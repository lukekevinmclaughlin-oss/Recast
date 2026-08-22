import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import sharp from "sharp";
import { convertFile, type ConversionOptions } from "../electron/converters";

let root = "";
const options = (): ConversionOptions => ({ imageQuality: 0.85, resizeEnabled: false, maxDimension: 2048, keepMetadata: true, videoQuality: "same", namingSuffix: "", destination: { mode: "folder", folder: root } });
const convert = (input: string, from: string, to: string) => convertFile(input, from, to, options(), new AbortController().signal, () => undefined);

function wav(seconds = 0.18): Buffer {
  const rate = 16_000; const samples = Math.floor(rate * seconds); const data = Buffer.alloc(samples * 2);
  for (let index = 0; index < samples; index += 1) data.writeInt16LE(Math.round(Math.sin(index / rate * Math.PI * 880) * 12_000), index * 2);
  const header = Buffer.alloc(44); header.write("RIFF", 0); header.writeUInt32LE(36 + data.length, 4); header.write("WAVEfmt ", 8); header.writeUInt32LE(16, 16); header.writeUInt16LE(1, 20); header.writeUInt16LE(1, 22); header.writeUInt32LE(rate, 24); header.writeUInt32LE(rate * 2, 28); header.writeUInt16LE(2, 32); header.writeUInt16LE(16, 34); header.write("data", 36); header.writeUInt32LE(data.length, 40);
  return Buffer.concat([header, data]);
}

beforeAll(async () => { root = await fs.mkdtemp(path.join(os.tmpdir(), "recast-test-")); });
afterAll(async () => { await fs.rm(root, { recursive: true, force: true }); });

describe("Recast local conversion engines", () => {
  it("converts structured data", async () => {
    const input = path.join(root, "people.json"); await fs.writeFile(input, JSON.stringify([{ name: "Ada", score: 99 }, { name: "Lin", score: 97 }]));
    const csv = await convert(input, "json", "csv"); const text = await fs.readFile(csv.outputPath, "utf8");
    expect(text).toContain("name"); expect(text).toContain("Ada"); expect(csv.outputSize).toBeGreaterThan(20);
  });

  it("writes valid DOCX and PDF documents and extracts PDF text", async () => {
    const input = path.join(root, "notes.txt"); await fs.writeFile(input, "Recast keeps this conversion on the Windows PC.\nSecond line.");
    const docx = await convert(input, "txt", "docx"); expect((await fs.readFile(docx.outputPath)).subarray(0, 2).toString()).toBe("PK");
    const pdf = await convert(input, "txt", "pdf"); expect((await fs.readFile(pdf.outputPath)).subarray(0, 4).toString()).toBe("%PDF");
    const extracted = await convert(pdf.outputPath, "pdf", "txt"); expect(await fs.readFile(extracted.outputPath, "utf8")).toContain("Recast keeps this conversion");
  }, 30_000);

  it("converts images and embeds them in PDF", async () => {
    const input = path.join(root, "cyan.png"); await sharp({ create: { width: 80, height: 50, channels: 4, background: "#4fe9f5" } }).png().toFile(input);
    const jpeg = await convert(input, "png", "jpeg"); expect((await fs.readFile(jpeg.outputPath)).subarray(0, 2)).toEqual(Buffer.from([0xff, 0xd8]));
    const pdf = await convert(input, "png", "pdf"); expect((await fs.readFile(pdf.outputPath)).subarray(0, 4).toString()).toBe("%PDF");
  });

  it("creates archives and performs a real bundled media conversion", async () => {
    const text = path.join(root, "archive-me.txt"); await fs.writeFile(text, "private local archive");
    const zip = await convert(text, "txt", "zip"); expect((await fs.readFile(zip.outputPath)).subarray(0, 2).toString()).toBe("PK");
    const input = path.join(root, "tone.wav"); await fs.writeFile(input, wav());
    const mp3 = await convert(input, "wav", "mp3"); expect(mp3.outputSize).toBeGreaterThan(500);
  }, 30_000);
});
