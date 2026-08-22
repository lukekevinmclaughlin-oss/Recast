import Foundation
#if os(macOS)
import AppKit
#endif

/// Small cross-platform helpers for acting on a converted file.
enum FileActions {
    static func reveal(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    }
    static func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }
}
