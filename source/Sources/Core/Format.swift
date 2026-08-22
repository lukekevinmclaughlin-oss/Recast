import Foundation
import UniformTypeIdentifiers

/// Broad category a format belongs to. Drives grouping, icons and default targets.
enum FormatCategory: String, CaseIterable, Identifiable, Codable {
    case image, audio, video, document, data, vector, archive, ebook

    var id: String { rawValue }

    var title: String {
        switch self {
        case .image: return "Images"
        case .audio: return "Audio"
        case .video: return "Video"
        case .document: return "Documents"
        case .data: return "Data"
        case .vector: return "Vector"
        case .archive: return "Archives"
        case .ebook: return "eBooks"
        }
    }

    var symbol: String {
        switch self {
        case .image: return "photo"
        case .audio: return "waveform"
        case .video: return "film"
        case .document: return "doc.richtext"
        case .data: return "curlybraces"
        case .vector: return "scribble.variable"
        case .archive: return "archivebox"
        case .ebook: return "book"
        }
    }
}

/// A single file format Recast knows about.
struct Format: Identifiable, Hashable, Codable {
    let id: String                 // stable key, e.g. "jpeg"
    let name: String               // display, e.g. "JPEG"
    let ext: String                // primary extension, e.g. "jpg"
    let aliases: [String]          // other extensions, e.g. ["jpeg"]
    let category: FormatCategory
    let uti: String?               // for ImageIO / UTType interop

    var allExtensions: [String] { [ext] + aliases }

    static func == (l: Format, r: Format) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum Catalog {
    static let all: [Format] = build()

    private static func f(_ id: String, _ name: String, _ ext: String,
                          _ cat: FormatCategory, uti: String? = nil,
                          alias: [String] = []) -> Format {
        Format(id: id, name: name, ext: ext, aliases: alias, category: cat, uti: uti)
    }

    private static func build() -> [Format] {
        [
            // Images
            f("jpeg", "JPEG", "jpg", .image, uti: "public.jpeg", alias: ["jpeg", "jpe"]),
            f("png", "PNG", "png", .image, uti: "public.png"),
            f("heic", "HEIC", "heic", .image, uti: "public.heic", alias: ["heif"]),
            f("tiff", "TIFF", "tiff", .image, uti: "public.tiff", alias: ["tif"]),
            f("gif", "GIF", "gif", .image, uti: "com.compuserve.gif"),
            f("bmp", "BMP", "bmp", .image, uti: "com.microsoft.bmp"),
            f("webp", "WebP", "webp", .image, uti: "org.webmproject.webp"),
            f("ico", "ICO", "ico", .image, uti: "com.microsoft.ico"),
            f("icns", "Apple Icon", "icns", .image, uti: "com.apple.icns"),
            f("avif", "AVIF", "avif", .image, uti: "public.avif"),
            f("jxl", "JPEG XL", "jxl", .image),
            f("psd", "Photoshop", "psd", .image, uti: "com.adobe.photoshop-image"),
            f("tga", "Targa", "tga", .image),
            f("ppm", "PPM", "ppm", .image),

            // Vector
            f("svg", "SVG", "svg", .vector, uti: "public.svg-image"),
            f("eps", "EPS", "eps", .vector),

            // Audio
            f("mp3", "MP3", "mp3", .audio, uti: "public.mp3"),
            f("m4a", "M4A (AAC)", "m4a", .audio, uti: "public.mpeg-4-audio"),
            f("aac", "AAC", "aac", .audio),
            f("wav", "WAV", "wav", .audio, uti: "com.microsoft.waveform-audio"),
            f("aiff", "AIFF", "aiff", .audio, uti: "public.aiff-audio", alias: ["aif"]),
            f("caf", "CAF", "caf", .audio),
            f("flac", "FLAC", "flac", .audio),
            f("ogg", "OGG", "ogg", .audio, alias: ["oga"]),
            f("opus", "Opus", "opus", .audio),
            f("wma", "WMA", "wma", .audio),

            // Video
            f("mp4", "MP4", "mp4", .video, uti: "public.mpeg-4", alias: ["m4v"]),
            f("mov", "MOV", "mov", .video, uti: "com.apple.quicktime-movie"),
            f("mkv", "MKV", "mkv", .video),
            f("webm", "WebM", "webm", .video),
            f("avi", "AVI", "avi", .video),
            f("flv", "FLV", "flv", .video),
            f("wmv", "WMV", "wmv", .video),
            f("mpg", "MPEG", "mpg", .video, alias: ["mpeg"]),
            f("gifv", "Animated GIF", "gif", .video),   // video→gif (distinct from still gif)

            // Documents
            f("pdf", "PDF", "pdf", .document, uti: "com.adobe.pdf"),
            f("docx", "Word (docx)", "docx", .document, uti: "org.openxmlformats.wordprocessingml.document"),
            f("doc", "Word (doc)", "doc", .document, uti: "com.microsoft.word.doc"),
            f("odt", "OpenDocument", "odt", .document, uti: "org.oasis-open.opendocument.text"),
            f("rtf", "RTF", "rtf", .document, uti: "public.rtf"),
            f("rtfd", "RTFD", "rtfd", .document, uti: "com.apple.rtfd"),
            f("html", "HTML", "html", .document, uti: "public.html", alias: ["htm"]),
            f("txt", "Plain Text", "txt", .document, uti: "public.plain-text", alias: ["text"]),
            f("md", "Markdown", "md", .document, uti: "net.daringfireball.markdown", alias: ["markdown"]),
            f("rst", "reStructuredText", "rst", .document),
            f("tex", "LaTeX", "tex", .document, alias: ["latex"]),
            f("org", "Org", "org", .document),

            // eBooks
            f("epub", "EPUB", "epub", .ebook, uti: "org.idpf.epub-container"),

            // Data
            f("json", "JSON", "json", .data, uti: "public.json"),
            f("yaml", "YAML", "yaml", .data, alias: ["yml"]),
            f("xml", "XML", "xml", .data, uti: "public.xml"),
            f("plist", "Property List", "plist", .data, uti: "com.apple.property-list"),
            f("csv", "CSV", "csv", .data, uti: "public.comma-separated-values-text"),
            f("tsv", "TSV", "tsv", .data, uti: "public.tab-separated-values-text"),
            f("toml", "TOML", "toml", .data),

            // Archives
            f("zip", "ZIP", "zip", .archive, uti: "public.zip-archive"),
            f("tar", "TAR", "tar", .archive),
            f("targz", "TAR.GZ", "tar.gz", .archive, alias: ["tgz"]),
            f("gz", "Gzip", "gz", .archive, uti: "org.gnu.gnu-zip-archive"),
        ]
    }

    private static let byID: [String: Format] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func format(id: String) -> Format? { byID[id] }

    static func formats(in category: FormatCategory) -> [Format] {
        all.filter { $0.category == category }
    }

    /// Classify a file by extension (then by UTType as a fallback).
    static func format(for url: URL) -> Format? {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") { return byID["targz"] }
        if let m = all.first(where: { $0.allExtensions.contains(ext) }) { return m }
        if let type = UTType(filenameExtension: ext),
           let m = all.first(where: { $0.uti == type.identifier }) { return m }
        return nil
    }

    /// Default target when converting *from* a given category.
    static func defaultTarget(from category: FormatCategory) -> Format {
        let id: String
        switch category {
        case .image: id = "jpeg"
        case .audio: id = "mp3"
        case .video: id = "mp4"
        case .document: id = "pdf"
        case .data: id = "json"
        case .vector: id = "png"
        case .archive: id = "zip"
        case .ebook: id = "pdf"
        }
        return byID[id] ?? all[0]
    }
}
