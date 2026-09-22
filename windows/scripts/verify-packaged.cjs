// Run using the packaged Electron executable with ELECTRON_RUN_AS_NODE=1.
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const assert = require('node:assert/strict');
const { createRequire } = require('node:module');

async function main() {
  const archive = path.resolve(__dirname, '../release/win-unpacked/resources/app.asar');
  const packagedRequire = createRequire(path.join(archive, 'package.json'));
  const { convertFile } = packagedRequire('./dist-electron/converters.js');
  const sharp = packagedRequire('sharp');
  const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'recast-packaged-'));
  if (!temp.startsWith(path.join(os.tmpdir(), 'recast-packaged-'))) throw new Error('Unexpected test directory');
  const options = { imageQuality: 0.85, resizeEnabled: false, maxDimension: 2048, keepMetadata: true, videoQuality: 'same', namingSuffix: '', destination: { mode: 'folder', folder: temp } };
  const convert = (input, from, to) => convertFile(input, from, to, options, new AbortController().signal, () => {});
  const checks = [];
  try {
    const png = path.join(temp, 'sample.png');
    await sharp({ create: { width: 32, height: 24, channels: 4, background: '#12ab34' } }).png().toFile(png);
    const jpg = await convert(png, 'png', 'jpeg');
    assert.equal((await sharp(jpg.outputPath).metadata()).width, 32);
    checks.push('packaged native image engine');
    assert.ok((await fs.stat(path.join(archive,'build/icon.ico'))).size>0);
    const jxl = await convert(png,'png','jxl');
    assert.ok((await convert(jxl.outputPath,'jxl','png')).outputSize>0);
    checks.push('packaged real JPEG XL encoder and decoder');
    if(process.env.RECAST_HEIC_FIXTURE){
      const decoded=await convert(process.env.RECAST_HEIC_FIXTURE,'heic','png');
      const dimensions=await sharp(decoded.outputPath).metadata();
      assert.ok(dimensions.width>0&&dimensions.height>0);
      checks.push(`packaged HEIC decoder (${dimensions.width}x${dimensions.height})`);
    }
    const txt = path.join(temp, 'sample.txt');
    await fs.writeFile(txt, 'Packaged Recast Windows conversion test. Grüße — 日本語.');
    const pdf = await convert(txt, 'txt', 'pdf');
    const extracted = await convert(pdf.outputPath, 'pdf', 'txt');
    assert.match(await fs.readFile(extracted.outputPath, 'utf8'), /Packaged Recast/);
    assert.match(await fs.readFile(extracted.outputPath, 'utf8'), /日本語/);
    const raster = await convert(pdf.outputPath, 'pdf', 'png');
    assert.ok((await sharp(raster.outputPath).metadata()).width > 0);
    const pixels = await sharp(raster.outputPath).flatten({ background: '#fff' }).removeAlpha().raw().toBuffer();
    assert.ok(pixels.some(value => value < 100), 'PDF raster must contain visible text, not a blank page');
    checks.push('packaged PDF text and raster engines');
    const doc=await convert(txt,'txt','doc');
    assert.equal((await fs.readFile(doc.outputPath)).subarray(0,8).toString('hex'),'d0cf11e0a1b11ae1');
    const restored=await convert(doc.outputPath,'doc','txt');
    assert.match(await fs.readFile(restored.outputPath,'utf8'),/Grüße/);
    const md=path.join(temp,'sample.md');await fs.writeFile(md,'# Heading\n\n**Bold** café.');
    const epub=await convert(md,'md','epub');
    const docx=await convert(epub.outputPath,'epub','docx');
    assert.equal((await fs.readFile(docx.outputPath)).subarray(0,2).toString(),'PK');
    checks.push('packaged rich Word and Pandoc EPUB engines');
    const zip = await convert(txt, 'txt', 'zip');
    assert.equal((await fs.readFile(zip.outputPath)).subarray(0, 2).toString(), 'PK');
    checks.push('packaged archive engine');
    const rate = 16000, samples = 3200;
    const wav = Buffer.alloc(44 + samples * 2);
    wav.write('RIFF'); wav.writeUInt32LE(wav.length - 8, 4); wav.write('WAVEfmt ', 8);
    wav.writeUInt32LE(16, 16); wav.writeUInt16LE(1, 20); wav.writeUInt16LE(1, 22);
    wav.writeUInt32LE(rate, 24); wav.writeUInt32LE(rate * 2, 28); wav.writeUInt16LE(2, 32); wav.writeUInt16LE(16, 34);
    wav.write('data', 36); wav.writeUInt32LE(samples * 2, 40);
    for (let i = 0; i < samples; i++) wav.writeInt16LE(Math.round(Math.sin(i / rate * Math.PI * 880) * 12000), 44 + i * 2);
    const audio = path.join(temp, 'sample.wav'); await fs.writeFile(audio, wav);
    assert.ok((await convert(audio, 'wav', 'mp3')).outputSize > 500);
    checks.push('packaged FFmpeg audio conversion');
    await fs.writeFile(path.resolve(__dirname, '../release/packaged-verification.json'), JSON.stringify({ passed: true, checks, electron: process.versions.electron, node: process.version }, null, 2));
    console.log(checks.join('\n'));
  } finally {
    await fs.rm(temp, { recursive: true, force: true });
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
