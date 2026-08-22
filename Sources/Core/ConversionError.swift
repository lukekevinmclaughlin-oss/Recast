import Foundation

enum ConversionError: LocalizedError {
    case unsupportedSource(String)
    case unsupportedTarget(String)
    case readFailed
    case writeFailed
    case exportFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unsupportedSource(let s): return "Can't read this file (\(s))."
        case .unsupportedTarget(let s): return s
        case .readFailed: return "Couldn't read the source file."
        case .writeFailed: return "Couldn't write the converted file."
        case .exportFailed(let s): return s
        case .cancelled: return "Cancelled."
        }
    }
}
