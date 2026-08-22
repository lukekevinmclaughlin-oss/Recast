import Foundation

/// Options that flow into a conversion.
struct ConversionOptions: Sendable {
    var imageQuality: Double = 0.85
    var maxDimension: Int? = nil
    var keepMetadata: Bool = true
    var videoQuality: VideoQuality = .same
}

/// A directed capability: this backend can turn `from` into `to`.
struct FormatEdge: Hashable {
    let from: String          // Format.id
    let to: String            // Format.id
    let backendID: String
    let cost: Double          // lower = preferred (native beats external; lossless beats lossy)
}

/// A pluggable conversion engine (native framework or external tool).
protocol ConversionBackend {
    var id: String { get }
    /// Whether this backend can run in the current environment (tool installed, OS supports it…).
    var isAvailable: Bool { get }
    /// The (from → to) conversions this backend provides right now.
    func edges() -> [FormatEdge]
    /// Perform a single-hop conversion, returning a freshly written temp file.
    func convert(source: URL, from: Format, to: Format,
                 options: ConversionOptions,
                 progress: @Sendable @escaping (Double) -> Void) async throws -> URL
}

extension ConversionBackend {
    /// Helper to build a fresh temp URL with the target extension.
    func tempURL(for format: Format) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(format.ext.contains(".") ? String(format.ext.split(separator: ".").last!) : format.ext)
    }
}
