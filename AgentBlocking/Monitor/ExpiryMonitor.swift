import DeviceActivity

final class ExpiryMonitor: DeviceActivityMonitor {
  override func intervalDidStart(for activity: DeviceActivityName) {
    super.intervalDidStart(for: activity)
    AgentFocusDevice.intervalStarted(activity)
  }

  override func intervalDidEnd(for activity: DeviceActivityName) {
    super.intervalDidEnd(for: activity)
    AgentFocusDevice.intervalEnded(activity)
  }
}
