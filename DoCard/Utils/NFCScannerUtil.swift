import CoreNFC
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "app.docard", category: "NFC")

struct NFCResult: Equatable {
  var id: String
  var payload: String?
  var cardName: String?
  var DateScanned: Date
}

class NFCScannerUtil: NSObject {
  // Callback closures for handling results and errors
  var onTagScanned: ((NFCResult) -> Void)?
  var onError: ((String) -> Void)?
  var onCancel: (() -> Void)?

  // SECURITY (V-10): Serial queue protects expectedTagIds from concurrent
  // read/write across the main thread and the NFC session callback thread.
  private let tagIdQueue = DispatchQueue(label: "app.docard.nfc.tagIdQueue")
  private var _expectedTagIds: [String]?

  // Optional expected tag IDs for paired card validation at NFC session level
  // If set, only tags with an ID in this array will be accepted
  var expectedTagIds: [String]? {
    get { tagIdQueue.sync { _expectedTagIds } }
    set { tagIdQueue.sync { _expectedTagIds = newValue } }
  }

  // NDEF External Type domain and type for DO Card
  static let doCardNDEFDomain = "docard.app"
  static let doCardNDEFType = "card"
  static let doCardNDEFFullType = "\(doCardNDEFDomain):\(doCardNDEFType)"

  private var nfcSession: NFCReaderSession?
  private var uuidToWrite: String?

  // When non-nil, the read path will also write a new JSON payload with this name
  var pendingCardName: String?

  // When true (rename flow), the write is only allowed if the tag is already in expectedTagIds.
  // When false (pairing flow), any valid DO Card is accepted.
  private var pendingRequirePaired: Bool = false

  deinit {
    nfcSession?.invalidate()
    nfcSession = nil
  }

  func scan(profileName: String, isUnlocking: Bool = false) {
    guard NFCReaderSession.readingAvailable else {
      self.onError?(String(localized: "此裝置不支援 DO Card 感應"))
      return
    }

    // Invalidate any existing session before creating a new one.
    // iOS only allows one NFC session at a time — without this,
    // the new session's dialog can be silently suppressed.
    nfcSession?.invalidate()
    nfcSession = nil

    nfcSession = NFCTagReaderSession(
      pollingOption: [.iso14443, .iso15693],
      delegate: self,
      queue: nil
    )
    nfcSession?.alertMessage = isUnlocking
      ? String(localized: "Hold your DO Card near your phone to unlock")
      : String(localized: "Hold your DO Card near your phone to lock")
    nfcSession?.begin()
  }

  /// Read the card, verify it is a DO Card, then write a new JSON payload with the given name.
  /// Calls `onTagScanned` on success (result.cardName == name), `onError` on failure.
  ///
  /// - Parameters:
  ///   - name: The card name to write into the NDEF payload.
  ///   - requirePaired: Pass `false` for the initial pairing flow (any valid DO Card accepted).
  ///                    Pass `true` for the rename flow (card must already be in `expectedTagIds`).
  func scanAndWrite(name: String, requirePaired: Bool) {
    pendingCardName = name
    pendingRequirePaired = requirePaired
    scan(profileName: "DO Card")
  }

  func writeExternalRecord(uuid: String) {
    guard NFCReaderSession.readingAvailable else {
      self.onError?(String(localized: "此裝置不支援 DO Card 寫入"))
      return
    }

    guard !uuid.isEmpty else {
      self.onError?(String(localized: "Invalid UUID"))
      return
    }

    uuidToWrite = uuid

    // Using NFCNDEFReaderSession for writing
    let ndefSession = NFCNDEFReaderSession(
      delegate: self, queue: nil, invalidateAfterFirstRead: false)
    ndefSession.alertMessage = String(localized: "將 iPhone 靠近 DO Card 以寫入資料")
    ndefSession.begin()
  }
}

// MARK: - NFCTagReaderSessionDelegate
extension NFCScannerUtil: NFCTagReaderSessionDelegate {
  func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
    // Session started
  }

  func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
    DispatchQueue.main.async { [weak self] in
      self?.nfcSession = nil

      // Filter out normal session-end errors (user cancel, successful read, etc.)
      // Only forward actual failures to the error handler
      if let readerError = error as? NFCReaderError {
        switch readerError.code {
        case .readerSessionInvalidationErrorUserCanceled:
          self?.onCancel?()
          return
        case .readerSessionInvalidationErrorFirstNDEFTagRead:
          return
        default:
          break
        }
      }

      self?.onError?(error.localizedDescription)
    }
  }

  func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
    guard let tag = tags.first else { return }

    session.connect(to: tag) { error in
      if let error = error {
        session.invalidate(errorMessage: String(format: String(localized: "Connection error: %@"), error.localizedDescription))
        return
      }

      switch tag {
      case .iso15693(let tag):
        self.readISO15693Tag(tag, session: session)
      case .miFare(let tag):
        self.readMiFareTag(tag, session: session)
      default:
        session.invalidate(errorMessage: String(localized: "Unsupported tag type"))
      }
    }
  }

  // MARK: - DO Card NDEF Validation

  /// MIME type format used by NFC Tools app: "docard.app/card"
  static let doCardMIMEType = "\(doCardNDEFDomain)/\(doCardNDEFType)"

  /// Check if an NDEF record is a DO Card record
  /// Accepts both External Type (docard.app:card) and MIME type (docard.app/card)
  static func isDOCardRecord(_ record: NFCNDEFPayload) -> Bool {
    guard let typeString = String(data: record.type, encoding: .utf8) else { return false }

    switch record.typeNameFormat {
    case .nfcExternal:
      // External Type "docard.app:card"
      return typeString == doCardNDEFFullType
    case .media:
      // MIME type "docard.app/card" (e.g. written by NFC Tools)
      return typeString == doCardMIMEType
    default:
      return false
    }
  }

  /// Extract the DO Card payload from an NDEF message.
  /// Returns `(uuid, cardName?)` — handles both old plain-UUID format and new JSON format.
  /// - Old format: plain UUID string → `(uuid: payloadString, cardName: nil)`
  /// - New format: `{"uuid":"...","name":"..."}` → `(uuid: parsedUUID, cardName: parsedName)`
  private func extractDOCardPayload(_ message: NFCNDEFMessage) -> (uuid: String, cardName: String?)? {
    let doCardRecords = message.records.filter { NFCScannerUtil.isDOCardRecord($0) }

    guard doCardRecords.count == 1,
      let record = doCardRecords.first,
      let payloadString = String(data: record.payload, encoding: .utf8),
      !payloadString.isEmpty
    else {
      return nil
    }

    // Try JSON format first (new format)
    if let data = payloadString.data(using: .utf8),
      let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: String],
      let uuid = jsonObj["uuid"],
      !uuid.isEmpty
    {
      return (uuid: uuid, cardName: jsonObj["name"])
    }

    // Fall back to plain UUID format (old format)
    return (uuid: payloadString, cardName: nil)
  }

  private func readMiFareTag(_ tag: NFCMiFareTag, session: NFCTagReaderSession) {
    tag.readNDEF { (message: NFCNDEFMessage?, error: Error?) in
      let tagId = tag.identifier.hexEncodedString()

      if error != nil || message == nil {
        if let error = error {
          // SECURITY (V-08): Never log tag IDs in release builds
          logger.debug("NDEF read failed (non-critical): \(error.localizedDescription, privacy: .public). Falling back to tag identifier.")
        }

        if self.pendingCardName != nil {
          // Cannot write without a readable NDEF — fail clearly
          DispatchQueue.main.async { [weak self] in
            self?.pendingCardName = nil
            session.invalidate(errorMessage: String(localized: "無法讀取 DO Card，請重試"))
            self?.onError?(String(localized: "無法讀取卡片資料，請重試"))
          }
          return
        }

        self.handleTagData(id: tagId, uuid: nil, cardName: nil, session: session)
        return
      }

      let extracted = self.extractDOCardPayload(message!)

      if let pendingName = self.pendingCardName {
        self.handleWritePath(
          tagId: tagId, extracted: extracted, pendingName: pendingName,
          requirePaired: self.pendingRequirePaired,
          tag: tag, session: session)
      } else {
        self.handleTagData(
          id: tagId,
          uuid: extracted?.uuid,
          cardName: extracted?.cardName,
          session: session
        )
      }
    }
  }

  private func readISO15693Tag(_ tag: NFCISO15693Tag, session: NFCTagReaderSession) {
    tag.readNDEF { (message: NFCNDEFMessage?, error: Error?) in
      let tagId = tag.identifier.hexEncodedString()

      if error != nil || message == nil {
        if let error = error {
          // SECURITY (V-08): Never log tag IDs in release builds
          logger.debug("ISO15693 NDEF read failed (non-critical): \(error.localizedDescription, privacy: .public). Falling back to tag identifier.")
        }

        if self.pendingCardName != nil {
          DispatchQueue.main.async { [weak self] in
            self?.pendingCardName = nil
            session.invalidate(errorMessage: String(localized: "無法讀取 DO Card，請重試"))
            self?.onError?(String(localized: "無法讀取卡片資料，請重試"))
          }
          return
        }

        self.handleTagData(id: tagId, uuid: nil, cardName: nil, session: session)
        return
      }

      let extracted = self.extractDOCardPayload(message!)

      if let pendingName = self.pendingCardName {
        self.handleWritePath(
          tagId: tagId, extracted: extracted, pendingName: pendingName,
          requirePaired: self.pendingRequirePaired,
          tag: tag, session: session)
      } else {
        self.handleTagData(
          id: tagId,
          uuid: extracted?.uuid,
          cardName: extracted?.cardName,
          session: session
        )
      }
    }
  }

  // MARK: - Write Path (single-session read-then-write)

  /// Called after a successful NDEF read when `pendingCardName` is set.
  /// Validates the tag is a valid DO Card, then writes the new JSON payload in the same NFC session.
  ///
  /// - Parameter requirePaired: When `true` (rename flow), also verifies the tag is in `expectedTagIds`.
  ///                            When `false` (pairing flow), skips that check — the card is new and not
  ///                            yet in the paired list.
  private func handleWritePath(
    tagId: String,
    extracted: (uuid: String, cardName: String?)?,
    pendingName: String,
    requirePaired: Bool,
    tag: NFCNDEFTag,
    session: NFCTagReaderSession
  ) {
    guard let extracted = extracted else {
      DispatchQueue.main.async { [weak self] in
        self?.pendingCardName = nil
        session.invalidate(errorMessage: String(localized: "請使用 DO Card"))
        self?.onError?(String(localized: "這不是有效的 DO Card，請使用你的 DO Card"))
      }
      return
    }

    // Rename flow only: verify this card is already in the paired list
    if requirePaired {
      let tagIdMatches =
        expectedTagIds == nil || expectedTagIds!.isEmpty || expectedTagIds!.contains(tagId)
      guard tagIdMatches else {
        DispatchQueue.main.async { [weak self] in
          self?.pendingCardName = nil
          session.invalidate(errorMessage: String(localized: "此DO Card 尚未配對"))
          self?.onError?(String(localized: "此 DO Card 尚未配對，請先完成配對再重新命名"))
        }
        return
      }
    }

    writeNDEFRecord(uuid: extracted.uuid, name: pendingName, to: tag, session: session) {
      self.handleTagData(id: tagId, uuid: extracted.uuid, cardName: pendingName, session: session)
    }
  }

  /// Write a new DO Card NDEF record with the given UUID and card name as JSON payload.
  /// Calls `onSuccess` (on the NFC callback queue) if the write succeeds.
  private func writeNDEFRecord(
    uuid: String,
    name: String,
    to tag: NFCNDEFTag,
    session: NFCTagReaderSession,
    onSuccess: @escaping () -> Void
  ) {
    let jsonDict: [String: String] = ["uuid": uuid, "name": name]
    guard let jsonData = try? JSONSerialization.data(withJSONObject: jsonDict),
      let typeData = NFCScannerUtil.doCardNDEFFullType.data(using: .utf8)
    else {
      session.invalidate(errorMessage: String(localized: "寫入資料無效，請重試"))
      return
    }

    let record = NFCNDEFPayload(
      format: .nfcExternal,
      type: typeData,
      identifier: Data(),
      payload: jsonData
    )
    let message = NFCNDEFMessage(records: [record])

    tag.writeNDEF(message) { error in
      if let error = error {
        logger.error("NFC write error: \(error.localizedDescription, privacy: .public)")
        session.invalidate(
          errorMessage: String(format: String(localized: "寫入失敗：%@"), error.localizedDescription))
      } else {
        session.alertMessage = String(localized: "✓ 卡片已命名")
        onSuccess()
      }
    }
  }

  private func handleTagData(id: String, uuid: String?, cardName: String?, session: NFCTagReaderSession) {
    pendingCardName = nil
    let result = NFCResult(id: id, payload: uuid, cardName: cardName, DateScanned: Date())
    // Capture paired IDs at read time, as the hardware path did before dispatching.
    let expectedIds = expectedTagIds
    DispatchQueue.main.async { [weak self] in
      self?.deliverReadResult(result, expectedIds: expectedIds) { message in
        if let message { session.invalidate(errorMessage: message) } else { session.invalidate() }
      }
    }
  }

  /// Common validation/delivery for a completed read; hardware supplies the dialog callback.
  func deliverReadResult(
    _ result: NFCResult, expectedIds: [String]?, invalidate: (String?) -> Void
  ) {
    if result.payload == nil {
      invalidate(String(localized: "請使用 DO Card"))
      onError?(String(localized: "This is not a valid DO Card. Please use your DO Card to unlock."))
    } else if let expectedIds, !expectedIds.isEmpty, !expectedIds.contains(result.id) {
      invalidate(String(localized: "此DO Card 尚未配對"))
      onError?(
        String(localized: "This DO Card is not paired. Please go to Settings to pair your card."))
    } else {
      invalidate(nil)
      onTagScanned?(result)
    }
  }

}

// MARK: - NDEF Writing Support (External Type)
extension NFCScannerUtil: NFCNDEFReaderSessionDelegate {
  func readerSession(
    _ session: NFCNDEFReaderSession,
    didDetectNDEFs messages: [NFCNDEFMessage]
  ) {
    // Not used for writing
  }

  func readerSession(
    _ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]
  ) {
    guard let tag = tags.first else {
      session.invalidate(errorMessage: String(localized: "No tag found"))
      return
    }

    session.connect(to: tag) { error in
      if let error = error {
        session.invalidate(
          errorMessage:
            String(format: String(localized: "Connection error: %@"), error.localizedDescription))
        return
      }

      tag.queryNDEFStatus { status, capacity, error in
        guard error == nil else {
          session.invalidate(errorMessage: String(localized: "Failed to query tag"))
          return
        }

        switch status {
        case .notSupported:
          session.invalidate(
            errorMessage: String(localized: "Tag is not NDEF compliant"))
        case .readOnly:
          session.invalidate(errorMessage: String(localized: "Tag is read-only"))
        case .readWrite:
          self.handleReadWrite(session, tag: tag)
        @unknown default:
          session.invalidate(errorMessage: String(localized: "Unknown tag status"))
        }
      }
    }
  }

  func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
    // Session became active
  }

  func readerSession(
    _ session: NFCNDEFReaderSession, didInvalidateWithError error: Error
  ) {
    DispatchQueue.main.async { [weak self] in
      if let readerError = error as? NFCReaderError {
        switch readerError.code {
        case .readerSessionInvalidationErrorFirstNDEFTagRead,
          .readerSessionInvalidationErrorUserCanceled:
          // User canceled or first tag read
          break
        default:
          self?.onError?(readerError.localizedDescription)
        }
      }
    }
  }

  private func handleReadWrite(
    _ session: NFCNDEFReaderSession, tag: NFCNDEFTag
  ) {
    guard let uuid = self.uuidToWrite,
      let typeData = NFCScannerUtil.doCardNDEFFullType.data(using: .utf8),
      let payloadData = uuid.data(using: .utf8)
    else {
      session.invalidate(errorMessage: String(localized: "Invalid DO Card data"))
      return
    }

    let record = NFCNDEFPayload(
      format: .nfcExternal,
      type: typeData,
      identifier: Data(),
      payload: payloadData
    )

    let message = NFCNDEFMessage(records: [record])
    tag.writeNDEF(message) { error in
      if let error = error {
        session.invalidate(
          errorMessage: String(format: String(localized: "Write failed: %@"), error.localizedDescription))
      } else {
        session.alertMessage = String(localized: "Successfully wrote DO Card data")
        session.invalidate()
      }
    }
  }
}

extension Data {
  func hexEncodedString() -> String {
    return map { String(format: "%02hhX", $0) }.joined()
  }
}
