import Foundation

/// The single source of truth for "what is this subscription tier allowed to do?".
///
/// `Entitlements` is the project's **rule book**: every UI gate and every enforcement
/// gate asks it, instead of each call site re-deriving the free/premium rules for
/// itself. It is a pure value type that depends only on `SubscriptionTier`, so it
/// compiles into the app *and* its extensions, and its core logic (`forTier`) is
/// trivial to unit-test with no I/O.
///
/// IMPORTANT — App Store rules. This rule book governs **paid** capabilities only.
/// The always-free flows must NEVER be routed through it:
///   • NFC card tap (start / stop blocking)
///   • Emergency Unlock
///   • RequestAuthorization (Family Controls permission)
/// Keep those flows entirely independent of `Entitlements`.
struct Entitlements {
  /// Maximum number of individual apps that may be blocked.
  let appLimit: Int
  /// Whether whole app *categories* may be blocked.
  let canBlockCategories: Bool
  /// Whether *website* domains may be blocked.
  let canBlockWebDomains: Bool
  /// Whether scheduled automation (time-based blocking) is available.
  let canSchedule: Bool
  /// Whether sessions sync to a paired Mac / Chrome / Safari.
  let canSyncExternalDevices: Bool
  /// Whether the deep Focus Report (focus score, trends, peak time) is shown
  /// unblurred. The data is always computed; this gates only its presentation.
  let canSeeDeepReport: Bool
  /// Whether Co-Focus (shared focus) may be started or joined.
  ///
  /// Co-Focus is free for every tier today, so this is `true` everywhere. The slot
  /// exists so that gating it later is a one-line change here plus a UI gate at the
  /// pairing entry point. NOTE: even once gated, this must only ever guard
  /// *creating / joining* a pairing — never `recordCoFocusTapFromNFC()` inside an
  /// already-paired session, which is part of the always-free NFC flow.
  let canUseCoFocus: Bool

  /// Free-tier app cap. Also the hard ceiling the enforcement gate trims down to.
  static let freeAppLimit = 3
  /// Premium-tier app cap — Apple's Family Controls hard limit, not "unlimited".
  static let premiumAppLimit = 50

  /// The rule book for a given tier. This `switch` is the one and only place the
  /// free-vs-premium rules are defined.
  static func forTier(_ tier: SubscriptionTier) -> Entitlements {
    switch tier {
    case .free:
      return Entitlements(
        appLimit: freeAppLimit,
        canBlockCategories: false,
        canBlockWebDomains: false,
        canSchedule: false,
        canSyncExternalDevices: false,
        canSeeDeepReport: false,
        canUseCoFocus: true
      )
    case .premium:
      return Entitlements(
        appLimit: premiumAppLimit,
        canBlockCategories: true,
        canBlockWebDomains: true,
        canSchedule: true,
        canSyncExternalDevices: true,
        canSeeDeepReport: true,
        canUseCoFocus: true
      )
    }
  }

  /// The current user's entitlements, honoring the 16-day billing grace period.
  ///
  /// Reads `SharedData.effectiveSubscriptionTier` — the same grace-aware source the
  /// enforcement gate uses — so the UI and the blocking engine never disagree (for
  /// example, during the grace period after a lapsed renewal).
  static var current: Entitlements {
    forTier(SharedData.effectiveSubscriptionTier)
  }
}
