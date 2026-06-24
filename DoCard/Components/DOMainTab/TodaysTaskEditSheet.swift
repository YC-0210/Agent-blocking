import SwiftUI

/// What the edit sheet is editing: a brand-new goal, or an existing one.
enum TodaysTaskEditTarget: Identifiable {
  case new
  case existing(DailyTask)

  var id: String {
    switch self {
    case .new: return "new"
    case .existing(let task): return task.id.uuidString
    }
  }
}

/// Editor for a Daily Task — presented as a half-height `.sheet` (never
/// `.fullScreenCover`, which zeroes the top safe area in this app). Name and
/// detail are length-capped; 完成 saves, 取消 / swipe-down discards, 刪除 (and
/// saving a blank name) removes the goal.
struct TodaysTaskEditSheet: View {
  @Environment(\.dismiss) private var dismiss

  let store: TodaysTasksStore
  let target: TodaysTaskEditTarget

  @State private var name: String
  @State private var detail: String

  private let nameLimit = 40
  private let detailLimit = 200

  init(store: TodaysTasksStore, target: TodaysTaskEditTarget) {
    self.store = store
    self.target = target
    switch target {
    case .new:
      _name = State(initialValue: "")
      _detail = State(initialValue: "")
    case .existing(let goal):
      _name = State(initialValue: goal.name)
      _detail = State(initialValue: goal.detail)
    }
  }

  private var existingGoal: DailyTask? {
    if case .existing(let goal) = target { return goal }
    return nil
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField(String(localized: "名稱"), text: $name)
            .onChange(of: name) { _, value in
              if value.count > nameLimit { name = String(value.prefix(nameLimit)) }
            }
        }
        Section {
          TextField(String(localized: "細節"), text: $detail, axis: .vertical)
            .lineLimit(3...6)
            .onChange(of: detail) { _, value in
              if value.count > detailLimit { detail = String(value.prefix(detailLimit)) }
            }
        } header: {
          Text(String(localized: "細節"))
        }
        if existingGoal != nil {
          Section {
            Button(role: .destructive) {
              if let goal = existingGoal { store.delete(goal) }
              dismiss()
            } label: {
              Text(String(localized: "刪除"))
            }
          }
        }
      }
      .navigationTitle(
        existingGoal == nil ? String(localized: "新增目標") : String(localized: "編輯目標")
      )
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(String(localized: "取消")) { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button(String(localized: "完成")) { save() }.fontWeight(.semibold)
        }
      }
    }
    .presentationDetents([.medium])
  }

  private func save() {
    if let goal = existingGoal {
      store.update(goal, name: name, detail: detail)  // blank name => delete
    } else {
      store.addGoal(name: name, detail: detail)  // blank name => no-op
    }
    dismiss()
  }
}
