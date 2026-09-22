import * as TOML from "@iarna/toml";
import { createCanvas, DOMMatrix, ImageData, Path2D } from "@napi-rs/canvas";
import { Resvg } from "@resvg/resvg-js";
import archiver from "archiver";
import { XMLBuilder, XMLParser } from "fast-xml-parser";
import ffmpegStatic from "ffmpeg-static";
import yaml from "js-yaml";
import Papa from "papaparse";
import { PDFDocument } from "pdf-lib";
import plist from "plist";
import sharp, { type Sharp } from "sharp";
import { spawn } from "node:child_process";
import { constants, createReadStream, createWriteStream, promises as fs } from "node:fs";
import { pipeline } from "node:stream/promises";
import { createGzip } from "node:zlib";
import os from "node:os";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { byId, plan, type Edge, type Format } from "./catalog";
import { convertRaster } from "./image-engine";
import { convertRichDocument } from "./document-engine";

export interface ConversionOptions {
  imageQuality: number;
  resizeEnabled: boolean;
  maxDimension: number;
  keepMetadata: boolean;
  videoQuality: "same" | "p1080" | "p720";
  namingSuffix: string;
  destination: { mode: "next" | "exports" | "folder"; folder?: string };
}

export interface ConversionResult { outputPath: string; outputSize: number }
type Progress = (value: number) => void;

const tempFile = (format: Format) => path.join(os.tmpdir(), `recast-${randomUUID()}.${format.ext}`);
const checkCancelled = (signal: AbortSignal) => { if (signal.aborted) throw new Error("Conversion cancelled."); };

async function imageToPdf(image: Sharp, output: string): Promise<void> {
  const png = await image.png().toBuffer();
  const metadata = await sharp(png).metadata();
  const pdf = await PDFDocument.create();
  const embedded = await pdf.embedPng(png);
  const width = metadata.width ?? embedded.width; const height = metadata.height ?? embedded.height;
  const page = pdf.addPage([width, height]); page.drawImage(embedded, { x: 0, y: 0, width, height });
  await fs.writeFile(output, await pdf.save());
}

async function convertImage(input: string, source: Format, target: Format, output: string, options: ConversionOptions, signal: AbortSignal): Promise<void> {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "recast-raster-"));
  try {
    let sourcePath = input;
    let sourceFormat = source;
    if (source.id === "svg") {
      sourcePath = path.join(directory, "vector.png");
      await fs.writeFile(sourcePath, new Resvg(await fs.readFile(input)).render().asPng());
      sourceFormat = byId.get("png")!;
    }
    if (target.id === "pdf") {
      const png = path.join(directory, "page.png");
      await convertRaster(sourcePath, sourceFormat, byId.get("png")!, png, options, signal);
      await imageToPdf(sharp(png), output);
    } else await convertRaster(sourcePath, sourceFormat, target, output, options, signal);
  } finally { await fs.rm(directory, { recursive: true, force: true }); }
}

async function loadPdf(input: string) {
  Object.assign(globalThis, { DOMMatrix, ImageData, Path2D });
  const pdfjs = await import("pdfjs-dist/legacy/build/pdf.mjs");
  const assets = path.dirname(require.resolve("pdfjs-dist/package.json"));
  return pdfjs.getDocument({
    data: new Uint8Array(await fs.readFile(input)),
    useSystemFonts: false,
    standardFontDataUrl: path.join(assets, "standard_fonts") + path.sep,
    cMapUrl: path.join(assets, "cmaps") + path.sep,
    cMapPacked: true,
    isEvalSupported: false,
  }).promise;
}

async function convertPdf(input: string, target: Format, output: string, options: ConversionOptions, signal: AbortSignal): Promise<void> {
  const document = await loadPdf(input);
  try {
  if (target.id === "txt") {
    const pages: string[] = [];
    for (let index = 1; index <= document.numPages; index += 1) {
      checkCancelled(signal);
      const content = await (await document.getPage(index)).getTextContent();
      pages.push(content.items.map((item) => "str" in item ? item.str : "").join(" "));
    }
    await fs.writeFile(output, pages.join("\n\n"), "utf8"); return;
  }
  const page = await document.getPage(1);
  const base = page.getViewport({ scale: 2 });
  const scale = options.resizeEnabled && Math.max(base.width, base.height) > options.maxDimension ? options.maxDimension / Math.max(base.width, base.height) * 2 : 2;
  const viewport = page.getViewport({ scale });
  const canvas = createCanvas(Math.ceil(viewport.width), Math.ceil(viewport.height));
  const context = canvas.getContext("2d");
  await page.render({ canvasContext: context as never, viewport }).promise;
  const png = canvas.toBuffer("image/png");
  const pseudoSource = byId.get("png")!;
  const temporary = path.join(os.tmpdir(), `recast-pdf-${randomUUID()}.png`);
  await fs.writeFile(temporary, png);
  try { await convertImage(temporary, pseudoSource, target, output, options, signal); } finally { await fs.rm(temporary, { force: true }); }
  } finally { await document.destroy(); }
}

function decodeData(text: string, format: string): unknown {
  switch (format) {
    case "json": return JSON.parse(text);
    case "yaml": return yaml.load(text);
    case "xml": return new XMLParser({ ignoreAttributes: false }).parse(text);
    case "plist": return plist.parse(text);
    case "csv": return Papa.parse(text, { header: true, dynamicTyping: true, skipEmptyLines: true }).data;
    case "tsv": return Papa.parse(text, { header: true, dynamicTyping: true, skipEmptyLines: true, delimiter: "\t" }).data;
    case "toml": return TOML.parse(text);
    default: throw new Error(`Unsupported structured-data input: ${format}`);
  }
}

function encodeData(value: unknown, format: string): string {
  switch (format) {
    case "json": return JSON.stringify(value, null, 2);
    case "yaml": return yaml.dump(value, { noRefs: true, sortKeys: true });
    case "xml": return new XMLBuilder({ ignoreAttributes: false, format: true }).build(value as object);
    case "plist": return plist.build(value as plist.PlistValue);
    case "csv": return Papa.unparse(value as Papa.UnparseObject<unknown> | unknown[]);
    case "tsv": return Papa.unparse(value as Papa.UnparseObject<unknown> | unknown[], { delimiter: "\t" });
    case "toml": return TOML.stringify(value as TOML.JsonMap);
    default: throw new Error(`Unsupported structured-data output: ${format}`);
  }
}

async function convertData(input: string, source: Format, target: Format, output: string): Promise<void> {
  const value = decodeData(await fs.readFile(input, "utf8"), source.id);
  await fs.writeFile(output, encodeData(value, target.id), "utf8");
}

async function runFfmpeg(input: string, target: Format, output: string, options: ConversionOptions, signal: AbortSignal, progress: Progress): Promise<void> {
  if (!ffmpegStatic) throw new Error("The bundled FFmpeg executable is unavailable.");
  const executable = ffmpegStatic.replace("app.asar", "app.asar.unpacked");
  const args = ["-y", "-i", input];
  if (target.category === "audio") args.push("-vn");
  if (target.id === "mp3") args.push("-q:a", "2");
  if (target.id === "gifv") args.push("-vf", "fps=12,scale=480:-1:flags=lanczos");
  else if (target.category === "video" && options.videoQuality !== "same") args.push("-vf", `scale=-2:${options.videoQuality === "p720" ? 720 : 1080}`);
  args.push(output);
  await new Promise<void>((resolvePromise, rejectPromise) => {
    const process = spawn(executable, args, { windowsHide: true }); let stderr = ""; let duration = 0;
    const cancel = () => process.kill(); signal.addEventListener("abort", cancel, { once: true });
    process.stderr.on("data", (chunk: Buffer) => {
      stderr += chunk.toString(); if (stderr.length > 16000) stderr = stderr.slice(-12000);
      const durationMatch = stderr.match(/Duration:\s*(\d+):(\d+):([\d.]+)/); if (durationMatch) duration = Number(durationMatch[1]) * 3600 + Number(durationMatch[2]) * 60 + Number(durationMatch[3]);
      const times = [...stderr.matchAll(/time=(\d+):(\d+):([\d.]+)/g)]; const last = times.at(-1);
      if (last && duration) progress(Math.min(0.98, (Number(last[1]) * 3600 + Number(last[2]) * 60 + Number(last[3])) / duration));
    });
    process.on("error", rejectPromise);
    process.on("close", (code) => { signal.removeEventListener("abort", cancel); if (signal.aborted) rejectPromise(new Error("Conversion cancelled.")); else if (code === 0) resolvePromise(); else rejectPromise(new Error(stderr.trim().split(/\r?\n/).at(-1) || "FFmpeg conversion failed.")); });
  });
}

async function convertArchive(input: string, target: Format, output: string): Promise<void> {
  if (target.id === "gz") { await pipeline(createReadStream(input), createGzip({ level: 9 }), createWriteStream(output)); return; }
  await new Promise<void>((resolvePromise, rejectPromise) => {
    const destination = createWriteStream(output);
    const archive = target.id === "zip" ? archiver("zip", { zlib: { level: 9 } }) : archiver("tar", target.id === "targz" ? { gzip: true, gzipOptions: { level: 9 } } : {});
    destination.on("close", resolvePromise); archive.on("error", rejectPromise); archive.pipe(destination); archive.file(input, { name: path.basename(input) }); void archive.finalize();
  });
}

async function execute(edge: Edge, input: string, output: string, options: ConversionOptions, signal: AbortSignal, progress: Progress): Promise<void> {
  checkCancelled(signal); const source = byId.get(edge.from)!; const target = byId.get(edge.to)!;
  switch (edge.backend) {
    case "image": await convertImage(input, source, target, output, options, signal); break;
    case "pdf": await convertPdf(input, target, output, options, signal); break;
    case "data": await convertData(input, source, target, output); break;
    case "document": await convertRichDocument(input, source, target, output, signal); break;
    case "media": await runFfmpeg(input, target, output, options, signal, progress); break;
    case "archive": await convertArchive(input, target, output); break;
  }
  checkCancelled(signal);
}

function baseName(input: string): string {
  const name = path.basename(input); return name.toLowerCase().endsWith(".tar.gz") ? name.slice(0, -7) : path.parse(name).name;
}

async function outputDirectory(input: string, options: ConversionOptions): Promise<string> {
  if (options.destination.mode === "next") return path.dirname(input);
  if (options.destination.mode === "folder" && options.destination.folder) return options.destination.folder;
  return path.join(os.homedir(), "Documents", "Recast Exports");
}

async function saveOutput(converted: string, input: string, target: Format, options: ConversionOptions, signal: AbortSignal): Promise<string> {
  if (/[<>:"/\\|?*]/.test(options.namingSuffix) || [...options.namingSuffix].some(character => character.charCodeAt(0) < 32)) throw new Error("The filename suffix contains characters Windows cannot use.");
  const directory = await outputDirectory(input, options); await fs.mkdir(directory, { recursive: true });
  const stem = `${baseName(input)}${options.namingSuffix}`; let candidate = path.join(directory, `${stem}.${target.ext}`); let counter = 2;
  for (;;) {
    checkCancelled(signal);
    try {
      await fs.copyFile(converted, candidate, constants.COPYFILE_EXCL);
      return candidate;
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
      candidate = path.join(directory, `${stem} ${counter++}.${target.ext}`);
    }
  }
}

export async function convertFile(input: string, from: string, to: string, options: ConversionOptions, signal: AbortSignal, progress: Progress): Promise<ConversionResult> {
  const route = plan(from, to); const target = byId.get(to);
  if (!route?.length || !target) throw new Error(`No conversion path from ${from} to ${to}.`);
  let current = input; const temporary: string[] = [];
  try {
    for (let index = 0; index < route.length; index += 1) {
      const stepTarget = byId.get(route[index].to)!; const output = tempFile(stepTarget); temporary.push(output);
      await execute(route[index], current, output, options, signal, (value) => progress((index + value) / route.length)); current = output; progress((index + 1) / route.length);
    }
    const destination = await saveOutput(current, input, target, options, signal); progress(1);
    return { outputPath: destination, outputSize: (await fs.stat(destination)).size };
  } finally {
    await Promise.all(temporary.map((file) => fs.rm(file, { force: true }).catch(() => undefined)));
  }
}
