import Foundation
import UserNotifications

/// Executes the shared phone command path before presenting a visible result notification.
final class NotificationService: UNNotificationServiceExtension, @unchecked Sendable {
  private let lock = NSLock()
  private var handler: ((UNNotificationContent) -> Void)?
  private var content: UNMutableNotificationContent?
  private var work: Task<Void, Never>?

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    guard request.content.userInfo["docardAgent"] as? Bool == true,
      let commandID = request.content.userInfo["commandId"] as? String,
      !commandID.isEmpty, commandID.utf8.count <= 80,
      let mutable = request.content.mutableCopy() as? UNMutableNotificationContent
    else {
      contentHandler(request.content)
      return
    }
    lock.lock()
    handler = contentHandler
    content = mutable
    lock.unlock()
    let task = Task { [weak self] in
      var outcome = AgentFocusDeliveryOutcome.pending
      do {
        let pairing = try AgentFocusPairingStore.load()
        let phone = try AgentFocusDevice.phone(lockTimeout: 0.2)
        guard try phone.status(pairingID: pairing.deviceId) != nil else {
          throw AgentFocusDevice.Failure.unavailable
        }
        try AgentFocusDevice.reconcile(lockTimeout: 0.2)
        let worker = AgentFocusDelivery(phone: phone, pairing: pairing)
        // The notification ID is only a hint. Commands and authority come from the authenticated relay.
        let result = await worker.run(commandID: commandID)
        outcome = result
      } catch { /* Keep the generic fallback; the main app can retry. */  }
      self?.finish(body: outcome.notificationBody)
    }
    lock.lock()
    if handler == nil { task.cancel() } else { work = task }
    lock.unlock()
  }

  override func serviceExtensionTimeWillExpire() {
    finish(body: AgentFocusDeliveryOutcome.pending.notificationBody)
  }

  private func finish(body: String) {
    lock.lock()
    let callback = handler
    let best = content
    best?.title = "DO Card"
    best?.body = body
    handler = nil
    content = nil
    let task = work
    work = nil
    lock.unlock()
    task?.cancel()
    if let callback, let best { callback(best) }
  }
}
