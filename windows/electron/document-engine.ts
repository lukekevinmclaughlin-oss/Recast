import { spawn } from "node:child_process";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import type { Format } from "./catalog";

const root = path.resolve(__dirname, "..").replace("app.asar", "app.asar.unpacked");
const office = path.join(root, "vendor", "libreoffice", "program", "soffice.com");
const pandoc = path.join(root, "vendor", "pandoc", "pandoc.exe");
const officeFormats: Record<string,string> = {
  doc: "MS Word 97", docx: "Office Open XML Text", odt: "writer8", rtf: "Rich Text Format", pdf: "writer_pdf_Export", txt: "Text (encoded):UTF8",
};
const nativeSources = new Set(["doc", "docx", "odt", "rtf", "txt"]);
const markupFormats: Record<string,string> = { md:"markdown", rst:"rst", tex:"latex", org:"org", html:"html", epub:"epub", docx:"docx", odt:"odt", rtf:"rtf", txt:"plain" };

export async function runDocumentProcess(executable: string, args: string[], directory: string, signal: AbortSignal): Promise<void> {
  if (signal.aborted) throw new Error("Conversion cancelled.");
  await new Promise<void>((resolve, reject) => {
    const child = spawn(executable, args, { windowsHide:true, cwd:directory });
    let output = "";
    let timedOut = false;
    const stop = () => {
      if (!child.pid || child.exitCode !== null) return;
      // soffice.com owns a soffice.bin child. Terminate only this conversion's
      // process tree, never the user's independently running office instance.
      if (process.platform === "win32") {
        const killer = spawn("taskkill.exe", ["/PID", String(child.pid), "/T", "/F"], { windowsHide:true, stdio:"ignore" });
        killer.on("error", () => child.kill());
      } else child.kill();
    };
    signal.addEventListener("abort", stop, { once:true });
    const timer = setTimeout(() => { timedOut = true; stop(); }, 120_000);
    const cleanup = () => { clearTimeout(timer); signal.removeEventListener("abort", stop); };
    const record = (data: Buffer) => { output = (output + data.toString()).slice(-8000); };
    child.stdout.on("data", record); child.stderr.on("data", record);
    child.once("error", error => { cleanup(); reject(error); });
    child.once("close", code => {
      cleanup();
      if (signal.aborted) reject(new Error("Conversion cancelled."));
      else if (timedOut) reject(new Error("Document conversion exceeded the two-minute limit."));
      else if (code !== 0) reject(new Error(output.trim() || `Document conversion failed (exit ${code}).`));
      else resolve();
    });
  });
}

async function prepareProfile(directory: string): Promise<string> {
  const profile = path.join(directory, "profile");
  await fs.mkdir(path.join(profile, "user"), {recursive:true});
  await fs.writeFile(path.join(profile, "user", "registrymodifications.xcu"), `<?xml version="1.0" encoding="UTF-8"?>
<oor:items xmlns:oor="http://openoffice.org/2001/registry">
<item oor:path="/org.openoffice.Office.Common/Security/Scripting">
<prop oor:name="DisableMacrosExecution" oor:op="fuse"><value>true</value></prop>
<prop oor:name="DisableActiveContent" oor:op="fuse"><value>true</value></prop>
<prop oor:name="DisablePythonRuntime" oor:op="fuse"><value>true</value></prop>
<prop oor:name="DisableOLEAutomation" oor:op="fuse"><value>true</value></prop>
<prop oor:name="BlockUntrustedRefererLinks" oor:op="fuse"><value>true</value></prop>
</item>
<item oor:path="/org.openoffice.Inet/Settings">
<prop oor:name="ooInetProxyType" oor:op="fuse"><value>2</value></prop>
<prop oor:name="ooInetHTTPProxyName" oor:op="fuse"><value>127.0.0.1</value></prop>
<prop oor:name="ooInetHTTPProxyPort" oor:op="fuse"><value>9</value></prop>
<prop oor:name="ooInetHTTPSProxyName" oor:op="fuse"><value>127.0.0.1</value></prop>
<prop oor:name="ooInetHTTPSProxyPort" oor:op="fuse"><value>9</value></prop>
<prop oor:name="ooInetFTPProxyName" oor:op="fuse"><value>127.0.0.1</value></prop>
<prop oor:name="ooInetFTPProxyPort" oor:op="fuse"><value>9</value></prop>
<prop oor:name="ooInetNoProxy" oor:op="fuse"><value></value></prop>
</item>
</oor:items>`, "utf8");
  return pathToFileURL(profile).href;
}

async function officeConvert(input: string, from: string, to: string, directory: string, signal: AbortSignal): Promise<string> {
  const outputDir = path.join(directory, `office-${to}`);
  await fs.mkdir(outputDir,{recursive:true});
  const profile = await prepareProfile(outputDir);
  const args = [`-env:UserInstallation=${profile}`, "--headless", "--norestore", "--nodefault", "--nofirststartwizard"];
  if (from === "txt") args.push("--infilter=Text (encoded):UTF8");
  args.push("--convert-to", `${to}:${officeFormats[to]}`, "--outdir", outputDir, input);
  await runDocumentProcess(office,args,directory,signal);
  const output = path.join(outputDir, `${path.parse(input).name}.${to}`);
  if (!(await fs.stat(output).catch(()=>null))?.size) throw new Error("The document engine could not read this file or produce the requested format.");
  return output;
}

async function markupConvert(input: string, from: string, to: string, output: string, directory: string, signal: AbortSignal): Promise<void> {
  const args = ["--sandbox", "--standalone", "--from", markupFormats[from], "--to", markupFormats[to], input, "--output", output];
  if (to === "html") args.push("--embed-resources");
  await runDocumentProcess(pandoc,args,directory,signal);
}

export async function convertRichDocument(input: string, source: Format, target: Format, output: string, signal: AbortSignal): Promise<void> {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(),"recast-document-"));
  try {
    if (source.id === "rtfd") throw new Error("RTFD attachment bundles are not yet supported by this Windows build. Export the source as RTF or DOCX.");
    if ((await fs.stat(input)).size > 256 * 1024 * 1024) throw new Error("This document exceeds the 256 MB input limit.");
    let current = path.join(directory,`input.${source.ext}`);
    if (["txt","md","rst","tex","org","html"].includes(source.id)) {
      const bytes = await fs.readFile(input);
      let text: string;
      if (bytes[0] === 0xff && bytes[1] === 0xfe) text = new TextDecoder("utf-16le").decode(bytes);
      else if (bytes[0] === 0xfe && bytes[1] === 0xff) text = new TextDecoder("utf-16be").decode(bytes);
      else { try { text = new TextDecoder("utf-8",{fatal:true}).decode(bytes); } catch { text = new TextDecoder("windows-1252").decode(bytes); } }
      await fs.writeFile(current,text,"utf8");
    } else await fs.copyFile(input,current);
    let format = source.id;
    if (officeFormats[target.id]) {
      if (!nativeSources.has(format)) {
        const intermediate = path.join(directory,"prepared.docx");
        await markupConvert(current,format,"docx",intermediate,directory,signal);
        current = intermediate; format = "docx";
      }
      if (format === target.id) await fs.copyFile(current,output);
      else await fs.copyFile(await officeConvert(current,format,target.id,directory,signal),output);
    } else {
      if (format === "doc") { current = await officeConvert(current,format,"docx",directory,signal); format = "docx"; }
      if (format === "txt") {
        // Pandoc has a plain-text writer but no literal plain-text reader.
        current = await officeConvert(current,format,"docx",directory,signal); format = "docx";
      }
      await markupConvert(current,format,target.id,output,directory,signal);
    }
  } finally { await fs.rm(directory,{recursive:true,force:true}); }
}
