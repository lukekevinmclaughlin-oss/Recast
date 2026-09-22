import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { mkdtemp, mkdir, readFile, writeFile, copyFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const target = join(root, 'vendor', 'imagemagick');
const url = 'https://download.imagemagick.org/archive/binaries/ImageMagick-7.1.2-31-portable-Q16-HDRI-x64.7z';
const archiveHash = 'a6a83a77a5284a2cae5ca4a81d95e5fad21ecd56cdb647ee99f970e233504fff';
const files = {
  'magick.exe': '6b6bd55206f23ed02738deda301c3c758738bb4d328c1c03c9a7ae778c3f960d',
  'colors.xml': '37b986dc355641021434859f77b5e1f30b21670c847706ee9b77418e0874dfa6',
  'LICENSE.txt': '5ffcbc771d4cc2827ca8c4505f6b5b61e0bc1d933e0f41a47eea16ed06db4f90',
  'NOTICE.txt': 'e0716b82a4aea7c6b3978398eadea7f35a19115d3d93c0b8e0b00d5c591ef1fc',
};
const hash = data => createHash('sha256').update(data).digest('hex');
const present = await Promise.all(Object.entries(files).map(async ([name, expected]) => {
  try { return hash(await readFile(join(target, name))) === expected; } catch { return false; }
}));
if (present.every(Boolean)) console.log('Pinned local ImageMagick engine verified.');
else {
  if (process.platform !== 'win32' || process.arch !== 'x64') throw new Error('This build requires Windows x64.');
  const temporary = await mkdtemp(join(tmpdir(), 'recast-engine-'));
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(120000) });
    if (!response.ok) throw new Error(`ImageMagick download returned ${response.status}`);
    const archive = Buffer.from(await response.arrayBuffer());
    if (hash(archive) !== archiveHash) throw new Error('ImageMagick archive checksum mismatch.');
    const archivePath = join(temporary, 'engine.7z');
    await writeFile(archivePath, archive);
    const result = spawnSync('tar.exe', ['-xf', archivePath, '-C', temporary, ...Object.keys(files)], { windowsHide: true, encoding:'utf8' });
    if (result.status !== 0) throw new Error(result.stderr || 'Windows tar extraction failed.');
    await mkdir(target, { recursive:true });
    for (const [name, expected] of Object.entries(files)) {
      if (hash(await readFile(join(temporary, name))) !== expected) throw new Error(`Unexpected engine file: ${name}`);
      await copyFile(join(temporary, name), join(target, name));
    }
    console.log('Pinned ImageMagick engine prepared locally; no GitHub Actions or LFS.');
  } finally { await rm(temporary, { recursive:true, force:true }); }
}
