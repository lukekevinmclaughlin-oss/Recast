import { spawn } from "node:child_process";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import type { Format } from "./catalog";
import type { ConversionOptions } from "./converters";

const root = path.resolve(__dirname, "..").replace("app.asar", "app.asar.unpacked");
export const imageEnginePath = path.join(root, "vendor", "imagemagick", "magick.exe");

export async function runImageEngine(args: string[], temporary: string, signal: AbortSignal): Promise<void> {
  if (signal.aborted) throw new Error("Conversion cancelled.");
  await new Promise<void>((resolve, reject) => {
    const child = spawn(imageEnginePath, args, { windowsHide: true, cwd: temporary,
      env: { ...process.env, MAGICK_CONFIGURE_PATH: path.join(root, "native", "image-policy"), MAGICK_TEMPORARY_PATH: temporary },
    });
    let diagnostics = "";
    let timedOut = false;
    const cancel = () => child.kill();
    signal.addEventListener("abort", cancel, { once: true });
    const timeout = setTimeout(() => { timedOut = true; child.kill(); }, 125_000);
    const cleanup = () => { clearTimeout(timeout); signal.removeEventListener("abort", cancel); };
    child.stdout.resume();
    child.stderr.on("data", (data: Buffer) => { diagnostics = (diagnostics + data.toString()).slice(-8000); });
    child.once("error", error => { cleanup(); reject(error); });
    child.once("close", code => {
      cleanup();
      if (signal.aborted) reject(new Error("Conversion cancelled."));
      else if (timedOut) reject(new Error("Image conversion exceeded the two-minute limit."));
      else if (code !== 0) reject(new Error(diagnostics.trim() || "The local image engine could not convert this file."));
      else resolve();
    });
  });
}

// Current Apple icon bundles contain PNG or JPEG 2000 representations. Choose
// the largest representation, validating each chunk before reading it.
async function iconRepresentation(input: string): Promise<{ bytes: Buffer; extension: string }> {
  const bytes = await fs.readFile(input);
  if (bytes.length < 8 || bytes.toString("ascii", 0, 4) !== "icns" || bytes.readUInt32BE(4) !== bytes.length) throw new Error("Invalid Apple icon container.");
  const choices: Array<{ bytes: Buffer; extension: string; size: number }> = [];
  const sizes: Record<string, number> = { icp4:16, icp5:32, icp6:64, ic07:128, ic08:256, ic09:512, ic10:1024, ic11:32, ic12:64, ic13:256, ic14:512 };
  for (let offset = 8; offset < bytes.length;) {
    if (offset + 8 > bytes.length) throw new Error("Truncated Apple icon chunk.");
    const type = bytes.toString("ascii", offset, offset + 4);
    const length = bytes.readUInt32BE(offset + 4);
    if (length < 8 || offset + length > bytes.length) throw new Error("Invalid Apple icon chunk length.");
    const data = bytes.subarray(offset + 8, offset + length);
    const png = data.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10]));
    const jp2 = data.length >= 12 && data.toString("ascii", 4, 8) === "jP  ";
    if (sizes[type] && (png || jp2)) choices.push({ bytes:data, extension:png ? "png" : "jp2", size:sizes[type] });
    offset += length;
  }
  const selected = choices.sort((a,b) => b.size - a.size)[0];
  if (!selected) throw new Error("This legacy Apple icon has no supported PNG or JPEG 2000 representation.");
  return selected;
}

export async function convertRaster(input: string, source: Format, target: Format, output: string, options: ConversionOptions, signal: AbortSignal): Promise<void> {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "recast-image-"));
  try {
    // Copy to a simple local filename so input names cannot become coder syntax,
    // options, globs or ImageMagick frame selectors.
    if ((await fs.stat(input)).size > 512 * 1024 * 1024) throw new Error("This image exceeds the 512 MB input limit.");
    let extension = source.ext;
    if (source.id === "icns") {
      const representation = await iconRepresentation(input);
      extension = representation.extension;
      await fs.writeFile(path.join(directory, `input.${extension}`), representation.bytes);
    } else await fs.copyFile(input, path.join(directory, `input.${extension}`));
    const result = path.join(directory, `output.${target.ext}`);
    const args = [`input.${extension}[0]`, "-auto-orient"];
    if (options.resizeEnabled) args.push("-resize", `${Math.max(1,Math.min(32768,Math.round(options.maxDimension)))}x${Math.max(1,Math.min(32768,Math.round(options.maxDimension)))}>`);
    if (!options.keepMetadata) args.push("-strip");
    if (target.id === "jpeg") args.push("-background", "white", "-alpha", "remove", "-alpha", "off");
    if (target.id === "ico") args.push("-resize", "256x256>");
    args.push("-quality", String(Math.max(10,Math.min(100,Math.round(options.imageQuality * 100)))), result);
    await runImageEngine(args, directory, signal);
    await fs.copyFile(result, output);
  } finally { await fs.rm(directory, { recursive:true, force:true }); }
}
