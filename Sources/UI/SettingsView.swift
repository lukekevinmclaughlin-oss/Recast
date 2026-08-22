import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: ConversionSettings
    @EnvironmentObject private var pro: ProManager
    @EnvironmentObject private var coordinator: ConversionCoordinator

    var body: some View {
        Form {
            Section("General") {
                Toggle("Convert automatically on drop", isOn: $settings.autoConvertOnDrop)
                    .disabled(!pro.isPro)
                Text(settings.autoConvertOnDrop && pro.isPro
                     ? "Dropped files convert immediately using the last-used format for their type."
                     : "Dropped files wait in the queue so you can pick a target, then press Convert. Automatic conversion is included with Premium.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Images") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Quality")
                        Spacer()
                        Text("\(Int(settings.imageQuality * 100))%")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    Slider(value: $settings.imageQuality, in: 0.1...1.0)
                }
                Toggle("Resize to a maximum size", isOn: $settings.resizeEnabled)
                if settings.resizeEnabled {
                    HStack {
                        Text("Longest edge")
                        Spacer()
                        Text("\(Int(settings.maxDimension)) px")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    Slider(value: $settings.maxDimension, in: 320...8192, step: 64)
                }
                Toggle("Keep EXIF & metadata", isOn: $settings.keepMetadata)
            }

            Section("Video") {
                Picker("Quality", selection: $settings.videoQuality) {
                    ForEach(VideoQuality.allCases) { q in Text(q.label).tag(q) }
                }
            }

            Section("Output") {
                TextField("Filename suffix", text: $settings.namingSuffix, prompt: Text("e.g. -converted"))
                Text("Added before the extension. Leave blank to keep the original name.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            #if DIRECT_DISTRIBUTION
            Section("License") {
                Label("Direct edition — fully unlocked", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("One-time website purchase. No subscription, StoreKit purchase, account, or restore step.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            #else
            Section("Recast Premium") {
                subscriptionStatus
                if pro.isPro {
                    Link("Manage Subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                } else {
                    Button("Try Premium") { coordinator.showProGate = true }
                }
                Button(pro.isRestoring ? "Restoring…" : "Restore Purchases") {
                    Task { await pro.restore() }
                }
                .disabled(pro.isRestoring)
                if let message = pro.statusMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                if let error = pro.lastError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
                Text("Free includes unlimited single-file conversions. Premium adds batches, folders, and automatic workflows.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            #endif

            Section("About") {
                Link("Privacy Policy", destination: URL(string: "https://macossoftware.com/legal/privacy/")!)
                Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            }

            Section {
                HStack {
                    Image(systemName: "lock.shield").foregroundStyle(.secondary)
                    Text("Conversions run on-device using Apple frameworks (plus any power tools you have installed). Nothing is uploaded.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .tint(Theme.accent)
        .navigationTitle("Settings")
        .frame(minWidth: 380, minHeight: 460)
    }

    #if !DIRECT_DISTRIBUTION
    @ViewBuilder private var subscriptionStatus: some View {
        switch pro.accessState {
        case .loading:
            Label("Checking subscription…", systemImage: "clock")
        case .free:
            Label("Free plan", systemImage: "checkmark.circle")
        case .active(_, let expiration, let autoRenew):
            VStack(alignment: .leading, spacing: 3) {
                Label("Premium active", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                if let expiration {
                    Text(autoRenew ? "Renews \(expiration.formatted(date: .abbreviated, time: .omitted))"
                                   : "Cancelled — access continues until \(expiration.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        case .gracePeriod(_, let expiration):
            VStack(alignment: .leading, spacing: 3) {
                Label("Premium active — billing grace period", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                if let expiration { Text("Update billing before \(expiration.formatted(date: .abbreviated, time: .omitted)).").font(.caption) }
            }
        case .billingRetry:
            Label("Subscription billing needs attention", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .expired:
            Label("Subscription expired", systemImage: "clock.badge.xmark")
        case .revoked:
            Label("Subscription refunded or revoked", systemImage: "xmark.seal")
        }
    }
    #endif
}
