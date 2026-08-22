import SwiftUI

/// Upsell shown when a free user drops a batch or a folder.
struct ProGateView: View {
    @EnvironmentObject private var pro: ProManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            HoloBackground()
            VStack(spacing: 16) {
                BrandMark(size: 54).padding(.top, 6)

                VStack(spacing: 4) {
                    Text("Start Your Free Trial")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text("Use every Recast feature free for one week")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }

                VStack(alignment: .leading, spacing: 11) {
                    feature("square.stack.3d.up.fill", "Unlimited batch & whole-folder conversion")
                    feature("lock.shield.fill", "Private, 100% on-device processing")
                    feature("arrow.triangle.branch", "Intelligent multi-step conversion routing")
                    feature("arrow.triangle.2.circlepath", "Ongoing format and workflow updates")
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.04))
                .liquidGlass(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.2), lineWidth: 1))

                Button {
                    Task { await pro.purchaseYearly() }
                } label: {
                    VStack(spacing: 2) {
                        Text("Start Free Trial")
                        Text("then \(pro.yearlyPrice)/year")
                            .font(.caption)
                    }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .tint(Theme.accent)
                .glassButton(prominent: true)
                .controlSize(.large)

                Button("Monthly — \(pro.monthlyPrice)/month after trial") {
                    Task { await pro.purchaseMonthly() }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(Theme.accent)

                Text("One week free, then auto-renews at the selected price until cancelled.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)

                Button("Restore Purchase") { Task { await pro.restore() } }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))

                HStack(spacing: 14) {
                    Link("Privacy Policy", destination: URL(string: "https://github.com/lukekevinmclaughlin-oss/Recast/blob/main/PRIVACY.md")!)
                    Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))

                if let error = pro.lastError {
                    Text(error).font(.caption).foregroundStyle(Theme.amber)
                }

                Button("Not now") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(24)
        }
        .frame(width: 340)
        .preferredColorScheme(.dark)
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            Text(text)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}
