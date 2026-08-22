#if DIRECT_DISTRIBUTION
import SwiftUI

struct ProGateView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 18) {
            BrandMark(size: 56)
            Text("Recast Direct edition").font(.title2.bold())
            Text("Every conversion format, batch, folder and automatic workflow is already unlocked. There is no subscription and no in-app purchase.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Continue") { dismiss() }.buttonStyle(.borderedProminent)
        }
        .padding(30).frame(minWidth: 360, minHeight: 300)
    }
}
#else
import StoreKit
import SwiftUI

struct ProGateView: View {
    @EnvironmentObject private var pro: ProManager
    @EnvironmentObject private var engagement: EngagementManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProductID = ProManager.yearlyID

    private var selectedProduct: Product? {
        pro.products.first { $0.id == selectedProductID } ?? pro.yearlyProduct ?? pro.monthlyProduct
    }

    var body: some View {
        ZStack {
            HoloBackground()
            ScrollView {
                VStack(spacing: 16) {
                    BrandMark(size: 54).padding(.top, 6)

                    VStack(spacing: 4) {
                        Text("Recast Premium")
                            .font(.title2.bold()).foregroundStyle(.white)
                        Text(trialHeadline)
                            .font(.caption).foregroundStyle(Theme.accent)
                    }

                    VStack(alignment: .leading, spacing: 11) {
                        feature("square.stack.3d.up.fill", "Unlimited batch & whole-folder conversion")
                        feature("bolt.fill", "Automatic conversion workflows")
                        feature("lock.shield.fill", "Private, 100% on-device processing")
                        feature("arrow.triangle.branch", "Intelligent multi-step conversion routing")
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04))
                    .liquidGlass(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(0.2), lineWidth: 1))

                    if pro.isLoading && pro.products.isEmpty {
                        ProgressView("Loading plans…").tint(Theme.accent)
                    } else {
                        planPicker
                    }

                    Button {
                        guard let product = selectedProduct else { return }
                        Task { await pro.purchase(product) }
                    } label: {
                        HStack {
                            if pro.isPurchasing { ProgressView().controlSize(.small) }
                            Text(actionTitle).font(.headline)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .tint(Theme.accent).glassButton(prominent: true).controlSize(.large)
                    .disabled(selectedProduct == nil || pro.isPurchasing)

                    Text(renewalDisclosure)
                        .font(.caption2).foregroundStyle(.white.opacity(0.58))
                        .multilineTextAlignment(.center)

                    Button(pro.isRestoring ? "Restoring…" : "Restore Purchases") {
                        Task { await pro.restore() }
                    }
                    .buttonStyle(.borderless).font(.caption)
                    .foregroundStyle(.white.opacity(0.72)).disabled(pro.isRestoring)

                    HStack(spacing: 14) {
                        Link("Manage Subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                        Link("Privacy Policy", destination: URL(string: "https://macossoftware.com/legal/privacy/")!)
                        Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    }
                    .font(.caption2).foregroundStyle(.white.opacity(0.68))

                    if let message = pro.statusMessage {
                        Text(message).font(.caption).foregroundStyle(.green)
                            .multilineTextAlignment(.center)
                    }
                    if let error = pro.lastError {
                        Text(error).font(.caption).foregroundStyle(Theme.amber)
                            .multilineTextAlignment(.center)
                    }

                    Button("Continue Free") { close() }
                        .buttonStyle(.plain).font(.callout.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))
                    Text("Free includes unlimited single-file conversions.")
                        .font(.caption2).foregroundStyle(.white.opacity(0.45))
                }
                .padding(24)
            }
        }
        .frame(minWidth: 360, idealWidth: 420, minHeight: 620)
        .preferredColorScheme(.dark)
        .task {
            engagement.recordPaywallShown()
            if pro.products.isEmpty { await pro.refresh() }
            if pro.yearlyProduct != nil { selectedProductID = ProManager.yearlyID }
        }
        .onChange(of: pro.isPro) { _, active in if active { close() } }
    }

    private var planPicker: some View {
        VStack(spacing: 9) {
            ForEach(pro.products, id: \.id) { product in
                Button { selectedProductID = product.id } label: {
                    HStack {
                        Image(systemName: selectedProductID == product.id ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.id == ProManager.yearlyID ? "Annual" : "Monthly")
                                .font(.headline).foregroundStyle(.white)
                            if pro.isEligibleForTrial(product) {
                                Text("Includes eligible free trial").font(.caption2).foregroundStyle(Theme.accent)
                            }
                        }
                        Spacer()
                        Text(product.displayPrice + (product.id == ProManager.yearlyID ? "/year" : "/month"))
                            .font(.callout.weight(.semibold)).foregroundStyle(.white)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(selectedProductID == product.id ? 0.09 : 0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accent.opacity(selectedProductID == product.id ? 0.65 : 0.16)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var trialHeadline: String {
        guard let product = selectedProduct, pro.isEligibleForTrial(product),
              let offer = product.subscription?.introductoryOffer else {
            return "Batch conversion and automation across Apple devices"
        }
        return "Try every Premium feature free for \(periodText(offer.period))"
    }

    private var actionTitle: String {
        guard let product = selectedProduct else { return "Plans Unavailable" }
        return pro.isEligibleForTrial(product) ? "Start Free Trial" : "Subscribe for \(product.displayPrice)"
    }

    private var renewalDisclosure: String {
        guard let product = selectedProduct else { return "Free conversion remains available while plans load." }
        let interval = product.id == ProManager.yearlyID ? "year" : "month"
        if pro.isEligibleForTrial(product), let offer = product.subscription?.introductoryOffer {
            return "Free for \(periodText(offer.period)), then \(product.displayPrice) per \(interval). Auto-renews until cancelled in Apple Account settings."
        }
        return "\(product.displayPrice) per \(interval). Auto-renews until cancelled in Apple Account settings."
    }

    private func periodText(_ period: Product.SubscriptionPeriod) -> String {
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "day" : "days"
        case .week: unit = period.value == 1 ? "week" : "weeks"
        case .month: unit = period.value == 1 ? "month" : "months"
        case .year: unit = period.value == 1 ? "year" : "years"
        @unknown default: unit = "period"
        }
        return "\(period.value) \(unit)"
    }

    private func close() {
        engagement.recordPaywallDismissed()
        dismiss()
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(Theme.accent).frame(width: 22)
            Text(text).font(.callout).foregroundStyle(.white.opacity(0.9))
        }
    }
}
#endif
