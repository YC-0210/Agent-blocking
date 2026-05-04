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

  func effectiveShieldSelection(for profile: SharedData.ProfileSnapshot) -> EffectiveShieldSelection {
    let selection = profile.selectedActivity
    let allowOnlyApps = profile.enableAllowMode

    var applicationTokens = selection.applicationTokens
    var categoryTokens = selection.categoryTokens
    var webDomainTokens = selection.webDomainTokens

    let tier = SharedData.effectiveSubscriptionTier
    if tier == .free && !allowOnlyApps {
      let limit = 3
      if applicationTokens.count > limit {
        applicationTokens = Set(Array(applicationTokens).prefix(limit))
      }
      categoryTokens = []
      webDomainTokens = []
    } else if !allowOnlyApps {
      let premiumLimit = 50
      if applicationTokens.count > premiumLimit {
        applicationTokens = Set(Array(applicationTokens).prefix(premiumLimit))
      }
    }

    return EffectiveShieldSelection(
      applicationTokens: applicationTokens,
      categoryTokens: categoryTokens,
      webDomainTokens: webDomainTokens,
      tier: tier,
      allowOnlyApps: allowOnlyApps
    )
  }

  func wouldShieldAnything(for profile: SharedData.ProfileSnapshot) -> Bool {
    let effectiveSelection = effectiveShieldSelection(for: profile)

    if effectiveSelection.allowOnlyApps {
      return true
    }

    return !effectiveSelection.applicationTokens.isEmpty
      || !effectiveSelection.categoryTokens.isEmpty
      || !effectiveSelection.webDomainTokens.isEmpty
  }

  func activateRestrictions(for profile: SharedData.ProfileSnapshot) {
    // NOTE: No AuthorizationCenter.shared.authorizationStatus check here.
    // Authorization is enforced at the UI level. Checking it here breaks
    // extension-based activation because AuthorizationCenter.shared does not
    // reliably return .approved in the DeviceActivityMonitor extension process.
    abLog.debug("Starting restrictions...")
    abLog.debug("📊 App tokens: \(profile.selectedActivity.applicationTokens.count), Category tokens: \(profile.selectedActivity.categoryTokens.count), Web tokens: \(profile.selectedActivity.webDomainTokens.count)")

    let allowOnlyDomains = profile.enableAllowModeDomains
    let enableSafariBlocking = profile.enableSafariBlocking
    let domains = getWebDomains(from: profile)
    let effectiveSelection = effectiveShieldSelection(for: profile)
    let allowOnlyApps = effectiveSelection.allowOnlyApps
    let tier = effectiveSelection.tier
    let applicationTokens = effectiveSelection.applicationTokens
    let categoriesTokens = effectiveSelection.categoryTokens
    let webTokens = effectiveSelection.webDomainTokens

    // Guard: if not in allow mode and all effective tokens are empty after tier enforcement,
    // skip activation entirely — setting shields to nil would CLEAR existing restrictions.
    if !allowOnlyApps && applicationTokens.isEmpty && categoriesTokens.isEmpty && webTokens.isEmpty {
      abLog.warning("activateRestrictions: skipping — all tokens are empty after tier enforcement for profile '\(profile.id.uuidString)' (tier: \(tier.rawValue)). No apps would be blocked; existing shields preserved.")
      return
    }

    if allowOnlyApps {
      store.shield.applicationCategories =
        .all(except: applicationTokens)

      if enableSafariBlocking {
        store.shield.webDomainCategories = .all(except: webTokens)
      }

    } else {
      // MARK: - Block mode shield application
      // IMPORTANT: Use nil (not .specific([])) for empty sets to avoid
      // unexpected interactions between shield settings (Apple bug).
      // When categories are selected, block at the CATEGORY level — this ensures
      // all apps in the category are blocked, including newly installed ones.
      // Individual applicationTokens are set separately for non-category apps.
      //
      // With includeEntireCategory: true, applicationTokens includes expanded
      // category apps. We must still pass categoryTokens to shield.applicationCategories
      // so the system blocks at the category level (more reliable than individual tokens).

      store.shield.applications = applicationTokens.isEmpty ? nil : applicationTokens
      store.shield.applicationCategories = categoriesTokens.isEmpty ? nil : .specific(categoriesTokens)

      if enableSafariBlocking {
        store.shield.webDomainCategories = categoriesTokens.isEmpty ? nil : .specific(categoriesTokens)
        store.shield.webDomains = webTokens.isEmpty ? nil : webTokens
      }
    }

    if allowOnlyDomains {
      store.webContent.blockedByFilter = .all(except: domains)
    } else {
      store.webContent.blockedByFilter = .specific(domains)
    }

    // Note: denyAppRemoval removed — not appropriate for .individual authorization.
    // The NFC-card-to-unlock mechanism provides sufficient behavioral friction.
  }

  func deactivateRestrictions() {
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
