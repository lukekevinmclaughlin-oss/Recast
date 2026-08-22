import Foundation
import PDFKit
import ImageIO
import CoreGraphics

/// PDF handling via PDFKit / CoreGraphics: rasterize the first page to an image,
/// or extract the full text. Works on macOS and iOS.
struct PDFBackend: ConversionBackend {
    let id = "pdfkit"
    var isAvailable: Bool { true }

    func edges() -> [FormatEdge] {
        var e: [FormatEdge] = []
        for img in ["png", "jpeg", "tiff"] {
            e.append(FormatEdge(from: "pdf", to: img, backendID: id, cost: 1.5))
        }
        e.append(FormatEdge(from: "pdf", to: "txt", backendID: id, cost: 1.3))
        return e
    }

    func convert(source: URL, from: Format, to: Format,
                 options: ConversionOptions,
                 progress: @Sendable @escaping (Double) -> Void) async throws -> URL {
        guard let doc = CGPDFDocument(source as CFURL), doc.numberOfPages > 0 else {
            throw ConversionError.readFailed
        }
        let out = tempURL(for: to)

        if to.id == "txt" {
            let text = PDFDocument(url: source)?.string ?? ""
            try text.data(using: .utf8)?.write(to: out)
            progress(1); return out
        }

        // rasterize page 1
        guard let page = doc.page(at: 1) else { throw ConversionError.readFailed }
        let box = page.getBoxRect(.mediaBox)
        let baseScale: CGFloat = 2.0
        var scale = baseScale
        if let maxDim = options.maxDimension {
            let longest = max(box.width, box.height) * baseScale
            if longest > CGFloat(maxDim) { scale = CGFloat(maxDim) / max(box.width, box.height) }
        }
        let w = Int(box.width * scale), h = Int(box.height * scale)
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            throw ConversionError.writeFailed
        }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        ctx.drawPDFPage(page)
        guard let image = ctx.makeImage() else { throw ConversionError.writeFailed }

        guard let uti = to.uti as CFString?,
              let dest = CGImageDestinationCreateWithURL(out as CFURL, uti, 1, nil) else {
            throw ConversionError.writeFailed
        }
        CGImageDestinationAddImage(dest, image,
                                   [kCGImageDestinationLossyCompressionQuality: options.imageQuality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ConversionError.writeFailed }
        progress(1)
        return out
    }
}
