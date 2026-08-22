#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

/// Contents of the menu-bar popover window — the quick-drop surface.
struct MenuBarContentView: View {
    @EnvironmentObject private var coordinator: ConversionCoordinator
    @EnvironmentObject private var settings: ConversionSettings
    @EnvironmentObject private var pro: ProManager
    @EnvironmentObject private var engagement: EngagementManager
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack {
            HoloBackground()
            VStack(alignment: .leading, spacing: 12) {
                header
                CapabilitiesBar(compact: true)
                DropZoneView(compact: !coordinator.jobs.isEmpty)
                DropNoticeBanner()
                OutputDestinationRow()
                QueueListView()
                footer
            }
            .padding(16)
        }
        .frame(width: 380)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $coordinator.showProGate) {
            ProGateView()
        }
        #if DEBUG
        .task { coordinator.seedDemoIfRequested() }
        #endif
    }

    private var header: some View {
        HStack(spacing: 9) {
            BrandMark(size: 28)
            BrandTitle()
            if pro.isPro { proBadge }
            Spacer()
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "macwindow")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(.plain)
            .background(Color.white.opacity(0.05))
            .liquidGlass(Capsule(), interactive: true)
            .clipShape(Capsule())
            .help("Open the full Recast window")

            Menu {
                Button("Open Files…") { openPanel() }
                Button("Floating Drop Window") { AppDelegate.shared?.toggleFloatingWindow() }
                Divider()
                Button("Settings…") { openSettings() }
                if !pro.isPro { Button("Unlock Pro…") { coordinator.showProGate = true } }
                #if DEBUG
                Divider()
                Button(pro.isPro ? "Debug: Lock Pro" : "Debug: Unlock Pro") { pro.toggleDebugPro() }
                #endif
                Divider()
                Button("Quit Recast") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 28, height: 24)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .background(Color.white.opacity(0.05))
            .liquidGlass(Capsule(), interactive: true)
            .clipShape(Capsule())
            .fixedSize()
        }
    }

    private var proBadge: some View {
        Text("PRO")
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Theme.accent.opacity(0.15)))
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.5), lineWidth: 0.8))
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.shield.fill").font(.caption2).foregroundStyle(Theme.accent.opacity(0.8))
            Text("100% on-device. Files never leave your Mac.")
                .font(.caption2).foregroundStyle(.white.opacity(0.45))
            Spacer()
        }
    }

    private func openPanel() { coordinator.presentOpenPanel() }
}

/// Row for choosing where converted files land (macOS).
struct OutputDestinationRow: View {
    @EnvironmentObject private var coordinator: ConversionCoordinator

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "folder.fill").font(.caption2).foregroundStyle(Theme.accent.opacity(0.7))
            Text("Save to").font(.caption).foregroundStyle(.white.opacity(0.5))
            Menu {
                Button("Next to original") { coordinator.outputDestination = .nextToOriginal }
                Button("Choose folder…") { chooseFolder() }
            } label: {
                HStack(spacing: 4) {
                    Text(coordinator.outputDestination.label)
                        .font(.caption.weight(.medium)).foregroundStyle(.white)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 7, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                }
                .padding(.horizontal, 9).padding(.vertical, 4).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .background(Color.white.opacity(0.05))
            .liquidGlass(Capsule(), interactive: true)
            .clipShape(Capsule())
            .fixedSize()
            Spacer()
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { coordinator.outputDestination = .folder(url) }
    }
}
#endif
