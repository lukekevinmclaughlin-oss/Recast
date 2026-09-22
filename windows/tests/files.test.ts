import { expect, it } from "vitest";
import { promises as fs } from "node:fs";
import path from "node:path";
import os from "node:os";
import { convertFile, type ConversionOptions } from "../electron/converters";
import { expandPaths } from "../electron/intake";

it("simultaneous conversions keep existing files and each result", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "recast-collisions-"));
  try {
    const input = path.join(directory, "people.json"), existing = path.join(directory, "people.csv");
    await fs.writeFile(input, '[{"name":"Ada"}]'); await fs.writeFile(existing, "keep me");
    const options: ConversionOptions = { imageQuality: .85, resizeEnabled: false, maxDimension: 2048, keepMetadata: true, videoQuality: "same", namingSuffix: "", destination: { mode: "folder", folder: directory } };
    const results = await Promise.all(Array.from({ length: 12 }, () => convertFile(input, "json", "csv", options, new AbortController().signal, () => {})));
    expect(new Set(results.map(result => result.outputPath)).size).toBe(12);
    expect(await fs.readFile(existing, "utf8")).toBe("keep me");
    for (const result of results) expect(await fs.readFile(result.outputPath, "utf8")).toContain("Ada");
    await expect(convertFile(input, "json", "csv", { ...options, namingSuffix: "../escape" }, new AbortController().signal, () => {})).rejects.toThrow("suffix");
  } finally { await fs.rm(directory, { recursive: true, force: true }); }
});

it("folder intake skips junction loops, deduplicates and bounds the queue", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "recast-intake-"));
  try {
    const file = path.join(directory, "one.txt"); await fs.writeFile(file, "one");
    await fs.symlink(directory, path.join(directory, "loop"), "junction");
    expect(await expandPaths([directory, file])).toEqual([file]);
    await fs.writeFile(path.join(directory, "two.txt"), "two");
    await expect(expandPaths([directory], 1)).rejects.toThrow("up to 1");
    const bundle = path.join(directory, "document.rtfd"); await fs.mkdir(bundle);
    await fs.writeFile(path.join(bundle, "TXT.rtf"), "{\\rtf1 example}");
    await expect(expandPaths([bundle])).rejects.toThrow("RTFD document bundles");
  } finally { await fs.rm(directory, { recursive: true, force: true }); }
});
