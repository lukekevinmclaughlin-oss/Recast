import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Raster image conversion via ImageIO / CGImageDestination, plus image → PDF.
/// Edges are computed from what this OS build can actually read and write.
struct ImageBackend: ConversionBackend {
    let id = "imageio"
    var isAvailable: Bool { true }

    private static let readableUTIs: Set<String> =
        Set(CGImageSourceCopyTypeIdentifiers() as? [String] ?? [])
    private static let writableUTIs: Set<String> =
        Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])

    func edges() -> [FormatEdge] {
        let imageFormats = Catalog.formats(in: .image)
        let readable = imageFormats.filter { f in
            guard let u = f.uti else { return false }
            return Self.readableUTIs.contains(u)
        }
        let writable = imageFormats.filter { f in
            guard let u = f.uti else { return false }
            return Self.writableUTIs.contains(u)
        }
        var edges: [FormatEdge] = []
        for r in readable {
            for w in writable where r.id != w.id {
                edges.append(FormatEdge(from: r.id, to: w.id, backendID: id, cost: 1))
            }
            edges.append(FormatEdge(from: r.id, to: "pdf", backendID: id, cost: 1.2))
        }
        return edges
    }

    func convert(source: URL, from: Format, to: Format,
                 options: ConversionOptions,
                 progress: @Sendable @escaping (Double) -> Void) async throws -> URL {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              CGImageSourceGetCount(imageSource) > 0 else { throw ConversionError.readFailed }

        let cgImage = try loadImage(from: imageSource, maxDimension: options.maxDimension)
        let out = tempURL(for: to)

        if to.id == "pdf" {
            try writePDF(cgImage, to: out)
            progress(1); return out
        }

        guard let uti = to.uti as CFString? else {
            throw ConversionError.unsupportedTarget("No image writer for \(to.name).")
        }
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, uti, 1, nil) else {
            throw ConversionError.writeFailed
        }
        var props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: options.imageQuality]
        if options.keepMetadata,
           let sp = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] {
            for (k, v) in sp where props[k] == nil { props[k] = v }
            if options.maxDimension != nil { props[kCGImagePropertyOrientation] = 1 }
        }
        CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ConversionError.writeFailed }
        progress(1)
        return out
    }

    private func loadImage(from source: CGImageSource, maxDimension: Int?) throws -> CGImage {
        if let maxDim = maxDimension {
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDim,
            ]
            if let t = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) { return t }
        }
        guard let img = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ConversionError.readFailed }
        return img
    }

    private func writePDF(_ image: CGImage, to url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw ConversionError.writeFailed
        }
        ctx.beginPDFPage(nil); ctx.draw(image, in: box); ctx.endPDFPage(); ctx.closePDF()
    }
}
