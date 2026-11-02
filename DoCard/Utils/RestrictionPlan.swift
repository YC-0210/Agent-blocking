import Foundation

struct RestrictionPlan<App: Hashable, Category: Hashable, Domain: Hashable>: Equatable {
  var apps: Set<App>
  var categories: Set<Category>
  var websites: Set<Domain>
  var allowOnlyApps: Bool
  var browserEnabled: Bool
  var customDomains: Set<String>
  var allowOnlyDomains: Bool
}

enum SelectionRules {
  static func canSave(appCount: Int, hasAccess: Bool) -> Bool {
    SubscriptionAccess.permits(.editSelection, hasAccess: hasAccess) && (0...50).contains(appCount)
  }

  static func plan<A, C, D>(
    apps: Set<A>, categories: Set<C>, websites: Set<D>,
    allowOnlyApps: Bool, browserEnabled: Bool, customDomains: Set<String>,
    allowOnlyDomains: Bool, hasAccess: Bool
  ) -> RestrictionPlan<A, C, D>? {
    guard canSave(appCount: apps.count, hasAccess: hasAccess) else { return nil }
    return RestrictionPlan(
      apps: apps, categories: categories,
      websites: browserEnabled ? websites : [], allowOnlyApps: allowOnlyApps,
      browserEnabled: browserEnabled, customDomains: customDomains,
      allowOnlyDomains: allowOnlyDomains)
  }
}
