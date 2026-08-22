# Recast — Universal File / Media Converter

Drop anything, get the format you need. On-device, private, frontier-level.

Native SwiftUI app for **macOS** (menu-bar agent + full window) and **iOS / iPadOS**.
A pluggable **capability-graph engine** routes any file to any reachable format,
chaining conversions when needed (e.g. `docx → html → pdf`).

## How it works — the capability graph

Every backend contributes directed edges (`from → to`) into one graph. To convert
A → B the engine runs **Dijkstra** over that graph, picking the lowest-cost path
(native beats external; lossless beats lossy) and executing each hop, writing
intermediates to temp and moving the final result into place atomically.

`ConversionEngine.reachableTargets(from:)` powers the "Convert to…" menu — it lists
*every* format your file can become, given the tools present right now.

### Backends

| Backend | Tech | Covers |
|---|---|---|
| `ImageBackend` | ImageIO | JPEG/PNG/HEIC/TIFF/GIF/BMP/ICO/…, image→PDF (read/write sets computed from the OS) |
| `AudioVideoBackend` | AVFoundation | M4A/WAV/AIFF/CAF, MP4/MOV, extract-audio |
| `PDFBackend` | PDFKit | PDF→PNG/JPEG/TIFF, PDF→text |
| `DocumentBackend` | AppKit (macOS) | Word .doc/.docx, ODT, RTF/RTFD, HTML, TXT ↔ each other, + →PDF (CoreText) |
| `DataBackend` | pure Swift | JSON ↔ YAML ↔ Plist ↔ CSV ↔ TSV |
| `ExternalToolBackend` | auto-detected CLIs (macOS) | **ffmpeg** (full A/V matrix incl. **MP3 encode**, MKV/WebM/FLAC/OGG, video→GIF), **rsvg** (SVG), **pandoc** (markdown/docs), **ImageMagick** (exotic images), **LibreOffice** (office→PDF), zip/gzip |

On this machine the graph currently wires up **57 formats and 524 conversions**
(Apple frameworks + ffmpeg + rsvg + zip). Install pandoc / ImageMagick /
LibreOffice and the graph widens automatically — no code changes.

> **Sandbox note.** External tools need subprocess execution, so this "direct/Pro"
> build is **not sandboxed** (hardened-runtime only). A Mac App Store variant would
> re-add `com.apple.security.app-sandbox` and fall back to the native backends
> (still covers HEIC→JPG, mov→mp4, docx→pdf, json→yaml, …). iOS is always sandboxed
> → native backends only (no external tools).

## UI

Dark **holographic HUD** with **Liquid Glass** (`.glassEffect` on macOS/iOS 26+,
`.ultraThinMaterial` fallback). Two macOS surfaces:

- **Menu-bar popover** — quick drop, capability readout, queue.
- **Full window** (`macwindow` button) — roomy two-pane layout: drop target +
  controls on the left, live results on the right, category explorer when idle.

Every queued file shows a **`source → [Convert to ▾]`** control listing all reachable
targets grouped by category. Animated scan-reticle drop zone, glowing progress bars,
`BrandMark` (mini rotating reticle). iOS mirrors the layout in one scrolling window.

## Freemium

Free = single-file conversion, every format. Pro (`com.lukemclaughlin.recast.pro`,
one-time IAP) = batch + folder drops + presets + automation. DEBUG has an unlock toggle.

## Build

```sh
cd Recast
xcodegen generate
open Recast.xcodeproj      # set a signing team, then Run
```

Unsigned CLI build: add `CODE_SIGNING_ALLOWED=NO` to `xcodebuild`.

## App icon

`Resources/make_logo.py` → a wireframe "data core" (projected icosahedron) being
scanned and assembled inside a HUD reticle. Rasterize with `rsvg-convert` into
`Assets.xcassets/AppIcon.appiconset`.
