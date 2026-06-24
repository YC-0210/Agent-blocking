import FamilyControls
import OSLog
import SwiftData
import SwiftUI

private let bplLog = Logger(subsystem: "online.do.card.app", category: "BlockedProfileList")

struct BlockedProfileListView: View {
  @Environment(\.modelContext) private var context
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var strategyManager: StrategyManager

  @Query(sort: [
    SortDescriptor(\BlockedProfiles.order, order: .forward),
    SortDescriptor(\BlockedProfiles.createdAt, order: .reverse),
  ]) private var profiles: [BlockedProfiles]

  @State private var showingCreateProfile = false
  @State private var showingDataExport = false

  @State private var profileToEdit: BlockedProfiles?
  @State private var showErrorAlert = false
  @State private var editMode: EditMode = .inactive

  var body: some View {
    NavigationStack {
      Group {
        if profiles.isEmpty {
          EmptyView(
            iconName: "person.crop.circle.badge.plus",
            headingText:
              String(localized: "透過自訂模式來分組和切換不同的專注場景")
          )
        } else {
          List {
            ForEach(profiles) { profile in
              ProfileRow(profile: profile)
                .contentShape(Rectangle())
                .onTapGesture {
                  if editMode == .inactive {
                    profileToEdit = profile
                  }
                }
            }
            .onDelete(perform: editMode == .active ? deleteProfiles : nil)
            .onMove(perform: editMode == .active ? moveProfiles : nil)
          }
          .environment(\.editMode, $editMode)
        }
      }
      .navigationTitle(String(localized: "模式"))
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(action: { dismiss() }) {
            Image(systemName: "xmark")
          }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
          if editMode == .active {
            Button(action: { editMode = .inactive }) {
              Image(systemName: "checkmark.circle")
            }
          }
          if !profiles.isEmpty {
            Menu {
              Button {
                editMode = .active
              } label: {
                Label(String(localized: "編輯／移動"), systemImage: "pencil")
              }

              Button {
                showingDataExport = true
              } label: {
                Label(String(localized: "匯出資料"), systemImage: "square.and.arrow.up")
              }
            } label: {
              Image(systemName: "ellipsis.circle")
            }
          }
          Button(action: { showingCreateProfile = true }) {
            Image(systemName: "plus")
          }
        }
      }
      .sheet(isPresented: $showingCreateProfile) {
        BlockedProfileView()
      }
      .sheet(item: $profileToEdit) { profile in
        BlockedProfileView(profile: profile)
      }
      .sheet(isPresented: $showingDataExport) {
        BlockedProfileDataExportView()
      }
      .alert(
        String(localized: "無法刪除使用中的模式"),
        isPresented: $showErrorAlert
      ) {
        Button(String(localized: "好"), role: .cancel) {}
      } message: {
        Text(String(localized:
          "無法刪除目前使用中的模式，請先切換至其他模式。"
        ))
      }
    }
  }

  private func deleteProfiles(at offsets: IndexSet) {
    // Block deleting whichever profile the unified status reports as active — this honours
    // manual-beats-scheduled precedence and a scheduled cold start, rather than the
    // most-recent-by-time SwiftData query this guard used before.
    let activeProfileId = strategyManager.activeSessionStatus.activeProfileId

    // Check if any of the profiles to delete are active
    for index in offsets {
      let profile = profiles[index]
      if profile.id == activeProfileId {
        showErrorAlert = true
        return
      }
    }

    // Delete the profiles and reorder
    do {
      for index in offsets {
        let profile = profiles[index]
        strategyManager.handleProfileDeletion(profile, context: context)
        try BlockedProfiles.deleteProfile(profile, in: context)
      }

      // Reorder remaining profiles to fix gaps in ordering
      let remainingProfiles = try BlockedProfiles.fetchProfiles(in: context)
      try BlockedProfiles.reorderProfiles(remainingProfiles, in: context)
    } catch {
      bplLog.error("Failed to delete or reorder profiles: \(error)")
    }
  }

  private func moveProfiles(from source: IndexSet, to destination: Int) {
    var reorderedProfiles = Array(profiles)
    reorderedProfiles.move(fromOffsets: source, toOffset: destination)

    do {
      try BlockedProfiles.reorderProfiles(reorderedProfiles, in: context)
    } catch {
      bplLog.error("Failed to reorder profiles: \(error)")
    }
  }
}

#Preview {
  BlockedProfileListView()
    .modelContainer(for: BlockedProfiles.self, inMemory: true)
    .environmentObject(StrategyManager())
}
