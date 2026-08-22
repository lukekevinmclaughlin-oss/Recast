#if os(macOS)
import AppKit
import SwiftUI

/// Hosts the always-available floating drop window (an NSPanel that stays above
/// other apps) so users can drop files without first opening the menu-bar popover.
final class AppDelegate: NSObject, NSApplicationDelegate {

    static private(set) var shared: AppDelegate?
    private var floatingPanel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
    }

    func toggleFloatingWindow() {
        if let panel = floatingPanel {
            if panel.isVisible { panel.orderOut(nil) } else { showPanel(panel) }
            return
        }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .hudWindow],
            backing: .buffered, defer: false)
        panel.title = "Recast"
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false

        let root = FloatingDropView()
            .environmentObject(ConversionCoordinator.shared)
            .environmentObject(ProManager.shared)
        panel.contentView = NSHostingView(rootView: root)
        floatingPanel = panel
        showPanel(panel)
    }

    private func showPanel(_ panel: NSPanel) {
        panel.center()
        panel.orderFrontRegardless()
    }
}
#endif
