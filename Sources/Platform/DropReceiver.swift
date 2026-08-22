import SwiftUI
import UniformTypeIdentifiers

/// A reusable drop target that accepts file URLs (including folders) and forwards
/// them to the coordinator. Works on macOS and iPadOS.
struct DropReceiver: ViewModifier {
    @Binding var isTargeted: Bool
    let onDrop: ([URL]) -> Void

    func body(content: Content) -> some View {
        content.onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            load(providers)
            return true
        }
    }

    private func load(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                var resolved: URL?
                if let data = item as? Data { resolved = URL(dataRepresentation: data, relativeTo: nil) }
                else if let url = item as? URL { resolved = url }
                if let url = resolved { lock.lock(); urls.append(url); lock.unlock() }
            }
        }
        group.notify(queue: .main) { if !urls.isEmpty { onDrop(urls) } }
    }
}

extension View {
    func dropReceiver(isTargeted: Binding<Bool>, onDrop: @escaping ([URL]) -> Void) -> some View {
        modifier(DropReceiver(isTargeted: isTargeted, onDrop: onDrop))
    }
}
