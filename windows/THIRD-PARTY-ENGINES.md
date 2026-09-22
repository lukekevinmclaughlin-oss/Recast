# Native conversion engines

Image conversion uses the unmodified official ImageMagick 7.1.2-31 Q16-HDRI x64 portable executable, Copyright ImageMagick Studio LLC. Its license and notice are retained beside the executable in `vendor/imagemagick/` and included in packaging. The build script pins the upstream archive and each bundled file by SHA-256.

Upstream distribution: https://download.imagemagick.org/archive/binaries/ImageMagick-7.1.2-31-portable-Q16-HDRI-x64.7z

License: https://imagemagick.org/license/

Security policy: https://imagemagick.org/security-policy/

Recast runs this engine as a separate local process. Its policy disables external delegates, filters, indirect file reads and non-image coders, and limits memory, disk and execution time. Input filenames are normalized through private temporary copies. SVG rendering uses the existing resvg engine; PDF rendering uses PDF.js.

This Windows engine decodes HEIC but does not encode HEVC. HEIC output is unavailable; AVIF is exposed separately and receives the correct extension. Apple icon import currently supports PNG and JPEG 2000 icon representations and reports older unsupported representations explicitly.

Rich documents use an unmodified LibreOffice 26.8.0 Windows x64 engine extracted from The Document Foundation's signed MSI. The package checksum is `4aa6c6e1895f4055104effcb556bd3362d20c6ad707c149543304f395ef9db95`. No system installation or file-association changes are needed. Its LICENSE.html, license.txt, NOTICE and bundled component notices are retained. See https://www.libreoffice.org/about-us/licenses/ and https://www.libreoffice.org/download/.

Markup and EPUB conversions use unmodified Pandoc 3.11, Copyright John MacFarlane and contributors, distributed under GPL-2.0-or-later. COPYRIGHT.txt and COPYING.rtf are retained with the executable. The official Windows ZIP checksum is `2ab72baf2399450e148ddf7a2a8689806c42e1bba71862b57e220fd9b8456d3d`. See https://pandoc.org/installing.html and https://github.com/jgm/pandoc/releases/tag/3.11. Pandoc runs as a separate process with its sandbox enabled and no filters or external PDF engine. LibreOffice uses a private conversion profile with macros, active content and ordinary network proxy access disabled.

Release is still pending a complete notice/source-availability audit for ImageMagick's bundled delegates, FFmpeg and the other packaged dependencies. This file records provenance; it does not replace those third-party notices or any required corresponding source distribution.
