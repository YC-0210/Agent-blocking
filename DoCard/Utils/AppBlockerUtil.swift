import FamilyControls
import ManagedSettings
import SwiftUI

/// Thread-safe utility for managing ManagedSettingsStore restrictions.
/// NOT @MainActor because it is used from DeviceActivityMonitor extension callbacks
/// which run on background threads. ManagedSettingsStore is thread-safe by design.
class AppBlockerUtil {
  let store = ManagedSettingsStore(
    named: ManagedSettingsStore.Name("doCardAppRestrictions")
  )

  func activateRestrictions(for profile: SharedData.ProfileSnapshot) {
    guard AuthorizationCenter.shared.authorizationStatus == .approved else {
      print("⚠️ Family Controls not authorized. Cannot activate restrictions.")
      return
    }

    print("Starting restrictions...")

    let selection = profile.selectedActivity
    let allowOnlyApps = profile.enableAllowMode
    let allowOnlyDomains = profile.enableAllowModeDomains
    let enableSafariBlocking = profile.enableSafariBlocking
    let domains = getWebDomains(from: profile)

    let applicationTokens = selection.applicationTokens
    let categoriesTokens = selection.categoryTokens
    let webTokens = selection.webDomainTokens

    if allowOnlyApps {
      store.shield.applicationCategories =
        .all(except: applicationTokens)

      if enableSafariBlocking {
        store.shield.webDomainCategories = .all(except: webTokens)
      }

    } else {
      store.shield.applications = applicationTokens
      store.shield.applicationCategories = .specific(categoriesTokens)

      if enableSafariBlocking {
        store.shield.webDomainCategories = .specific(categoriesTokens)
        store.shield.webDomains = webTokens
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
    guard AuthorizationCenter.shared.authorizationStatus == .approved else {
      print("⚠️ Family Controls not authorized. Cannot deactivate restrictions.")
      return
    }

    print("Stopping restrictions...")

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
