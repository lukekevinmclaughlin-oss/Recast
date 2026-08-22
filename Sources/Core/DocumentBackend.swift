#if os(macOS)
import Foundation
import AppKit
import CoreText
import CoreGraphics

/// Rich-document conversion via AppKit's NSAttributedString document readers /
/// writers (Word .doc/.docx, ODT, RTF/RTFD, HTML, plain text) plus CoreText
/// pagination to PDF. macOS only — AppKit's office readers aren't on iOS.
struct DocumentBackend: ConversionBackend {
    let id = "appkit-doc"
    var isAvailable: Bool { true }

    private static let typeMap: [String: NSAttributedString.DocumentType] = [
        "txt": .plain, "rtf": .rtf, "rtfd": .rtfd, "html": .html,
        "doc": .docFormat, "docx": .officeOpenXML, "odt": .openDocument,
    ]
    private let readable = ["txt", "rtf", "rtfd", "html", "doc", "docx", "odt"]
    private let writable = ["txt", "rtf", "html", "doc", "docx", "odt"]

    func edges() -> [FormatEdge] {
        var e: [FormatEdge] = []
        for r in readable {
            for w in writable where r != w {
                e.append(FormatEdge(from: r, to: w, backendID: id, cost: 1.2))
            }
            e.append(FormatEdge(from: r, to: "pdf", backendID: id, cost: 1.4))
        }
        return e
    }

    func convert(source: URL, from: Format, to: Format,
                 options: ConversionOptions,
                 progress: @Sendable @escaping (Double) -> Void) async throws -> URL {
        guard let readType = Self.typeMap[from.id] else {
            throw ConversionError.unsupportedSource(from.name)
        }
        let opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: readType]
        guard let attr = try? NSAttributedString(url: source, options: opts, documentAttributes: nil) else {
            throw ConversionError.readFailed
        }
        let out = tempURL(for: to)

        if to.id == "pdf" {
            try renderPDF(attr, to: out)
            progress(1); return out
        }
        guard let writeType = Self.typeMap[to.id] else {
            throw ConversionError.unsupportedTarget("Can't write \(to.name).")
        }
        let data = try attr.data(from: NSRange(location: 0, length: attr.length),
                                  documentAttributes: [.documentType: writeType])
        try data.write(to: out)
        progress(1)
        return out
    }

    /// Paginate the attributed string into US-Letter PDF pages with CoreText.
    private func renderPDF(_ attr: NSAttributedString, to url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 48
        let textRect = mediaBox.insetBy(dx: margin, dy: margin)

        guard let consumer = CGDataConsumer(url: url as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ConversionError.writeFailed
        }
        let framesetter = CTFramesetterCreateWithAttributedString(attr as CFAttributedString)
        let total = attr.length
        var start = 0
        while start < total {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(mediaBox)
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: start, length: 0), path, nil)
            CTFrameDraw(frame, ctx)
            let visible = CTFrameGetVisibleStringRange(frame)
            ctx.endPDFPage()
            if visible.length <= 0 { break }
            start += visible.length
        }
        ctx.closePDF()
    }
}
#endif
