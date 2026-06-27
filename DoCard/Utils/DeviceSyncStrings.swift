import Foundation

/// Single source of truth for the device-sync feature's user-facing name.
///
/// The feature pairs the iPhone with other devices to mirror its blocking
/// signal — today the Mac browser extensions (Chrome / Safari), and soon iPad.
/// The name was generalised from the old browser-specific "Chrome / Safari 連動"
/// to "裝置同步" / "Device Sync" so it fits every paired device. Both the
/// Settings entry row and the pairing screen's navigation title read from here
/// so the two can never drift.
enum DeviceSyncStrings {
  /// "裝置同步" / "Device Sync" — the feature title shown in Settings and as the
  /// pairing screen's navigation title.
  static var featureTitle: String { String(localized: "裝置同步") }
}
