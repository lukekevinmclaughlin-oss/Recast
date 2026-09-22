# Recast for Windows

The Windows edition lives entirely in this directory. The existing Swift, Xcode and macOS distribution files remain unchanged. This edition has the full local batch, folder, preset and command-line features enabled; it does not contain a subscription or trial gate.

## Use

Run `Recast.exe`, choose or drop files and select an available output format. Automatic conversion can be disabled in Settings. Save named presets for image quality, resizing, metadata, video size, output names and destination. Closing the window leaves the tray icon running; choose Quit from its menu to exit.

Conversions run locally. Source files and existing outputs are preserved; name collisions receive a numbered suffix. Folder intake skips links and junctions and accepts at most 10,000 files per operation. No conversion requires a cloud account.

Command-line example:

```powershell
& '.\Recast.exe' --convert 'C:\Input\report.docx' --to pdf --output 'C:\Output' --report 'C:\Output\results.json'
& '.\Recast.exe' --convert 'C:\Input\photo.png' --to webp --quality 85 --max-size 1600 --strip-metadata
& '.\Recast.exe' --formats
```

An existing report is preserved. Exit codes are 0 for success, 1 for conversion failures and 2 for invalid arguments. Run `--help` for all options.

## Format behavior

The bundled engines support images, local audio/video, PDF rendering and text extraction, rich Word/ODT/RTF documents, markup and EPUB, structured data, and archive creation. Output choices are derived from the installed conversion graph.

- HEIC is input-only; use AVIF, JPEG, PNG or another offered image output.
- Apple icon import supports PNG and JPEG 2000 representations; legacy RLE representations are not supported.
- RTFD document bundles are not supported. Export to RTF or DOCX first.
- Image and PDF raster output uses the first frame or page. PDF text extraction reads all pages. This is not OCR.
- Converting through plain text loses formatting. CSV/TSV represent tabular data and cannot preserve arbitrary nested structures.
- Macros, external document resources and active content are disabled. Complex documents can have layout differences; inspect important outputs.
- Video conversion can re-encode media. Archive outputs package the input file; archive extraction is not offered.

## Local development and packaging

Use Windows x64 with Node.js and pnpm. Run `pnpm install --frozen-lockfile`, then `pnpm run test`, `pnpm run lint` and `pnpm run build`. The preparation scripts retrieve checksum-pinned official ImageMagick, LibreOffice and Pandoc distributions into ignored `vendor/` folders. LibreOffice is extracted without a system installation. NSIS is required for the installer.

`pnpm run package:win` builds locally and explicitly disables publishing. GitHub Actions and Git LFS are not used. Do not commit `vendor/`, `node_modules/` or `release/`.

## Release status

This is a Windows release candidate, not yet approved for storefront sales. Packaged engines, browser-rendered UI flows and native command-line conversion have been exercised. Native window/tray/dialog/drag-drop behavior, installer/uninstaller behavior, code signing and the complete third-party source/notice distribution still require release checks. See `THIRD-PARTY-ENGINES.md` for provenance and licenses.
