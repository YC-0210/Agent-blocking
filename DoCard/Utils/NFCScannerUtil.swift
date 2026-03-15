import CoreNFC
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "app.docard", category: "NFC")

struct NFCResult: Equatable {
  var id: String
  var payload: String?
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

  deinit {
    nfcSession?.invalidate()
    nfcSession = nil
  }

  func scan(profileName: String, isUnlocking: Bool = false) {
    guard NFCReaderSession.readingAvailable else {
      self.onError?(String(localized: "NFC scanning not available on this device"))
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

  func writeExternalRecord(uuid: String) {
    guard NFCReaderSession.readingAvailable else {
      self.onError?(String(localized: "NFC writing not available on this device"))
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
    ndefSession.alertMessage = String(localized: "Hold your iPhone near an NFC tag to write DO Card data.")
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

  /// Extract the DO Card payload (UUID) from an NDEF message
  /// Returns the UUID string if a valid DO Card External Type record is found
  private func extractDOCardPayload(_ message: NFCNDEFMessage) -> String? {
    let doCardRecords = message.records.filter { NFCScannerUtil.isDOCardRecord($0) }

    guard doCardRecords.count == 1,
      let record = doCardRecords.first,
      let payloadString = String(data: record.payload, encoding: .utf8),
      !payloadString.isEmpty
    else {
      return nil
    }

    return payloadString
  }

  private func readMiFareTag(_ tag: NFCMiFareTag, session: NFCTagReaderSession) {
    tag.readNDEF { (message: NFCNDEFMessage?, error: Error?) in
      if error != nil || message == nil {
        let tagId = tag.identifier.hexEncodedString()

        if let error = error {
          // SECURITY (V-08): Never log tag IDs in release builds
          logger.debug("NDEF read failed (non-critical): \(error.localizedDescription, privacy: .public). Falling back to tag identifier.")
        }

        // Still use the identifier - works for all tag types
        self.handleTagData(
          id: tagId,
          payload: nil,
          session: session
        )
        return
      }

      let payload = self.extractDOCardPayload(message!)
      self.handleTagData(
        id: tag.identifier.hexEncodedString(),
        payload: payload,
        session: session
      )
    }
  }

  private func readISO15693Tag(_ tag: NFCISO15693Tag, session: NFCTagReaderSession) {
    tag.readNDEF { (message: NFCNDEFMessage?, error: Error?) in
      if error != nil || message == nil {
        let tagId = tag.identifier.hexEncodedString()

        if let error = error {
          // SECURITY (V-08): Never log tag IDs in release builds
          logger.debug("ISO15693 NDEF read failed (non-critical): \(error.localizedDescription, privacy: .public). Falling back to tag identifier.")
        }

        self.handleTagData(
          id: tagId,
          payload: nil,
          session: session
        )
        return
      }

      let payload = self.extractDOCardPayload(message!)
      self.handleTagData(
        id: tag.identifier.hexEncodedString(),
        payload: payload,
        session: session
      )
    }
  }

  private func handleTagData(id: String, payload: String?, session: NFCTagReaderSession) {
    let result = NFCResult(id: id, payload: payload, DateScanned: Date())

    // Validate at the NFC session level so the system dialog
    // shows ✗ (cross) for invalid/unmatched tags instead of ✓ (checkmark)
    let isDOCard = payload != nil
    let tagIdMatches = expectedTagIds == nil || expectedTagIds!.isEmpty || expectedTagIds!.contains(id)

    DispatchQueue.main.async { [weak self] in
      if !isDOCard {
        // Case 1: Random NFC tag (no DO Card External Type record) → ✗ cross
        session.invalidate(errorMessage: String(localized: "請使用 DO Card"))
        self?.onError?(String(localized: "This is not a valid DO Card. Please use your DO Card to unlock."))
      } else if !tagIdMatches {
        // Case 2: Valid DO Card but wrong tag ID → ✗ cross
        session.invalidate(errorMessage: String(localized: "此DO Card 尚未配對"))
        self?.onError?(String(localized: "This DO Card is not paired. Please go to Settings to pair your card."))
      } else {
        // Case 3: Matched DO Card → ✓ checkmark
        self?.onTagScanned?(result)
        session.invalidate()
      }
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
