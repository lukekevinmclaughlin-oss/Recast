#if os(macOS)
import AppKit

extension ConversionCoordinator {
    /// Shared "Open Files…" panel used by the ⌘O command and the buttons.
    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Convert"
        if panel.runModal() == .OK {
            add(urls: panel.urls, securityScoped: true)
        }
    }
}
#endif
