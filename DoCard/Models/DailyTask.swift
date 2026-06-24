import Foundation

/// One entry in Today's Tasks (今日目標): a short `name` shown on the
/// centerpiece, an optional longer `detail`, and a `done` state.
/// See CONTEXT.md → "Daily Task".
struct DailyTask: Codable, Identifiable, Equatable {
  let id: UUID
  var name: String
  var detail: String
  var done: Bool

  init(id: UUID = UUID(), name: String, detail: String = "", done: Bool = false) {
    self.id = id
    self.name = name
    self.detail = detail
    self.done = done
  }
}
