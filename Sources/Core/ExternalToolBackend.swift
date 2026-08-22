#if os(macOS)
import Foundation

/// Auto-detecting bridge to command-line power tools. Whatever is installed on
/// the machine (or bundled in a notarized build) lights up automatically and
/// widens coverage to essentially "anything → anything": ffmpeg for the full A/V
/// matrix (incl. MP3 encode), rsvg for SVG, pandoc for documents/markdown,
/// ImageMagick for exotic images, LibreOffice for office formats.
///
/// macOS only — iOS can't spawn subprocesses.
struct ExternalToolBackend: ConversionBackend {
    let id = "external"

    static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]

    static func locate(_ tool: String) -> String? {
        for dir in searchPaths {
            let p = "\(dir)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    // resolved once
    private static let ffmpeg = locate("ffmpeg")
    private static let rsvg = locate("rsvg-convert")
    private static let pandoc = locate("pandoc")
    private static let magick = locate("magick") ?? locate("convert")
    private static let soffice = locate("soffice") ?? locate("libreoffice")
    private static let gzip = locate("gzip")
    private static let zip = locate("zip")
    private static let tar = locate("tar")

    var isAvailable: Bool {
        Self.ffmpeg != nil || Self.rsvg != nil || Self.pandoc != nil
            || Self.magick != nil || Self.soffice != nil || Self.zip != nil || Self.tar != nil
    }

    /// Names of the tools actually found (for the capabilities panel).
    static var detected: [String] {
        var out: [String] = []
        if ffmpeg != nil { out.append("ffmpeg") }
        if rsvg != nil { out.append("rsvg") }
        if pandoc != nil { out.append("pandoc") }
        if magick != nil { out.append("ImageMagick") }
        if soffice != nil { out.append("LibreOffice") }
        if zip != nil { out.append("zip") }
        if tar != nil { out.append("tar") }
        return out
    }

    // MARK: Edges

    private let audio = ["mp3", "m4a", "aac", "wav", "aiff", "flac", "ogg", "opus", "wma", "caf"]
    private let video = ["mp4", "mov", "mkv", "webm", "avi", "flv", "wmv", "mpg"]
    private let pandocDocs = ["md", "html", "rst", "tex", "org", "docx", "odt", "epub", "txt"]
    private let magickImages = ["png", "jpeg", "gif", "bmp", "tiff", "webp", "heic", "ico",
                                "tga", "psd", "ppm", "avif", "jxl", "svg", "eps", "pdf"]
    private let officeDocs = ["doc", "docx", "odt", "rtf", "html", "txt"]

    func edges() -> [FormatEdge] {
        var e: [FormatEdge] = []

        if Self.ffmpeg != nil {
            for a in audio { for b in audio where a != b {
                e.append(FormatEdge(from: a, to: b, backendID: id, cost: 2.0)) } }
            for v in video { for w in video where v != w {
                e.append(FormatEdge(from: v, to: w, backendID: id, cost: 2.0)) } }
            for v in video { for a in audio {
                e.append(FormatEdge(from: v, to: a, backendID: id, cost: 2.1)) } }
            for v in video { e.append(FormatEdge(from: v, to: "gifv", backendID: id, cost: 2.2)) }
        }
        if Self.rsvg != nil {
            for t in ["png", "pdf"] { e.append(FormatEdge(from: "svg", to: t, backendID: id, cost: 1.6)) }
        }
        if Self.pandoc != nil {
            for a in pandocDocs { for b in pandocDocs where a != b {
                e.append(FormatEdge(from: a, to: b, backendID: id, cost: 1.8)) } }
        }
        if Self.magick != nil {
            for a in magickImages { for b in magickImages where a != b {
                e.append(FormatEdge(from: a, to: b, backendID: id, cost: 2.4)) } }
        }
        if Self.soffice != nil {
            for a in officeDocs { e.append(FormatEdge(from: a, to: "pdf", backendID: id, cost: 1.9)) }
        }
        for f in Catalog.all where f.category != .archive {
            if Self.zip != nil { e.append(FormatEdge(from: f.id, to: "zip", backendID: id, cost: 2.5)) }
            if Self.gzip != nil { e.append(FormatEdge(from: f.id, to: "gz", backendID: id, cost: 2.5)) }
            if Self.tar != nil { e.append(FormatEdge(from: f.id, to: "tar", backendID: id, cost: 2.5)) }
        }
        return e
    }

    // MARK: Convert

    func convert(source: URL, from: Format, to: Format,
                 options: ConversionOptions,
                 progress: @Sendable @escaping (Double) -> Void) async throws -> URL {
        progress(0.03)
        let out = tempURL(for: to)

        if to.id == "gz", let gzip = Self.gzip {
            FileManager.default.createFile(atPath: out.path, contents: nil)
            try await runProcess(gzip, ["-c", source.path], stdoutTo: out)
        } else if to.id == "zip", let zip = Self.zip {
            try? FileManager.default.removeItem(at: out)
            try await runProcess(zip, ["-j", "-q", out.path, source.path])
        } else if to.id == "tar", let tar = Self.tar {
            try? FileManager.default.removeItem(at: out)
            try await runProcess(tar, ["-cf", out.path, "-C", source.deletingLastPathComponent().path, source.lastPathComponent])
        } else if from.id == "svg", let rsvg = Self.rsvg {
            var args = ["-f", to.id == "pdf" ? "pdf" : "png"]
            if let m = options.maxDimension, to.id == "png" { args += ["-w", String(m)] }
            args += ["-o", out.path, source.path]
            try await runProcess(rsvg, args)
        } else if isFFmpegEdge(from: from, to: to), let ff = Self.ffmpeg {
            // Parse ffmpeg's stderr for Duration/time to report real progress.
            let tracker = FFmpegProgress { p in progress(0.03 + 0.94 * p) }
            try await runProcess(ff, ffmpegArgs(source: source, to: to, out: out, options: options),
                                 onStderr: { tracker.feed($0) })
        } else if pandocDocs.contains(from.id), pandocDocs.contains(to.id), let pandoc = Self.pandoc {
            try await runProcess(pandoc, ["-s", source.path, "-o", out.path])
        } else if officeDocs.contains(from.id), to.id == "pdf", let soffice = Self.soffice {
            return try await libreOfficeConvert(soffice, source: source, to: to)
        } else if let magick = Self.magick {
            try await runProcess(magick, [source.path, out.path])
        } else {
            throw ConversionError.unsupportedTarget("No external tool available for \(from.name) → \(to.name).")
        }
        progress(1)
        return out
    }

    private func isFFmpegEdge(from: Format, to: Format) -> Bool {
        let av = Set(audio + video + ["gifv"])
        return av.contains(from.id) && av.contains(to.id)
    }

    private func ffmpegArgs(source: URL, to: Format, out: URL, options: ConversionOptions) -> [String] {
        var args = ["-y", "-i", source.path]
        switch to.category {
        case .audio:
            args += ["-vn"]
            if to.id == "mp3" { args += ["-q:a", "2"] }
        case .video where to.id == "gifv":
            args += ["-vf", "fps=12,scale=480:-1:flags=lanczos"]
        case .video:
            switch options.videoQuality {
            case .p720: args += ["-vf", "scale=-2:720"]
            case .p1080: args += ["-vf", "scale=-2:1080"]
            case .same: break
            }
        default: break
        }
        args.append(out.path)
        return args
    }

    private func libreOfficeConvert(_ soffice: String, source: URL, to: Format) async throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try await runProcess(soffice, ["--headless", "--convert-to", to.ext, "--outdir", dir.path, source.path])
        let produced = dir.appendingPathComponent(source.deletingPathExtension().lastPathComponent)
            .appendingPathExtension(to.ext)
        guard FileManager.default.fileExists(atPath: produced.path) else {
            throw ConversionError.exportFailed("LibreOffice produced no output.")
        }
        return produced
    }

    // MARK: Process runner (async + cancellable + live stderr)

    private func runProcess(_ executable: String, _ args: [String],
                            stdoutTo: URL? = nil,
                            onStderr: ((String) -> Void)? = nil) async throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = args
        let errPipe = Pipe()
        proc.standardError = errPipe
        if let stdoutTo, let handle = try? FileHandle(forWritingTo: stdoutTo) {
            proc.standardOutput = handle
        } else {
            proc.standardOutput = Pipe()
        }

        final class ErrAccumulator { var data = Data() }
        let acc = ErrAccumulator()

        try await withTaskCancellationHandler {
            do { try proc.run() } catch {
                throw ConversionError.exportFailed("Couldn't launch \((executable as NSString).lastPathComponent).")
            }
            // Stream stderr so we can (a) report progress and (b) capture errors.
            let handle = errPipe.fileHandleForReading
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }              // EOF (process exited / terminated)
                acc.data.append(chunk)
                if let s = String(data: chunk, encoding: .utf8) { onStderr?(s) }
            }
            proc.waitUntilExit()
            if Task.isCancelled { throw ConversionError.cancelled }
            if proc.terminationStatus != 0 {
                let tail = String(data: acc.data.suffix(600), encoding: .utf8)?
                    .split(separator: "\n").last.map(String.init)?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                throw ConversionError.exportFailed(tail.isEmpty ? "External tool failed." : tail)
            }
        } onCancel: {
            if proc.isRunning { proc.terminate() }
        }
    }
}

/// Parses ffmpeg's stderr stream ("Duration: HH:MM:SS.ss" then "time=HH:MM:SS.ss")
/// into a 0…1 progress value.
private final class FFmpegProgress {
    private var duration: Double?
    private let emit: (Double) -> Void
    private var buffer = ""
    init(_ emit: @escaping (Double) -> Void) { self.emit = emit }

    func feed(_ s: String) {
        buffer += s
        if duration == nil, let d = Self.seconds(in: buffer, after: "Duration:") { duration = d }
        if let dur = duration, dur > 0, let t = Self.lastSeconds(in: buffer, after: "time=") {
            emit(min(0.99, t / dur))
        }
        if buffer.count > 8000 { buffer = String(buffer.suffix(4000)) }
    }

    /// First "H:MM:SS.ss" appearing after `key`.
    private static func seconds(in text: String, after key: String) -> Double? {
        guard let r = text.range(of: key) else { return nil }
        return parseClock(String(text[r.upperBound...]))
    }
    /// Last occurrence (ffmpeg overwrites time= repeatedly).
    private static func lastSeconds(in text: String, after key: String) -> Double? {
        guard let r = text.range(of: key, options: .backwards) else { return nil }
        return parseClock(String(text[r.upperBound...]))
    }
    private static func parseClock(_ s: String) -> Double? {
        let trimmed = s.drop { $0 == " " }
        var h = "", m = "", sec = "", stage = 0
        for ch in trimmed {
            if ch.isNumber || ch == "." {
                switch stage { case 0: h.append(ch); case 1: m.append(ch); default: sec.append(ch) }
            } else if ch == ":" { stage += 1; if stage > 2 { break } }
            else { break }
        }
        guard let hh = Double(h), let mm = Double(m), let ss = Double(sec) else { return nil }
        return hh * 3600 + mm * 60 + ss
    }
}
#endif
