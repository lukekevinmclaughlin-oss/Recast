import Foundation

/// One file's trip through the queue. Reference type so SwiftUI rows can observe
/// progress updates in place without rebuilding the whole list.
final class ConversionJob: ObservableObject, Identifiable {
    let id = UUID()
    let sourceURL: URL
    let sourceFormat: Format
    let securityScoped: Bool
    let inputSize: Int

    @Published var target: Format
    @Published var status: Status = .queued
    @Published var progress: Double = 0
    @Published var outputURL: URL?
    @Published var outputSize: Int?

    init(sourceURL: URL, sourceFormat: Format, target: Format, securityScoped: Bool) {
        self.sourceURL = sourceURL
        self.sourceFormat = sourceFormat
        self.target = target
        self.securityScoped = securityScoped
        self.inputSize = (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    /// `.ready` = configured but waiting for the user to press Convert (manual mode).
    /// `.queued` = will be picked up by the processing loop automatically.
    enum Status: Equatable {
        case ready, queued, running, done
        case failed(String)
        case cancelled
    }

    var fileName: String { sourceURL.lastPathComponent }
    var category: FormatCategory { sourceFormat.category }

    var isFinished: Bool {
        switch status {
        case .done, .failed, .cancelled: return true
        case .ready, .queued, .running: return false
        }
    }

    /// e.g. "1.2 MB → 340 KB · −72%". Nil until finished with a known output size.
    var sizeSummary: String? {
        guard status == .done, let out = outputSize, inputSize > 0 else { return nil }
        let f = ByteCountFormatter()
        f.countStyle = .file
        let inStr = f.string(fromByteCount: Int64(inputSize))
        let outStr = f.string(fromByteCount: Int64(out))
        let delta = Double(out - inputSize) / Double(inputSize) * 100
        let sign = delta <= 0 ? "−" : "+"
        return "\(inStr) → \(outStr) · \(sign)\(abs(Int(delta.rounded())))%"
    }
}
