import SwiftUI

class OnboardingManager: ObservableObject {
  static let shared = OnboardingManager()

  private static let defaults = UserDefaults(suiteName: "group.DO.version3")!

  @AppStorage("onboardingCompleted", store: UserDefaults(suiteName: "group.DO.version3"))
  var isOnboardingCompleted: Bool = false

  @AppStorage("tutorialCompleted", store: UserDefaults(suiteName: "group.DO.version3"))
  var isTutorialCompleted: Bool = false

  @Published var showOnboarding: Bool = false
  @Published var tutorialStep: Int = 0

  // MARK: - DO Card Pairing (supports up to 5 cards)

  static let maxPairedCards = 5

  var pairedDOCardTagIds: [String] {
    get { Self.defaults.stringArray(forKey: "pairedDOCardTagIds") ?? [] }
    set { Self.defaults.set(newValue, forKey: "pairedDOCardTagIds") }
  }

  var pairedDOCardCount: Int {
    pairedDOCardTagIds.count
  }

  var isDOCardPaired: Bool {
    !pairedDOCardTagIds.isEmpty
  }

  var canPairMoreCards: Bool {
    pairedDOCardTagIds.count < Self.maxPairedCards
  }

  /// Add a new DO Card. Returns false if already paired or at max capacity.
  @discardableResult
  func pairDOCard(tagId: String) -> Bool {
    var ids = pairedDOCardTagIds
    // Don't add duplicate
    if ids.contains(tagId) { return false }
    // Don't exceed max
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
