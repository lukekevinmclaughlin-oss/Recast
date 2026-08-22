#if os(macOS)
import SwiftUI
import StoreKit
#if os(macOS)
import AppKit
#endif

/// The full-size Recast window — a roomier surface than the menu-bar popover,
/// with the drop target and controls on the left and the live queue on the right.
struct MainWindowView: View {
    @EnvironmentObject private var coordinator: ConversionCoordinator
    @EnvironmentObject private var settings: ConversionSettings
    @EnvironmentObject private var pro: ProManager
    @EnvironmentObject private var engagement: EngagementManager
    @Environment(\.openSettings) private var openSettings
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        ZStack {
            HoloBackground()
            HStack(spacing: 0) {
                leftPane
                    .frame(width: 360)
                    .padding(22)
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
                rightPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(22)
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $engagement.showWelcome) { PremiumIntroView() }
        .sheet(isPresented: $coordinator.showProGate) { ProGateView() }
        .onChange(of: engagement.showPremiumReminder) { _, shouldShow in
            guard shouldShow else { return }
            engagement.showPremiumReminder = false
            coordinator.showProGate = true
        }
        .onChange(of: engagement.shouldRequestReview) { _, shouldRequest in
            guard shouldRequest else { return }
            engagement.shouldRequestReview = false
            requestReview()
        }
        #if DEBUG
        .task { coordinator.seedDemoIfRequested() }
        #endif
    }

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 11) {
                BrandMark(size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Recast").font(.title.weight(.bold)).foregroundStyle(.white)
                        .shadow(color: Theme.accent.opacity(0.4), radius: 8)
                    Text("Any file → any format").font(.caption).foregroundStyle(Theme.accent)
                }
                Spacer()
                if pro.isPro {
                    Text("PRO").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.accent)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.accent.opacity(0.15)))
                } else {
                    Button("Try Premium") { coordinator.showProGate = true }
                        .buttonStyle(.bordered).controlSize(.small).tint(Theme.accent)
                }
            }

            CapabilitiesBar()
            DropZoneView(big: true)
            DropNoticeBanner()
            OutputDestinationRow()

            HStack(spacing: 10) {
                Button { openPanel() } label: {
                    Label("Choose Files", systemImage: "folder.fill").frame(maxWidth: .infinity)
                }
                .tint(Theme.accent).glassButton(prominent: true).controlSize(.large)

                Button { openSettings() } label: {
                    Image(systemName: "slider.horizontal.3").frame(width: 24)
                }
                .glassButton().controlSize(.large)
            }

            Spacer()

            HStack(spacing: 5) {
                Image(systemName: "lock.shield.fill").font(.caption2).foregroundStyle(Theme.accent.opacity(0.8))
                Text("100% on-device. Files never leave your Mac.")
                    .font(.caption2).foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    @ViewBuilder private var rightPane: some View {
        if coordinator.jobs.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 0) {
                QueueListView(maxHeight: .infinity)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "square.grid.3x3.topleft.filled")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(Theme.accent.opacity(0.7))
            Text("Drop anything to begin")
                .font(.title3.weight(.semibold)).foregroundStyle(.white)
            Text("Recast routes it through the best available engine — chaining steps when needed to reach your target format.")
                .font(.callout).foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center).frame(maxWidth: 380)

            let cols = [GridItem(.adaptive(minimum: 96), spacing: 10)]
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(FormatCategory.allCases) { cat in
                    let c = Theme.color(for: cat)
                    VStack(spacing: 6) {
                        Image(systemName: cat.symbol).font(.system(size: 18)).foregroundStyle(c)
                        Text(cat.title).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(c.opacity(0.06))
                    .liquidGlass(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(c.opacity(0.22), lineWidth: 1))
                }
            }
            .frame(maxWidth: 440)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }
        coordinator.add(urls: panel.urls, securityScoped: true)
    }
}
#endif
