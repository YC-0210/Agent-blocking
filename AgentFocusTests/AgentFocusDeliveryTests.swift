import Foundation
import XCTest

@testable import AgentFocusCore

final class AgentFocusDeliveryTests: XCTestCase {
  func testExpiryNotificationCannotExecuteAPendingStart() async throws {
    let fixture = try DeliveryFixture()
    defer { fixture.cleanup() }
    let result = await fixture.worker.run(expiryCheck: true)
    XCTAssertEqual(result, .expiryChecked)
    XCTAssertFalse(fixture.shielded)
    XCTAssertNil(try fixture.phone.status(pairingID: "device")?.session)
    XCTAssertFalse(fixture.commandFetchRequested)
  }

  func testEarlyExpiryNotificationPreservesTheLiveDeadline() async throws {
    let fixture = try DeliveryFixture()
    defer { fixture.cleanup() }
    _ = try fixture.phone.receive(fixture.command, pairingID: "device")
    let before = try fixture.phone.status(pairingID: "device")?.session
    fixture.clock += 899_999
    let outcome = await fixture.worker.run(expiryCheck: true)
    XCTAssertEqual(outcome, .expiryChecked)
    XCTAssertTrue(fixture.shielded)
    XCTAssertEqual(try fixture.phone.status(pairingID: "device")?.session, before)
    XCTAssertFalse(fixture.commandFetchRequested)
  }

  func testExpiryNotificationReleasesAfterAMissedMonitorCallbackAndPublishesStatus() async throws {
    let fixture = try DeliveryFixture()
    defer { fixture.cleanup() }
    _ = try fixture.phone.receive(fixture.command, pairingID: "device")
    fixture.clock += 900_000
    let outcome = await fixture.worker.run(expiryCheck: true)
    XCTAssertEqual(outcome, .expired)
    XCTAssertFalse(fixture.shielded)
    XCTAssertNil(try fixture.phone.status(pairingID: "device")?.session)
    XCTAssertFalse(fixture.commandFetchRequested)
    let snapshot = try XCTUnwrap(
      JSONSerialization.jsonObject(with: try XCTUnwrap(fixture.snapshots.last)) as? [String: Any])
    XCTAssertNil(snapshot["sessionID"])
    XCTAssertEqual(snapshot["maximumMinutes"] as? Int, 45)
    XCTAssertEqual(snapshot["requiresRenewalApproval"] as? Bool, true)
  }

  func testOldExpiryNotificationCannotReleaseANewerUnexpiredSession() async throws {
    let fixture = try DeliveryFixture()
    defer { fixture.cleanup() }
    _ = try fixture.phone.receive(fixture.command, pairingID: "device")
    fixture.clock += 10_000
    try fixture.phone.emergencyUnlock()
    let mode = try XCTUnwrap(fixture.phone.status()?.policy.modeID)
    let newer = FocusCommand(
      id: "newer", sequence: 2, action: .start, modeID: mode,
      durationMinutes: 30, sessionID: "newer-session", issuedAt: fixture.clock,
      expiresAt: fixture.clock + 120_000)
    XCTAssertEqual(try fixture.phone.receive(newer, pairingID: "device").status, "applied")
    let before = try fixture.phone.status()?.session
    fixture.clock += 890_001
    let outcome = await fixture.worker.run(expiryCheck: true)
    XCTAssertEqual(outcome, .expiryChecked)
    XCTAssertTrue(fixture.shielded)
    XCTAssertEqual(try fixture.phone.status()?.session, before)
    XCTAssertFalse(fixture.commandFetchRequested)
  }

  func testExpiryReleasesLocallyEvenIfStatusUploadFails() async throws {
    let fixture = try DeliveryFixture()
    defer { fixture.cleanup() }
    _ = try fixture.phone.receive(fixture.command, pairingID: "device")
    fixture.clock += 900_000
    fixture.failAllRequests = true
    let outcome = await fixture.worker.run(expiryCheck: true)
    XCTAssertEqual(outcome, .expired)
    XCTAssertFalse(fixture.shielded)
    XCTAssertNil(try fixture.phone.status()?.session)
    XCTAssertTrue(fixture.snapshots.isEmpty)
  }

  func testNotificationStartsPhoneFocusWithoutForegroundRuntime() async throws {
    let fixture = try DeliveryFixture()
    defer { fixture.cleanup() }
    let outcome = await fixture.worker.run(commandID: "start")
    XCTAssertEqual(outcome, .applied)
    XCTAssertEqual(try fixture.phone.status(pairingID: "device")?.session?.id, "session")
    XCTAssertTrue(fixture.shielded)
    XCTAssertEqual(fixture.receipts.first?.status, "applied")
  }
  func testReceiptUploadFailureDoesNotPreventANewUnlock() async throws {
    let fixture = try DeliveryFixture()
    defer { fixture.cleanup() }
    _ = try fixture.phone.receive(fixture.command, pairingID: "device")
    fixture.command = FocusCommand(
      id: "stop", sequence: 2, action: .stop, modeID: "work",
      durationMinutes: nil, sessionID: "session", issuedAt: fixture.clock,
      expiresAt: fixture.clock + 120000)
    fixture.failReceiptUploads = true
    let outcome = await fixture.worker.run(commandID: "stop")
    XCTAssertEqual(outcome, .applied)
    XCTAssertFalse(fixture.shielded)
    XCTAssertNil(try fixture.phone.status(pairingID: "device")?.session)
    XCTAssertEqual(
      try fixture.phone.pendingReceipts(pairingID: "device").map(\.id), ["start", "stop"])
  }

  func testExpiredCommandCannotBlockFromANotification() async throws {
    let fixture = try DeliveryFixture()
    defer { fixture.cleanup() }
    fixture.command = FocusCommand(
      id: "start", sequence: 1, action: .start, modeID: "work",
      durationMinutes: 15, sessionID: "session", issuedAt: fixture.clock - 120001,
      expiresAt: fixture.clock - 1)
    let result = await fixture.worker.run(commandID: "start")
    XCTAssertEqual(result, .rejected)
    XCTAssertFalse(fixture.shielded)
    XCTAssertEqual(fixture.receipts.first?.reason, "expired_or_future_command")
  }

  func testCancelledNotificationLeavesThePhoneUnchanged() async throws {
    let fixture = try DeliveryFixture()
    defer { fixture.cleanup() }
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return await fixture.worker.run(commandID: "start")
    }
    let result = await task.value
    XCTAssertEqual(result, .pending)
    XCTAssertFalse(fixture.shielded)
    XCTAssertNil(try fixture.phone.status(pairingID: "device")?.session)
  }

  func testAlreadyProcessedNotificationReportsAuthenticatedResultWithoutReapplying() async throws {
    let fixture = try DeliveryFixture()
    defer { fixture.cleanup() }
    let receipt = try fixture.phone.receive(fixture.command, pairingID: "device")
    try fixture.phone.acknowledge(receipt.id, pairingID: "device")
    fixture.receipts = [receipt]
    fixture.queueEmpty = true
    let result = await fixture.worker.run(commandID: "start")
    XCTAssertEqual(result, .applied)
    XCTAssertEqual(fixture.receipts.count, 1)
  }

}

private final class DeliveryFixture: @unchecked Sendable {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  var clock = 1_793_836_800_000.0
  var queueEmpty = false
  var commandFetchRequested = false
  var failReceiptUploads = false
  var failAllRequests = false
  var snapshots: [Data] = []
  var shielded = false
  var receipts: [FocusReceipt] = []
  var command = FocusCommand(
    id: "start", sequence: 1, action: .start, modeID: "work",
    durationMinutes: 15, sessionID: "session", issuedAt: 1_793_836_800_000,
    expiresAt: 1_793_836_920_000)
  lazy var phone = AgentFocusPhone<String>(
    directory: directory,
    emergency: .init(read: { nil }, write: { _ in }), now: { self.clock },
    apply: { _, _ in self.shielded = true }, release: { self.shielded = false })
  lazy var worker: AgentFocusDelivery<String> = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DeliveryURLProtocol.self]
    return AgentFocusDelivery(
      phone: phone,
      pairing: .init(
        relay: URL(string: "https://relay.example")!,
        deviceId: "device", deviceToken: "private-device-token"), configuration: configuration)
  }()
  init() throws {
    try phone.approve(
      policy: .init(
        modeID: "work", maximumMinutes: 45,
        startMinute: 0, endMinute: 1440, timeZone: "Asia/Taipei"),
      selection: "opaque-on-phone", pairingID: "device")
    DeliveryURLProtocol.handle = { request in try self.respond(request) }
  }
  func cleanup() {
    DeliveryURLProtocol.handle = nil
    try? FileManager.default.removeItem(at: directory)
  }
  private func requestBody(_ request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var buffer = [UInt8](repeating: 0, count: 4096)
    var data = Data()
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      if count <= 0 { break }
      data.append(contentsOf: buffer.prefix(count))
    }
    return data
  }

  func respond(_ request: URLRequest) throws -> (Int, Data) {
    if failAllRequests { return (503, Data()) }
    guard request.value(forHTTPHeaderField: "Authorization") == "Bearer private-device-token" else {
      return (401, Data())
    }
    switch request.url!.path {
    case "/v1/device/commands":
      commandFetchRequested = true
      struct Commands: Encodable { let commands: [FocusCommand] }
      return (200, try JSONEncoder().encode(Commands(commands: queueEmpty ? [] : [command])))
    case "/v1/device/receipts":
      if failReceiptUploads { return (503, Data()) }
      let data = requestBody(request)
      receipts.append(try JSONDecoder().decode(FocusReceipt.self, from: data))
      return (200, Data("{}".utf8))
    case "/v1/device/commands/start":
      struct Result: Encodable {
        let command: FocusCommand
        let status: String
      }
      return (
        200,
        try JSONEncoder().encode(
          Result(command: command, status: receipts.last?.status ?? "pending"))
      )
    case "/v1/device/snapshot":
      snapshots.append(requestBody(request))
      return (200, Data("{}".utf8))
    default: return (404, Data())
    }
  }
}

private final class DeliveryURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handle: ((URLRequest) throws -> (Int, Data))?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      let (status, data) = try Self.handle!(request)
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status,
        httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}
