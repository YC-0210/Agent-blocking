import CoreNFC
import SwiftUI

class PhysicalReader {
  private let nfcScanner: NFCScannerUtil = NFCScannerUtil()

  func readNFCTag(
    onSuccess: @escaping (String) -> Void,
  ) {
    nfcScanner.onTagScanned = { result in
      let tagId = result.payload ?? result.id
      onSuccess(tagId)
    }

    nfcScanner.scan(profileName: "")
  }
}
