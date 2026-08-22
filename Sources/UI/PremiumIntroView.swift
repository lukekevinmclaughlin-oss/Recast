#if DIRECT_DISTRIBUTION
import SwiftUI

struct PremiumIntroView: View {
    @EnvironmentObject private var engagement: EngagementManager
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 18) {
            BrandMark(size: 56)
            Text("The complete Recast experience").font(.title2.bold())
            Text("Your Direct edition includes batches, whole folders and automatic workflows with no subscription.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Start converting") {
                engagement.completeWelcome()
                dismiss()
            }.buttonStyle(.borderedProminent)
        }
        .padding(30).frame(minWidth: 360, minHeight: 320)
    }
}
#else
import SwiftUI

struct PremiumIntroView: View {
    @EnvironmentObject private var pro: ProManager
    @EnvironmentObject private var engagement: EngagementManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            HoloBackground()
            VStack(spacing: 18) {
                BrandMark(size: 56)
                Text("Convert free. Go faster with Premium.")
                    .font(.title2.bold()).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Single-file conversion is always available. Premium adds batches, whole folders, and automatic workflows across iPhone, iPad, and Mac.")
                    .font(.callout).foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)

                Button("Try Premium") {
                    finish()
                    DispatchQueue.main.async { ConversionCoordinator.shared.showProGate = true }
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.accent)

                Button("Continue Free") { finish() }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.82))

                HStack(spacing: 14) {
                    Button("Restore Purchases") { Task { await pro.restore() } }
                    Link("Manage Subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                }
                .font(.caption).buttonStyle(.plain).foregroundStyle(Theme.accent)
            }
            .padding(28)
        }
        .frame(minWidth: 340, idealWidth: 420, minHeight: 430)
        .preferredColorScheme(.dark)
    }

    private func finish() {
        engagement.completeWelcome()
        dismiss()
    }
}
#endif
