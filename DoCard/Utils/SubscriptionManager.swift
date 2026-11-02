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

  @Published private(set) var accessRevision = 0
  private let store: any SubscriptionStore
  private let scheduleRuntimeTimers: Bool
  private let scheduleExpiry: () -> Void
  private var refreshSequence = 0
  private var statusListener: Task<Void, Never>?
  private var expiryTimer: Timer?
  private var transactionListener: Task<Void, Never>?

  init(
    store: (any SubscriptionStore)? = nil,
    startAutomatically: Bool = true,
    scheduleExpiry: @escaping () -> Void = { SubscriptionExpiry.schedule() }
  ) {
    self.store = store ?? StoreKitSubscriptionStore()
    self.scheduleExpiry = scheduleExpiry
    self.scheduleRuntimeTimers = startAutomatically
    tier = SharedData.effectiveSubscriptionTier
    expirationDate = SharedData.subscriptionAccessEnd
    if startAutomatically {
      transactionListener = listenForTransactions()
      statusListener = Task { [weak self] in
        for await status in Product.SubscriptionInfo.Status.updates {
          guard case .verified(let transaction) = status.transaction,
            SubscriptionAccess.productIDs.contains(transaction.productID)
          else { continue }
          await self?.checkCurrentEntitlements()
        }
      }
      Task { await loadInitialState() }
    }
  }

  deinit {
    transactionListener?.cancel()
    statusListener?.cancel()
    expiryTimer?.invalidate()
  }

  // MARK: - Initial Load

  private func loadInitialState() async {
    await checkCurrentEntitlements()
    await loadProducts()
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
        print(
          "⚠️ [StoreKit] Product array is empty — check App Store Connect IAP status and Sandbox account"
        )
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
    refreshSequence += 1
    let sequence = refreshSequence
    do {
      let grants = try await store.currentGrants()
      guard sequence == refreshSequence else { return }
      SharedData.subscriptionGrants = grants
      errorMessage = nil
    } catch {
      guard sequence == refreshSequence else { return }
      // A failed refresh cannot invent access or remove still-valid offline proof.
      errorMessage = String(localized: "Unable to check subscription. Please try again.")
    }
    refreshLocalAccess()
  }

  func refreshLocalAccess() {
    tier = SharedData.effectiveSubscriptionTier
    expirationDate = SharedData.subscriptionAccessEnd
    syncTierToAppGroup()
    scheduleExpiry()
    expiryTimer?.invalidate()
    if scheduleRuntimeTimers, let end = expirationDate {
      expiryTimer = Timer.scheduledTimer(
        withTimeInterval: max(0.01, end.timeIntervalSinceNow), repeats: false
      ) { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.refreshLocalAccess()
          await self?.checkCurrentEntitlements()
        }
      }
    }
    accessRevision += 1
  }

  func purchase(_ product: Product) async { await purchase(productID: product.id) }

  func purchase(productID: String) async {
    guard permits(.purchase), SubscriptionAccess.productIDs.contains(productID) else { return }
    purchaseInProgress = true
    defer { purchaseInProgress = false }
    do {
      switch try await store.purchase(productID: productID) {
      case .verified: await checkCurrentEntitlements()
      case .cancelled: break
      case .pending: errorMessage = String(localized: "購買處理中，請稍候")
      case .unverified: errorMessage = String(localized: "無法驗證購買，請重試")
      }
    } catch { errorMessage = String(localized: "購買失敗，請重試") }
  }

  func restorePurchases() async {
    guard permits(.restore) else { return }
    do {
      try await store.restore()
      await checkCurrentEntitlements()
    } catch { errorMessage = String(localized: "恢復購買失敗，請重試") }
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

  private func handleVerifiedTransaction(_ transaction: StoreKit.Transaction) async {
    guard SubscriptionAccess.productIDs.contains(transaction.productID) else { return }
    // Re-read the complete verified state: an old event must not overwrite a renewal.
    await checkCurrentEntitlements()
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
  /// agree, including during the Apple-confirmed billing grace period after a lapsed renewal.
  var isPremium: Bool {
    return SharedData.effectiveSubscriptionTier == .premium
  }

  /// The current user's entitlements (grace-aware). UI gates should ask this rule
  /// book — e.g. `subscriptionManager.entitlements.canSchedule` — instead of
  /// re-deriving the free/premium rules at each call site.
  var entitlements: Entitlements {
    return Entitlements.current
  }

  func permits(_ action: SubscriptionAction) -> Bool {
    SubscriptionAccess.permits(action, hasAccess: isPremium)
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
