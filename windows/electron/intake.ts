import { promises as fs } from "node:fs";
import path from "node:path";

// Do not traverse directory links/junctions: a dropped folder can otherwise loop
// or silently include files outside the tree the user chose.
export async function expandPaths(inputs: string[], limit = 10_000): Promise<string[]> {
  const files: string[] = [];
  const visited = new Set<string>();
  const visit = async (input: string): Promise<void> => {
    const resolved = path.resolve(input);
    const identity = process.platform === "win32" ? resolved.toLowerCase() : resolved;
    if (visited.has(identity)) return;
    visited.add(identity);
    const stat = await fs.lstat(resolved).catch(() => null);
    if (!stat || stat.isSymbolicLink()) return;
    if (stat.isFile()) {
      if (files.length >= limit) throw new Error(`Choose up to ${limit.toLocaleString()} files at a time.`);
      files.push(resolved);
    } else if (stat.isDirectory()) {
      if (resolved.toLowerCase().endsWith(".rtfd")) throw new Error("RTFD document bundles are not supported yet. Export the document as RTF or DOCX before converting it.");
      const entries = await fs.readdir(resolved, { withFileTypes: true });
      for (const entry of entries) if (!entry.name.startsWith(".")) await visit(path.join(resolved, entry.name));
    }
  };
  for (const input of inputs) await visit(input);
  return files;
}
