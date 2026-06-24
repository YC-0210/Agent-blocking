import OSLog
import StoreKit
import SwiftUI

private let logger = Logger(subsystem: "app.docard", category: "Subscription")

@MainActor
class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    @Published private(set) var tier: SubscriptionTier = .free
    @Published private(set) var expirationDate: Date?
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var productsLoadFailed = false
    @Published private(set) var purchaseInProgress = false
    @Published var errorMessage: String?

    private var transactionListener: Task<Void, Never>?

    init() {
        transactionListener = listenForTransactions()
        Task { await loadInitialState() }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Initial Load

    private func loadInitialState() async {
        await loadProducts()
        await checkCurrentEntitlements()
    }

    // MARK: - Products

    func loadProducts() async {
        isLoadingProducts = true
        productsLoadFailed = false
        defer { isLoadingProducts = false }

        do {
            print("🔍 [StoreKit] Fetching product IDs: \(SubscriptionProduct.allProductIDs)")
            let storeProducts = try await Product.products(
                for: SubscriptionProduct.allProductIDs
            )
            print("✅ [StoreKit] Products loaded: \(storeProducts.map { $0.id })")
            if storeProducts.isEmpty {
                print("⚠️ [StoreKit] Product array is empty — check App Store Connect IAP status and Sandbox account")
                productsLoadFailed = true
            }
            // Sort: monthly first, then annual
            products = storeProducts.sorted { a, _ in
                a.id == SubscriptionProduct.monthly
            }
        } catch {
            print("❌ [StoreKit] loadProducts failed: \(error)")
            logger.error("Failed to load products: \(error.localizedDescription)")
            productsLoadFailed = true
        }
    }

    // MARK: - Entitlement Check

    func checkCurrentEntitlements() async {
        var foundPremium = false

        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               SubscriptionProduct.allProductIDs.contains(transaction.productID),
               transaction.revocationDate == nil
            {
                foundPremium = true
                expirationDate = transaction.expirationDate
                break
            }
        }

        let newTier: SubscriptionTier = foundPremium ? .premium : .free
        tier = newTier
        // Always sync to App Group regardless of whether tier changed.
        // This ensures extensions and AppBlockerUtil see the correct tier after
        // a reinstall or App Group data wipe — not just on first purchase.
        syncTierToAppGroup()
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        purchaseInProgress = true
        defer { purchaseInProgress = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    tier = .premium
                    expirationDate = transaction.expirationDate
                    syncTierToAppGroup()
                    await transaction.finish()
                    logger.info("Purchase successful: \(product.id)")
                } else {
                    errorMessage = String(localized: "無法驗證購買，請重試")
                }

            case .userCancelled:
                break

            case .pending:
                errorMessage = String(localized: "購買處理中，請稍候")

            @unknown default:
                break
            }
        } catch {
            logger.error("Purchase failed: \(error.localizedDescription)")
            errorMessage = String(localized: "購買失敗，請重試")
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await checkCurrentEntitlements()
        } catch {
            logger.error("Restore failed: \(error.localizedDescription)")
            errorMessage = String(localized: "恢復購買失敗，請重試")
        }
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in StoreKit.Transaction.updates {
                if case .verified(let transaction) = result {
                    await self?.handleVerifiedTransaction(transaction)
                    await transaction.finish()
                }
            }
        }
    }

    private func handleVerifiedTransaction(_ transaction: StoreKit.Transaction) {
        guard SubscriptionProduct.allProductIDs.contains(transaction.productID) else {
            return
        }

        if transaction.revocationDate != nil {
            tier = .free
            expirationDate = nil
        } else {
            tier = .premium
            expirationDate = transaction.expirationDate
        }
        syncTierToAppGroup()
    }

    // MARK: - App Group Sync

    private func syncTierToAppGroup() {
        SharedData.subscriptionTier = tier
        if let expiration = expirationDate {
            SharedData.subscriptionExpirationDate = expiration
        } else {
            SharedData.subscriptionExpirationDate = nil
        }
        logger.info("Synced tier to App Group: \(self.tier.rawValue)")
    }

    // MARK: - Helpers

    /// Grace-aware premium status. Reads `SharedData.effectiveSubscriptionTier` —
    /// the same source the enforcement gate uses — so the UI and the blocking engine
    /// agree, including during the 16-day billing grace period after a lapsed renewal.
    var isPremium: Bool {
        return SharedData.effectiveSubscriptionTier == .premium
    }

    /// The current user's entitlements (grace-aware). UI gates should ask this rule
    /// book — e.g. `subscriptionManager.entitlements.canSchedule` — instead of
    /// re-deriving the free/premium rules at each call site.
    var entitlements: Entitlements {
        return Entitlements.current
    }

    var monthlyProduct: Product? {
        products.first { $0.id == SubscriptionProduct.monthly }
    }

    var annualProduct: Product? {
        products.first { $0.id == SubscriptionProduct.annual }
    }

    // App-block limits now live on the `Entitlements` rule book
    // (`Entitlements.freeAppLimit` / `Entitlements.premiumAppLimit`).
}
