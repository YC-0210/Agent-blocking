import Foundation
import XCTest

@testable import DoCard

private final class UpdateHTTPStub: URLProtocol {
  private static let lock = NSLock()
  private static var handler: ((UpdateHTTPStub) -> Void)?

  static func respond(using handler: @escaping (UpdateHTTPStub) -> Void) {
    lock.lock()
    defer { lock.unlock() }
    Self.handler = handler
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.lock.lock()
    let handler = Self.handler
    Self.lock.unlock()
    handler?(self)
  }
  override func stopLoading() {}

  func finish(status: Int = 200, json: String, url: URL? = nil) {
    let response = HTTPURLResponse(
      url: url ?? request.url!, statusCode: status,
      httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(json.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  func fail(_ error: URLError) { client?.urlProtocol(self, didFailWithError: error) }
}

@MainActor
final class AppUpdateNetworkTests: XCTestCase {
  private let requiredJSON = #"{"minimumVersion":"2.1.1","updateMessage":"Update now"}"#

  private func manager(
    endpoint: URL = URL(string: "https://config.example.invalid/app-config.json")!
  )
    -> AppUpdateManager
  {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [UpdateHTTPStub.self]
    return AppUpdateManager(
      installedVersion: "2.1.0", endpoint: endpoint,
      session: URLSession(configuration: config))
  }

  func testRemoteMinimumRequiresUpdateAndPreservesMessage() async {
    UpdateHTTPStub.respond { $0.finish(json: self.requiredJSON) }
    let manager = manager()
    await manager.checkForUpdate()
    XCTAssertEqual(manager.requiredUpdate?.minimumVersion, "2.1.1")
    XCTAssertEqual(manager.requiredUpdate?.updateMessage, "Update now")
    XCTAssertFalse(manager.isChecking)
  }

  func testLoweringRemoteMinimumClearsRequirement() async {
    let manager = manager()
    UpdateHTTPStub.respond { $0.finish(json: self.requiredJSON) }
    await manager.checkForUpdate()
    XCTAssertNotNil(manager.requiredUpdate)
    UpdateHTTPStub.respond { $0.finish(json: #"{"minimumVersion":"2.1.0"}"#) }
    await manager.checkForUpdate()
    XCTAssertNil(manager.requiredUpdate)
  }

  func testRemoteKillSwitchClearsRequirement() async {
    let manager = manager()
    UpdateHTTPStub.respond { $0.finish(json: self.requiredJSON) }
    await manager.checkForUpdate()
    XCTAssertNotNil(manager.requiredUpdate)
    UpdateHTTPStub.respond { $0.finish(json: #"{"minimumVersion":"99","enabled":false}"#) }
    await manager.checkForUpdate()
    XCTAssertNil(manager.requiredUpdate)
  }

  func testOfflineTimeoutAndCancellationClearPreviousRequirement() async {
    let manager = manager()
    for code in [URLError.notConnectedToInternet, .timedOut, .cancelled] {
      UpdateHTTPStub.respond { $0.finish(json: self.requiredJSON) }
      await manager.checkForUpdate()
      XCTAssertNotNil(manager.requiredUpdate)
      UpdateHTTPStub.respond { $0.fail(URLError(code)) }
      await manager.checkForUpdate()
      XCTAssertNil(manager.requiredUpdate)
      XCTAssertFalse(manager.isChecking)
    }
  }

  func testHTTPFailuresCannotEnforceOrRetainAnUpdate() async {
    let manager = manager()
    for status in [204, 304, 403, 404, 500] {
      UpdateHTTPStub.respond { $0.finish(json: self.requiredJSON) }
      await manager.checkForUpdate()
      XCTAssertNotNil(manager.requiredUpdate)
      UpdateHTTPStub.respond { $0.finish(status: status, json: self.requiredJSON) }
      await manager.checkForUpdate()
      XCTAssertNil(manager.requiredUpdate)
    }
  }

  func testMalformedAndOversizedResponsesFailOpen() async {
    let manager = manager()
    for json in [
      "<html>Unavailable</html>", "{}", "[]", #"{"minimumVersion":123}"#,
      #"{"minimumVersion":"2..1"}"#, #"{"minimumVersion":"99","enabled":"true"}"#,
      String(repeating: " ", count: 16_385) + requiredJSON,
    ] {
      UpdateHTTPStub.respond { $0.finish(json: self.requiredJSON) }
      await manager.checkForUpdate()
      XCTAssertNotNil(manager.requiredUpdate)
      UpdateHTTPStub.respond { $0.finish(json: json) }
      await manager.checkForUpdate()
      XCTAssertNil(manager.requiredUpdate)
    }
  }

  func testRefreshBypassesCachesAndUsesPublicJSONRequest() async {
    let received = expectation(description: "Fresh config request")
    UpdateHTTPStub.respond {
      XCTAssertEqual($0.request.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
      XCTAssertEqual($0.request.value(forHTTPHeaderField: "Accept"), "application/json")
      XCTAssertNil($0.request.value(forHTTPHeaderField: "Authorization"))
      XCTAssertEqual($0.request.timeoutInterval, 8)
      received.fulfill()
      $0.finish(json: self.requiredJSON)
    }
    await manager().checkForUpdate()
    await fulfillment(of: [received], timeout: 2)
  }

  func testInsecureEndpointOrResponseFailsOpen() async {
    UpdateHTTPStub.respond { _ in XCTFail("HTTP endpoint must not be requested") }
    let insecure = manager(endpoint: URL(string: "http://example.invalid/app-config.json")!)
    await insecure.checkForUpdate()
    XCTAssertNil(insecure.requiredUpdate)
    UpdateHTTPStub.respond {
      $0.finish(
        json: self.requiredJSON, url: URL(string: "http://example.invalid/app-config.json")!)
    }
    let manager = manager()
    await manager.checkForUpdate()
    XCTAssertNil(manager.requiredUpdate)
  }

  func testConcurrentChecksShareTheInFlightRequest() async {
    let started = expectation(description: "Request started")
    var finish: (() -> Void)?
    UpdateHTTPStub.respond { stub in
      Task { @MainActor in
        finish = { stub.finish(json: self.requiredJSON) }
        started.fulfill()
      }
    }
    let manager = manager()
    let first = Task { await manager.checkForUpdate() }
    await fulfillment(of: [started], timeout: 2)
    XCTAssertTrue(manager.isChecking)
    await manager.checkForUpdate()
    XCTAssertTrue(manager.isChecking)
    XCTAssertNil(manager.requiredUpdate)
    finish?()
    await first.value
    XCTAssertNotNil(manager.requiredUpdate)
    XCTAssertFalse(manager.isChecking)
  }
}
