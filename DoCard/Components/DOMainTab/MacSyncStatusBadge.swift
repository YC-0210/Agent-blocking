import SwiftUI

/// Small inline badge shown during an active session to tell the user whether
/// the Mac side actually received the start signal. Hidden when the user has
/// never paired a Mac (no signal to show).
struct MacSyncStatusBadge: View {
  @ObservedObject var sync: MacSessionSyncService

  var body: some View {
    if shouldDisplay {
      HStack(spacing: 6) {
        icon
        Text(label)
          .font(.system(size: 11, weight: .medium))
      }
      .foregroundColor(color)
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .background(
        Capsule()
          .fill(color.opacity(0.15))
      )
    }
  }

  private var shouldDisplay: Bool {
    MacPairingService.sharedDefaults.bool(forKey: MacPairingService.hasEverSyncedKey)
      || sync.pendingEndCount > 0
  }

  @ViewBuilder
  private var icon: some View {
    switch sync.status {
    case .syncing:
      ProgressView()
        .progressViewStyle(.circular)
        .scaleEffect(0.5)
        .frame(width: 10, height: 10)
    case .synced:
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 10))
    case .failed:
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 10))
    case .idle:
      Image(systemName: "laptopcomputer")
        .font(.system(size: 10))
    }
  }

  private var label: String {
    switch sync.status {
    case .synced:
      return String(localized: "Chrome / Safari 已連動")
    case .syncing:
      return String(localized: "Chrome / Safari 同步中")
    case .failed:
      return sync.pendingEndCount > 0
        ? String(localized: "Chrome / Safari 重試中")
        : String(localized: "Chrome / Safari 同步失敗")
    case .idle:
      return String(localized: "Chrome / Safari 連動")
    }
  }

  private var color: Color {
    switch sync.status {
    case .synced: return .green
    case .syncing, .idle: return .white.opacity(0.6)
    case .failed: return .orange
    }
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    MacSyncStatusBadge(sync: MacSessionSyncService.shared)
  }
}
