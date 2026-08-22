#if os(iOS)
import SwiftUI
import StoreKit
import UniformTypeIdentifiers

/// iOS / iPadOS main window. No menu bar, so this is the primary surface:
/// import via drop (iPad) or the file picker, convert, then share / save results.
struct MainContentView: View {
    @EnvironmentObject private var coordinator: ConversionCoordinator
    @EnvironmentObject private var settings: ConversionSettings
    @EnvironmentObject private var pro: ProManager
    @EnvironmentObject private var engagement: EngagementManager
    @Environment(\.requestReview) private var requestReview
    @State private var showPicker = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            HoloBackground()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    CapabilitiesBar()
                    DropZoneView(big: true)
                    DropNoticeBanner()

                    Button { showPicker = true } label: {
                        Label("Choose Files", systemImage: "folder.fill.badge.plus")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .tint(Theme.accent).glassButton(prominent: true).controlSize(.large)

                    QueueListView(maxHeight: 400)

                    HStack(spacing: 5) {
                        Image(systemName: "lock.shield.fill").font(.caption2)
                        Text("100% on-device. Files never leave this device.").font(.caption2)
                    }
                    .foregroundStyle(.white.opacity(0.45)).padding(.top, 4)
                }
                .padding()
            }
        }
        .preferredColorScheme(.dark)
        .fileImporter(isPresented: $showPicker,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { coordinator.add(urls: urls, securityScoped: true) }
        }
        .sheet(isPresented: $showSettings) { SettingsView().preferredColorScheme(.dark) }
        .sheet(isPresented: $engagement.showWelcome) { PremiumIntroView().preferredColorScheme(.dark) }
        .sheet(isPresented: $coordinator.showProGate) { ProGateView().preferredColorScheme(.dark) }
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
        .overlay(alignment: .topTrailing) {
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3").font(.title3).foregroundStyle(.white)
            }
            .padding()
        }
        #if DEBUG
        .task { coordinator.seedDemoIfRequested() }
        #endif
    }

    private var header: some View {
        HStack(spacing: 10) {
            BrandMark(size: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text("Recast").font(.title2.weight(.bold)).foregroundStyle(.white)
                Text("Any file → any format").font(.caption2).foregroundStyle(Theme.accent)
            }
            if pro.isPro {
                Text("PRO").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.accent)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.accent.opacity(0.15)))
            } else {
                Button("Try Premium") { coordinator.showProGate = true }
                    .buttonStyle(.bordered).controlSize(.small).tint(Theme.accent)
            }
            Spacer()
        }
    }
}
#endif
