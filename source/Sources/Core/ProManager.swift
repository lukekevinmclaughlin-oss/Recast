import Foundation
import StoreKit

/// Auto-renewable subscription access. The one-week trial is configured as an
/// introductory offer in App Store Connect, so Apple—not local state—controls
/// eligibility, billing, cancellation and restoration across devices.
@MainActor
final class ProManager: ObservableObject {
    static let shared = ProManager()
    static let monthlyID = "com.lukemclaughlin.recast.monthly"
    static let yearlyID = "com.lukemclaughlin.recast.yearly"
    static let productIDs: Set<String> = [monthlyID, yearlyID]

    @Published private(set) var isPro = false
    @Published private(set) var products: [Product] = []
    @Published var lastError: String?
    private var updatesTask: Task<Void, Never>?

    private init() {
        #if DEBUG
        isPro = UserDefaults.standard.bool(forKey: "debug.forcePro") || ProcessInfo.processInfo.environment["RECAST_DEMO"] == "1"
        #endif
        updatesTask = listenForTransactions()
        Task { await refresh() }
    }

    var hasAccess: Bool { isPro }
    var monthlyProduct: Product? { products.first { $0.id == Self.monthlyID } }
    var yearlyProduct: Product? { products.first { $0.id == Self.yearlyID } }
    var monthlyPrice: String { monthlyProduct?.displayPrice ?? "€2,99" }
    var yearlyPrice: String { yearlyProduct?.displayPrice ?? "€19,99" }

    func refresh() async {
        do {
            products = try await Product.products(for: Self.productIDs)
                .sorted { $0.id == Self.yearlyID && $1.id != Self.yearlyID }
        } catch { products = [] }
        await updateEntitlement()
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            if case .success(let verification) = result,
               case .verified(let transaction) = verification {
                await transaction.finish()
                await updateEntitlement()
            }
        } catch { lastError = error.localizedDescription }
    }

    func purchaseYearly() async {
        guard let product = yearlyProduct else {
            lastError = "Subscriptions aren’t available right now. Please try again later."
            return
        }
        await purchase(product)
    }

    func purchaseMonthly() async {
        guard let product = monthlyProduct else {
            lastError = "Subscriptions aren’t available right now. Please try again later."
            return
        }
        await purchase(product)
    }

    func restore() async {
        do { try await AppStore.sync() }
        catch { lastError = error.localizedDescription }
        await updateEntitlement()
    }

    private func updateEntitlement() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               Self.productIDs.contains(transaction.productID),
               transaction.revocationDate == nil,
               (transaction.expirationDate ?? .distantFuture) > Date() {
                active = true
            }
        }
        #if DEBUG
        active = active || UserDefaults.standard.bool(forKey: "debug.forcePro") || ProcessInfo.processInfo.environment["RECAST_DEMO"] == "1"
        #endif
        isPro = active
    }

    #if DEBUG
    func toggleDebugPro() {
        let new = !UserDefaults.standard.bool(forKey: "debug.forcePro")
        UserDefaults.standard.set(new, forKey: "debug.forcePro")
        isPro = new
    }
    #endif

    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await updateEntitlement()
                }
            }
        }
    }
}
