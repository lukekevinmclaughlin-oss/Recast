import Foundation
import SwiftUI

/// Where converted files are written.
enum OutputDestination: Equatable {
    case nextToOriginal
    case folder(URL)
    case appExports

    var label: String {
        switch self {
        case .nextToOriginal: return "Next to original"
        case .folder(let url): return url.lastPathComponent
        case .appExports: return "Recast Exports"
        }
    }
}

enum VideoQuality: String, CaseIterable, Identifiable {
    case same, p1080, p720
    var id: String { rawValue }
    var label: String {
        switch self {
        case .same: return "Same quality"
        case .p1080: return "1080p"
        case .p720: return "720p"
        }
    }
}

/// User-tunable options plus the per-category "last used target" memory.
@MainActor
final class ConversionSettings: ObservableObject {

    static let shared = ConversionSettings()

    private let defaults = UserDefaults.standard

    @Published var imageQuality: Double { didSet { defaults.set(imageQuality, forKey: K.imageQuality) } }
    @Published var resizeEnabled: Bool { didSet { defaults.set(resizeEnabled, forKey: K.resizeEnabled) } }
    @Published var maxDimension: Double { didSet { defaults.set(maxDimension, forKey: K.maxDimension) } }
    @Published var keepMetadata: Bool { didSet { defaults.set(keepMetadata, forKey: K.keepMetadata) } }
    @Published var videoQuality: VideoQuality { didSet { defaults.set(videoQuality.rawValue, forKey: K.videoQuality) } }
    @Published var namingSuffix: String { didSet { defaults.set(namingSuffix, forKey: K.namingSuffix) } }
    /// When true (default) a dropped file converts immediately with its category
    /// default. When false it waits in the queue for the user to pick a target and
    /// press Convert.
    @Published var autoConvertOnDrop: Bool { didSet { defaults.set(autoConvertOnDrop, forKey: K.autoConvert) } }

    @Published private var lastTargetIDs: [String: String] {
        didSet { defaults.set(lastTargetIDs, forKey: K.lastTargetIDs) }
    }

    func lastTarget(for category: FormatCategory) -> Format {
        if let id = lastTargetIDs[category.rawValue], let f = Catalog.format(id: id) { return f }
        return Catalog.defaultTarget(from: category)
    }

    func setLastTarget(_ format: Format, for category: FormatCategory) {
        lastTargetIDs[category.rawValue] = format.id
    }

    var options: ConversionOptions {
        ConversionOptions(imageQuality: imageQuality,
                          maxDimension: resizeEnabled ? Int(maxDimension) : nil,
                          keepMetadata: keepMetadata,
                          videoQuality: videoQuality)
    }

    private init() {
        imageQuality = defaults.object(forKey: K.imageQuality) as? Double ?? 0.85
        resizeEnabled = defaults.bool(forKey: K.resizeEnabled)
        maxDimension = defaults.object(forKey: K.maxDimension) as? Double ?? 2048
        keepMetadata = defaults.object(forKey: K.keepMetadata) as? Bool ?? true
        videoQuality = VideoQuality(rawValue: defaults.string(forKey: K.videoQuality) ?? "") ?? .same
        namingSuffix = defaults.string(forKey: K.namingSuffix) ?? ""
        autoConvertOnDrop = defaults.object(forKey: K.autoConvert) as? Bool ?? true
        lastTargetIDs = defaults.dictionary(forKey: K.lastTargetIDs) as? [String: String] ?? [:]
    }

    private enum K {
        static let imageQuality = "imageQuality"
        static let resizeEnabled = "resizeEnabled"
        static let maxDimension = "maxDimension"
        static let keepMetadata = "keepMetadata"
        static let videoQuality = "videoQuality"
        static let namingSuffix = "namingSuffix"
        static let autoConvert = "autoConvertOnDrop"
        static let lastTargetIDs = "lastTargetIDs"
    }
}
