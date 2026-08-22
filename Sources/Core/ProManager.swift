import Foundation
import StoreKit

/// StoreKit 2 is the only source of truth for Premium access. Recast never
/// caches an entitlement as active after StoreKit says it expired or was revoked.
@MainActor
final class ProManager: ObservableObject {
    enum AccessState: Equatable {
        case loading
        case free
        case active(productID: String, expirationDate: Date?, willAutoRenew: Bool)
        case gracePeriod(productID: String, expirationDate: Date?)
        case billingRetry
        case expired
        case revoked
    }

    static let shared = ProManager()
    static let monthlyID = "com.lukemclaughlin.recast.premium.monthly"
    static let yearlyID = "com.lukemclaughlin.recast.premium.annual"
    static let productIDs: Set<String> = [monthlyID, yearlyID]

    @Published private(set) var accessState: AccessState = .loading
    @Published private(set) var products: [Product] = []
    @Published private(set) var introEligibleProductIDs: Set<String> = []
    @Published private(set) var isLoading = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false
    @Published var lastError: String?
    @Published var statusMessage: String?

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = listenForTransactions()
        Task { await refresh() }
    }

    deinit { updatesTask?.cancel() }

    var isPro: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "debug.forcePro") ||
            ProcessInfo.processInfo.environment["RECAST_DEMO"] == "1" { return true }
        #endif
        #if DIRECT_DISTRIBUTION
        return true
        #else
        switch accessState {
        case .active, .gracePeriod: return true
        default: return false
        }
        #endif
    }

    var hasAccess: Bool { isPro }
    var monthlyProduct: Product? { products.first { $0.id == Self.monthlyID } }
    var yearlyProduct: Product? { products.first { $0.id == Self.yearlyID } }
    var monthlyPrice: String { monthlyProduct?.displayPrice ?? "Monthly plan" }
    var yearlyPrice: String { yearlyProduct?.displayPrice ?? "Annual plan" }

    func isEligibleForTrial(_ product: Product) -> Bool {
        introEligibleProductIDs.contains(product.id) && product.subscription?.introductoryOffer != nil
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            products = try await Product.products(for: Self.productIDs)
                .sorted { lhs, rhs in
                    if lhs.id == Self.yearlyID { return true }
                    if rhs.id == Self.yearlyID { return false }
                    return lhs.displayName < rhs.displayName
                }
            var eligible: Set<String> = []
            for product in products where await product.subscription?.isEligibleForIntroOffer == true {
                eligible.insert(product.id)
            }
            introEligibleProductIDs = eligible
            if products.isEmpty {
                lastError = "Premium plans are temporarily unavailable from the App Store. Free conversion remains available."
            }
        } catch {
            products = []
            introEligibleProductIDs = []
            lastError = "Premium plans could not be loaded. Free conversion remains available."
        }
        await updateEntitlement()
    }

    func purchase(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        lastError = nil
        statusMessage = nil
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                let transaction = try verified(verification)
                await transaction.finish()
                await updateEntitlement()
                statusMessage = isPro ? "Premium is active on this device." : nil
            case .pending:
                statusMessage = "Your purchase is pending approval. Recast will unlock automatically when Apple completes it."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = "The purchase could not be verified. You have not been charged by Recast."
        }
    }

    func purchaseYearly() async {
        guard let product = yearlyProduct else {
            lastError = "The annual plan isn’t available right now. Please try again later."
            return
        }
        await purchase(product)
    }

    func purchaseMonthly() async {
        guard let product = monthlyProduct else {
            lastError = "The monthly plan isn’t available right now. Please try again later."
            return
        }
        await purchase(product)
    }

    func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        lastError = nil
        statusMessage = nil
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
            await updateEntitlement()
            statusMessage = isPro
                ? "Your Premium subscription has been restored."
                : "No active Recast Premium subscription was found for this Apple Account."
        } catch {
            lastError = "Purchases could not be restored. Check your App Store connection and try again."
        }
    }

    func updateEntitlement() async {
        var activeTransaction: Transaction?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  Self.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil,
                  (transaction.expirationDate ?? .distantFuture) > Date() else { continue }
            if activeTransaction == nil ||
                (transaction.expirationDate ?? .distantFuture) > (activeTransaction?.expirationDate ?? .distantPast) {
                activeTransaction = transaction
            }
        }

        var renewalByProduct: [String: Product.SubscriptionInfo.RenewalInfo] = [:]
        var stateByProduct: [String: Product.SubscriptionInfo.RenewalState] = [:]
        for product in products {
            guard let statuses = try? await product.subscription?.status else { continue }
            for status in statuses {
                guard let transaction = try? verified(status.transaction),
                      let renewal = try? verified(status.renewalInfo),
                      Self.productIDs.contains(transaction.productID) else { continue }
                renewalByProduct[transaction.productID] = renewal
                stateByProduct[transaction.productID] = status.state
            }
        }

        if let transaction = activeTransaction {
            let state = stateByProduct[transaction.productID]
            if state == .inGracePeriod {
                accessState = .gracePeriod(productID: transaction.productID,
                                           expirationDate: transaction.expirationDate)
            } else {
                let autoRenews = renewalByProduct[transaction.productID]?.willAutoRenew == true
                accessState = .active(productID: transaction.productID,
                                      expirationDate: transaction.expirationDate,
                                      willAutoRenew: autoRenews)
            }
            return
        }

        if stateByProduct.values.contains(.inBillingRetryPeriod) {
            accessState = .billingRetry
        } else if stateByProduct.values.contains(.revoked) {
            accessState = .revoked
        } else if stateByProduct.values.contains(.expired) {
            accessState = .expired
        } else {
            accessState = .free
        }
    }

    #if DEBUG
    func toggleDebugPro() {
        let newValue = !UserDefaults.standard.bool(forKey: "debug.forcePro")
        UserDefaults.standard.set(newValue, forKey: "debug.forcePro")
        objectWillChange.send()
    }
    #endif

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): return value
        case .unverified: throw StoreError.failedVerification
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.updateEntitlement()
                }
            }
        }
    }

    private enum StoreError: Error { case failedVerification }
}
