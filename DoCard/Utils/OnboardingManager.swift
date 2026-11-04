import OSLog
import SwiftUI

private let onboardingLog = Logger(subsystem: "online.do.card.app", category: "OnboardingManager")

class OnboardingManager: ObservableObject {
  static let shared = OnboardingManager()

  private static let defaults: UserDefaults = {
    guard let defaults = UserDefaults(suiteName: "group.DO.version3") else {
      onboardingLog.error("Failed to access App Group UserDefaults — falling back to standard")
      return UserDefaults.standard
    }
    return defaults
  }()

  @AppStorage("onboardingCompleted", store: UserDefaults(suiteName: "group.DO.version3"))
  var isOnboardingCompleted: Bool = false

  @AppStorage("tutorialCompleted", store: UserDefaults(suiteName: "group.DO.version3"))
  var isTutorialCompleted: Bool = false

  @Published var showOnboarding: Bool = false
  @Published var tutorialStep: Int = 0

  // MARK: - DO Card Pairing

  #if DEBUG
    static let maxPairedCards = 100
  #else
    static let maxPairedCards = 5
  #endif

  var pairedDOCardTagIds: [String] {
    get { Self.defaults.stringArray(forKey: "pairedDOCardTagIds") ?? [] }
    set { Self.defaults.set(newValue, forKey: "pairedDOCardTagIds") }
  }

  /// The user-given name of their DO Card, stored locally after a successful pair or rename.
  /// Lives on the card itself (NDEF payload); this is a cached copy for display.
  var doCardName: String? {
    get { Self.defaults.string(forKey: "doCardName") }
    set {
      if let name = newValue {
        Self.defaults.set(name, forKey: "doCardName")
      } else {
        Self.defaults.removeObject(forKey: "doCardName")
      }
      objectWillChange.send()
    }
  }

  var pairedDOCardCount: Int {
    pairedDOCardTagIds.count
  }

  var isDOCardPaired: Bool {
    !pairedDOCardTagIds.isEmpty
  }

  var canPairMoreCards: Bool {
    return pairedDOCardTagIds.count < Self.maxPairedCards
  }

  /// Add a new DO Card. Returns false if already paired or at max capacity.
  @discardableResult
  func pairDOCard(tagId: String) -> Bool {
    var ids = pairedDOCardTagIds
    // Don't add duplicate
    if ids.contains(tagId) { return false }
    if ids.count >= Self.maxPairedCards { return false }
    ids.append(tagId)
    pairedDOCardTagIds = ids
    objectWillChange.send()
    return true
  }

  func unpairAllDOCards() {
    pairedDOCardTagIds = []
    objectWillChange.send()
  }

  func isTagIdPaired(_ tagId: String) -> Bool {
    pairedDOCardTagIds.contains(tagId)
  }

  var shouldShowOnboarding: Bool {
    return !isOnboardingCompleted
  }

  var shouldShowTutorial: Bool {
    return isOnboardingCompleted && !isTutorialCompleted
  }

  func completeOnboarding() {
    isOnboardingCompleted = true
    showOnboarding = false
  }

  func resetOnboarding() {
    isOnboardingCompleted = false
    isTutorialCompleted = false
    showOnboarding = true
    tutorialStep = 0
  }

  func startTutorial() {
    tutorialStep = 1
  }

  func advanceTutorial() {
    if tutorialStep >= 5 {
      completeTutorial()
    } else {
      tutorialStep += 1
    }
  }

  func completeTutorial() {
    isTutorialCompleted = true
    tutorialStep = 0
  }
}
