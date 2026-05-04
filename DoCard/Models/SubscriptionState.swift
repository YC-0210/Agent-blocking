import Foundation

/// Product identifiers for StoreKit 2.
enum SubscriptionProduct {
    static let monthly = "online.do.card.app.premium.monthly.v2"
    static let annual = "online.do.card.app.premium.annual.v2"
    static let groupID = "DO Card Premium"

    static let allProductIDs: Set<String> = [monthly, annual]
}
