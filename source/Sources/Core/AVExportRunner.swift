import Foundation
import AVFoundation

/// Wraps AVAssetExportSession's callback API in async/await and polls progress.
/// Uses the classic `exportAsynchronously` path so it works on our minimum
/// deployment targets (macOS 14 / iOS 17).
enum AVExportRunner {

    static func run(_ session: AVAssetExportSession,
                    to url: URL,
                    fileType: AVFileType,
                    progress: @Sendable @escaping (Double) -> Void) async throws {

        try? FileManager.default.removeItem(at: url)
        session.outputURL = url
        session.outputFileType = fileType
        session.shouldOptimizeForNetworkUse = true

        let poller = Task {
            while !Task.isCancelled {
                progress(Double(session.progress))
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
        defer { poller.cancel() }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                session.exportAsynchronously {
                    switch session.status {
                    case .completed:
                        progress(1.0); cont.resume()
                    case .cancelled:
                        cont.resume(throwing: ConversionError.cancelled)
                    case .failed:
                        cont.resume(throwing: ConversionError.exportFailed(
                            session.error?.localizedDescription ?? "Export failed."))
                    default:
                        cont.resume(throwing: ConversionError.exportFailed("Export ended unexpectedly."))
                    }
                }
            }
        } onCancel: {
            session.cancelExport()
        }
    }
}
