import * as TOML from "@iarna/toml";
import { createCanvas, DOMMatrix, ImageData, Path2D } from "@napi-rs/canvas";
import { Resvg } from "@resvg/resvg-js";
import AdmZip from "adm-zip";
import archiver from "archiver";
import bmp from "bmp-js";
import { Document, Packer, Paragraph } from "docx";
import { XMLBuilder, XMLParser } from "fast-xml-parser";
import ffmpegStatic from "ffmpeg-static";
import { convert as htmlToText } from "html-to-text";
import yaml from "js-yaml";
import mammoth from "mammoth";
import { marked } from "marked";
import Papa from "papaparse";
import { PDFDocument, StandardFonts, rgb } from "pdf-lib";
import plist from "plist";
import pngToIco from "png-to-ico";
import sharp, { type Sharp } from "sharp";
import TurndownService from "turndown";
import { spawn } from "node:child_process";
import { createReadStream, createWriteStream, promises as fs } from "node:fs";
import { pipeline } from "node:stream/promises";
import { createGzip } from "node:zlib";
import os from "node:os";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { byId, plan, type Edge, type Format } from "./catalog";

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
const quality = (options: ConversionOptions) => Math.max(10, Math.min(100, Math.round(options.imageQuality * 100)));
const checkCancelled = (signal: AbortSignal) => { if (signal.aborted) throw new Error("Conversion cancelled."); };

async function sourceImage(input: string, source: Format, options: ConversionOptions): Promise<Sharp> {
  let image: Sharp;
  if (source.id === "svg") {
    const svg = await fs.readFile(input);
    image = sharp(new Resvg(svg, { fitTo: options.resizeEnabled ? { mode: "width", value: options.maxDimension } : undefined }).render().asPng());
  } else if (source.id === "bmp") {
    const decoded = bmp.decode(await fs.readFile(input));
    image = sharp(decoded.data, { raw: { width: decoded.width, height: decoded.height, channels: 4 } });
  } else {
    image = sharp(input, { animated: source.id === "gif" });
  }
  if (options.resizeEnabled) image = image.resize({ width: options.maxDimension, height: options.maxDimension, fit: "inside", withoutEnlargement: true });
  if (options.keepMetadata) image = image.withMetadata();
  return image;
}

async function writePpm(image: Sharp, output: string): Promise<void> {
  const { data, info } = await image.removeAlpha().raw().toBuffer({ resolveWithObject: true });
  await fs.writeFile(output, Buffer.concat([Buffer.from(`P6\n${info.width} ${info.height}\n255\n`, "ascii"), data]));
}

async function writeTga(image: Sharp, output: string): Promise<void> {
  const { data, info } = await image.ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const header = Buffer.alloc(18);
  header[2] = 2; header.writeUInt16LE(info.width, 12); header.writeUInt16LE(info.height, 14); header[16] = 32; header[17] = 0x28;
  const pixels = Buffer.alloc(data.length);
  for (let index = 0; index < data.length; index += 4) {
    pixels[index] = data[index + 2]; pixels[index + 1] = data[index + 1]; pixels[index + 2] = data[index]; pixels[index + 3] = data[index + 3];
  }
  await fs.writeFile(output, Buffer.concat([header, pixels]));
}

async function imageToPdf(image: Sharp, output: string): Promise<void> {
  const png = await image.png().toBuffer();
  const metadata = await sharp(png).metadata();
  const pdf = await PDFDocument.create();
  const embedded = await pdf.embedPng(png);
  const width = metadata.width ?? embedded.width; const height = metadata.height ?? embedded.height;
  const page = pdf.addPage([width, height]); page.drawImage(embedded, { x: 0, y: 0, width, height });
  await fs.writeFile(output, await pdf.save());
}

async function convertImage(input: string, source: Format, target: Format, output: string, options: ConversionOptions): Promise<void> {
  const image = await sourceImage(input, source, options);
  if (target.id === "pdf") return imageToPdf(image, output);
  if (target.id === "ppm") return writePpm(image, output);
  if (target.id === "tga") return writeTga(image, output);
  if (target.id === "bmp") {
    const { data, info } = await image.ensureAlpha().raw().toBuffer({ resolveWithObject: true });
    await fs.writeFile(output, bmp.encode({ data, width: info.width, height: info.height }).data); return;
  }
  if (target.id === "ico") {
    await fs.writeFile(output, await pngToIco(await image.resize({ width: 256, height: 256, fit: "inside" }).png().toBuffer())); return;
  }
  switch (target.id) {
    case "jpeg": await image.flatten({ background: "white" }).jpeg({ quality: quality(options) }).toFile(output); break;
    case "png": await image.png().toFile(output); break;
    case "webp": await image.webp({ quality: quality(options) }).toFile(output); break;
    case "tiff": await image.tiff({ quality: quality(options) }).toFile(output); break;
    case "gif": await image.gif().toFile(output); break;
    case "avif": await image.avif({ quality: quality(options) }).toFile(output); break;
    case "heic": await image.heif({ quality: quality(options), compression: "av1" }).toFile(output); break;
    case "jxl": await image.toFormat("jxl").toFile(output); break;
    default: throw new Error(`No local image writer is available for ${target.name}.`);
  }
}

async function loadPdf(input: string) {
  Object.assign(globalThis, { DOMMatrix, ImageData, Path2D });
  const pdfjs = await import("pdfjs-dist/legacy/build/pdf.mjs");
  return pdfjs.getDocument({ data: new Uint8Array(await fs.readFile(input)), useSystemFonts: true }).promise;
}

async function convertPdf(input: string, target: Format, output: string, options: ConversionOptions): Promise<void> {
  const document = await loadPdf(input);
  if (target.id === "txt") {
    const pages: string[] = [];
    for (let index = 1; index <= document.numPages; index += 1) {
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
  try { await convertImage(temporary, pseudoSource, target, output, options); } finally { await fs.rm(temporary, { force: true }); }
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

interface DocumentContent { text: string; html: string }
const escapeHtml = (value: string) => value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
const decodeEntities = (value: string) => value.replaceAll("&lt;", "<").replaceAll("&gt;", ">").replaceAll("&amp;", "&").replaceAll("&quot;", "\"").replaceAll("&#39;", "'");
const textToHtml = (text: string) => `<p>${escapeHtml(text).replace(/\r?\n\r?\n/g, "</p><p>").replace(/\r?\n/g, "<br>")}</p>`;
const stripXml = (value: string) => decodeEntities(value.replace(/<text:tab[^>]*\/>/g, "\t").replace(/<text:line-break[^>]*\/>/g, "\n").replace(/<\/text:p>/g, "\n").replace(/<[^>]+>/g, " ").replace(/[ \t]+/g, " ").replace(/\n +/g, "\n").trim());
const stripRtf = (value: string) => value.replace(/\\par[d]?/g, "\n").replace(/\\'[0-9a-fA-F]{2}/g, "").replace(/\\[a-z]+-?\d* ?/g, "").replace(/[{}]/g, "").trim();

async function readDocument(input: string, source: Format): Promise<DocumentContent> {
  if (source.id === "docx") {
    const buffer = await fs.readFile(input);
    const [raw, converted] = await Promise.all([mammoth.extractRawText({ buffer }), mammoth.convertToHtml({ buffer })]);
    return { text: raw.value, html: converted.value };
  }
  if (["odt", "epub"].includes(source.id)) {
    const zip = new AdmZip(input);
    const entries = source.id === "odt" ? zip.getEntries().filter((entry) => entry.entryName === "content.xml") : zip.getEntries().filter((entry) => /\.(x?html?)$/i.test(entry.entryName));
    const html = entries.map((entry) => entry.getData().toString("utf8")).join("\n");
    return { text: stripXml(html), html };
  }
  const raw = await fs.readFile(input, "utf8");
  if (["rtf", "rtfd", "doc"].includes(source.id)) { const text = stripRtf(raw); return { text, html: textToHtml(text) }; }
  if (source.id === "html") return { text: htmlToText(raw), html: raw };
  if (source.id === "md") return { text: raw, html: String(await marked.parse(raw)) };
  return { text: raw, html: textToHtml(raw) };
}

const rtf = (text: string) => `{\\rtf1\\ansi\\deff0 ${text.replaceAll("\\", "\\\\").replaceAll("{", "\\{").replaceAll("}", "\\}").replace(/\r?\n/g, "\\par\n")}}`;

async function writeTextPdf(text: string, output: string): Promise<void> {
  const pdf = await PDFDocument.create(); const font = await pdf.embedFont(StandardFonts.Helvetica);
  const size = 11; const lineHeight = 15; const maxWidth = 516; const lines: string[] = [];
  for (const paragraph of text.split(/\r?\n/)) {
    let line = "";
    for (const word of paragraph.split(/\s+/)) {
      const candidate = line ? `${line} ${word}` : word;
      if (font.widthOfTextAtSize(candidate, size) > maxWidth && line) { lines.push(line); line = word; } else line = candidate;
    }
    lines.push(line); if (!paragraph) lines.push("");
  }
  let page = pdf.addPage([612, 792]); let y = 744;
  for (const line of lines) {
    if (y < 48) { page = pdf.addPage([612, 792]); y = 744; }
    page.drawText(line, { x: 48, y, size, font, color: rgb(0.08, 0.1, 0.14) }); y -= lineHeight;
  }
  await fs.writeFile(output, await pdf.save());
}

function odtArchive(content: DocumentContent): AdmZip {
  const zip = new AdmZip();
  zip.addFile("mimetype", Buffer.from("application/vnd.oasis.opendocument.text"));
  zip.addFile("content.xml", Buffer.from(`<?xml version="1.0" encoding="UTF-8"?><office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"><office:body><office:text>${content.text.split(/\r?\n/).map((line) => `<text:p>${escapeHtml(line)}</text:p>`).join("")}</office:text></office:body></office:document-content>`));
  zip.addFile("META-INF/manifest.xml", Buffer.from(`<?xml version="1.0"?><manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0"><manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.text"/><manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/></manifest:manifest>`));
  return zip;
}

function epubArchive(content: DocumentContent): AdmZip {
  const zip = new AdmZip(); zip.addFile("mimetype", Buffer.from("application/epub+zip"));
  zip.addFile("META-INF/container.xml", Buffer.from(`<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>`));
  zip.addFile("OEBPS/content.xhtml", Buffer.from(`<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>Recast Document</title></head><body>${content.html}</body></html>`));
  zip.addFile("OEBPS/content.opf", Buffer.from(`<?xml version="1.0"?><package version="3.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">urn:uuid:${randomUUID()}</dc:identifier><dc:title>Recast Document</dc:title><dc:language>en</dc:language></metadata><manifest><item id="content" href="content.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="content"/></spine></package>`));
  return zip;
}

async function convertDocument(input: string, source: Format, target: Format, output: string): Promise<void> {
  const content = await readDocument(input, source);
  switch (target.id) {
    case "txt": case "rst": case "tex": case "org": await fs.writeFile(output, content.text, "utf8"); break;
    case "html": await fs.writeFile(output, `<!doctype html><html><meta charset="utf-8"><body>${content.html}</body></html>`, "utf8"); break;
    case "md": await fs.writeFile(output, new TurndownService().turndown(content.html), "utf8"); break;
    case "rtf": case "rtfd": case "doc": await fs.writeFile(output, rtf(content.text), "utf8"); break;
    case "docx": {
      const document = new Document({ sections: [{ children: content.text.split(/\r?\n/).map((line) => new Paragraph(line)) }] });
      await fs.writeFile(output, await Packer.toBuffer(document)); break;
    }
    case "odt": odtArchive(content).writeZip(output); break;
    case "epub": epubArchive(content).writeZip(output); break;
    case "pdf": await writeTextPdf(content.text, output); break;
    default: throw new Error(`Unsupported document target: ${target.name}`);
  }
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
    case "image": await convertImage(input, source, target, output, options); break;
    case "pdf": await convertPdf(input, target, output, options); break;
    case "data": await convertData(input, source, target, output); break;
    case "document": await convertDocument(input, source, target, output); break;
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

async function uniqueOutput(input: string, target: Format, options: ConversionOptions): Promise<string> {
  const directory = await outputDirectory(input, options); await fs.mkdir(directory, { recursive: true });
  const stem = `${baseName(input)}${options.namingSuffix}`; let candidate = path.join(directory, `${stem}.${target.ext}`); let counter = 2;
  while (await fs.stat(candidate).then(() => true).catch(() => false)) candidate = path.join(directory, `${stem} ${counter++}.${target.ext}`);
  return candidate;
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
    const destination = await uniqueOutput(input, target, options);
    await fs.copyFile(current, destination); progress(1);
    return { outputPath: destination, outputSize: (await fs.stat(destination)).size };
  } finally {
    await Promise.all(temporary.map((file) => fs.rm(file, { force: true }).catch(() => undefined)));
  }
}
