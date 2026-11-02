import FamilyControls
import ManagedSettings
import OSLog
import SwiftUI

private let abLog = Logger(subsystem: "app.docard", category: "AppBlockerUtil")

/// Thread-safe utility for managing ManagedSettingsStore restrictions.
/// NOT @MainActor because it is used from DeviceActivityMonitor extension callbacks
/// which run on background threads. ManagedSettingsStore is thread-safe by design.
class AppBlockerUtil {
  struct EffectiveShieldSelection {
    let applicationTokens: Set<ApplicationToken>
    let categoryTokens: Set<ActivityCategoryToken>
    let webDomainTokens: Set<WebDomainToken>
    let tier: SubscriptionTier
    let allowOnlyApps: Bool
  }

  let store = ManagedSettingsStore(
    named: ManagedSettingsStore.Name("doCardAppRestrictions")
  )

  typealias Plan = RestrictionPlan<ApplicationToken, ActivityCategoryToken, WebDomainToken>
  private let write: ((Plan?) -> Void)?

  init(write: ((Plan?) -> Void)? = nil) { self.write = write }

  func restrictionPlan(for profile: SharedData.ProfileSnapshot) -> Plan? {
    SelectionRules.plan(
      apps: profile.selectedActivity.applicationTokens,
      categories: profile.selectedActivity.categoryTokens,
      websites: profile.selectedActivity.webDomainTokens,
      allowOnlyApps: profile.enableAllowMode, browserEnabled: profile.enableSafariBlocking,
      customDomains: Set(profile.domains ?? []), allowOnlyDomains: profile.enableAllowModeDomains,
      hasAccess: SharedData.effectiveSubscriptionTier == .premium)
  }

  func effectiveShieldSelection(for profile: SharedData.ProfileSnapshot) -> EffectiveShieldSelection
  {
    let plan = restrictionPlan(for: profile)
    return EffectiveShieldSelection(
      applicationTokens: plan?.apps ?? [],
      categoryTokens: plan?.categories ?? [], webDomainTokens: plan?.websites ?? [],
      tier: SharedData.effectiveSubscriptionTier, allowOnlyApps: plan?.allowOnlyApps ?? false)
  }

  func wouldShieldAnything(for profile: SharedData.ProfileSnapshot) -> Bool {
    guard let plan = restrictionPlan(for: profile) else { return false }
    return plan.allowOnlyApps || plan.allowOnlyDomains || !plan.apps.isEmpty
      || !plan.categories.isEmpty || !plan.websites.isEmpty || !plan.customDomains.isEmpty
  }

  func activateRestrictions(for profile: SharedData.ProfileSnapshot) {
    guard SharedData.effectiveSubscriptionTier == .premium else {
      deactivateRestrictions()
      return
    }
    guard let plan = restrictionPlan(for: profile) else { return }
    guard wouldShieldAnything(for: profile) else { return }
    // The recorder lives below the production policy; tests never bypass the gate.
    if let write {
      write(plan)
      return
    }
    // Replace the full plan so previous allow-mode/browser settings cannot linger.
    store.clearAllSettings()
    if plan.allowOnlyApps {
      store.shield.applicationCategories = .all(except: plan.apps)
      if plan.browserEnabled { store.shield.webDomainCategories = .all(except: plan.websites) }
    } else {
      store.shield.applications = plan.apps.isEmpty ? nil : plan.apps
      store.shield.applicationCategories =
        plan.categories.isEmpty ? nil : .specific(plan.categories)
      if plan.browserEnabled {
        store.shield.webDomainCategories =
          plan.categories.isEmpty ? nil : .specific(plan.categories)
        store.shield.webDomains = plan.websites.isEmpty ? nil : plan.websites
      }
    }
    let domains = Set(plan.customDomains.map { WebDomain(domain: $0) })
    store.webContent.blockedByFilter =
      plan.allowOnlyDomains ? .all(except: domains) : .specific(domains)
  }

  func deactivateRestrictions() {
    if let write {
      write(nil)
      return
    }
    abLog.debug("Stopping restrictions...")

    store.shield.applications = nil
    store.shield.applicationCategories = nil
    store.shield.webDomains = nil
    store.shield.webDomainCategories = nil

    store.webContent.blockedByFilter = nil

    store.clearAllSettings()
  }

  func getWebDomains(from profile: SharedData.ProfileSnapshot) -> Set<WebDomain> {
    if let domains = profile.domains {
      return Set(domains.map { WebDomain(domain: $0) })
    }

    return []
  }
}
