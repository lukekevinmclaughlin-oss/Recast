import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: ConversionSettings
    @EnvironmentObject private var pro: ProManager

    var body: some View {
        Form {
            Section("General") {
                Toggle("Convert automatically on drop", isOn: $settings.autoConvertOnDrop)
                Text(settings.autoConvertOnDrop
                     ? "Dropped files convert immediately using the last-used format for their type."
                     : "Dropped files wait in the queue so you can pick a target, then press Convert.")
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

            Section("Recast Pro") {
                if pro.isPro {
                    Label("Recast Pro subscription active", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("Batch conversion, folder drops, presets and automation.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Start 1-Week Trial — then \(pro.yearlyPrice)/year") { Task { await pro.purchaseYearly() } }
                    Button("Monthly — \(pro.monthlyPrice)/month") { Task { await pro.purchaseMonthly() } }
                    Button("Restore Purchase") { Task { await pro.restore() } }
                }
                Link("Manage Subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                Link("Privacy Policy", destination: URL(string: "https://github.com/lukekevinmclaughlin-oss/Recast/blob/main/PRIVACY.md")!)
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
}
