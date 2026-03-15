import SwiftData
import SwiftUI

struct ScheduleTabView: View {
  @Environment(\.modelContext) private var context
  @EnvironmentObject var themeManager: ThemeManager

  @Query(sort: [
    SortDescriptor(\BlockedProfiles.order, order: .forward),
    SortDescriptor(\BlockedProfiles.createdAt, order: .reverse),
  ]) private var profiles: [BlockedProfiles]

  @State private var showCreateSheet = false
  @State private var editingProfile: BlockedProfiles? = nil
  @State private var showConflictAlert = false
  @State private var conflictProfileName = ""

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          let scheduledProfiles = profiles.filter { $0.schedule != nil }
          if scheduledProfiles.isEmpty {
            ContentUnavailableView(
              String(localized: "尚無排程"),
              systemImage: "calendar.badge.clock",
              description: Text(String(localized: "建立排程以自動啟動專注模式"))
            )
            .padding(.top, 60)
          } else {
            ForEach(scheduledProfiles, id: \.id) { profile in
              ScheduleCard(
                profile: profile,
                onToggle: { newValue in
                  toggleSchedule(profile: profile, enabled: newValue)
                },
                onTap: {
                  editingProfile = profile
                }
              )
            }
          }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
      }
      .safeAreaInset(edge: .bottom) {
        VStack(spacing: 8) {
          Text(String(localized: "建立新排程"))
            .font(.subheadline)
            .foregroundStyle(.secondary)

          Button(action: { showCreateSheet = true }) {
            Image(systemName: "plus")
              .font(.title2)
              .fontWeight(.medium)
              .foregroundStyle(.primary)
              .frame(width: 56, height: 56)
              .background(
                Circle()
                  .fill(.ultraThinMaterial)
                  .overlay(
                    Circle()
                      .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                  )
              )
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
      }
      .background(Color(.systemGroupedBackground).ignoresSafeArea())
      .navigationTitle(String(localized: "排程"))
    }
    .sheet(isPresented: $showCreateSheet) {
      ScheduleEditSheet(profile: nil, profiles: profiles)
    }
    .sheet(item: $editingProfile) { profile in
      ScheduleEditSheet(profile: profile, profiles: profiles)
    }
    .alert(String(localized: "時間衝突"), isPresented: $showConflictAlert) {
      Button(String(localized: "OK"), role: .cancel) {}
    } message: {
      Text(String(localized: "此排程與「\(conflictProfileName)」的排程時間衝突"))
    }
  }

  private func toggleSchedule(profile: BlockedProfiles, enabled: Bool) {
    guard var schedule = profile.schedule else { return }

    if enabled {
      if let conflicting = findConflictingSchedule(for: profile) {
        conflictProfileName = conflicting.name
        showConflictAlert = true
        return
      }
    }

    if enabled {
      if schedule.days.isEmpty {
        schedule.days = Weekday.allCases.map { $0 }
      }
    } else {
      schedule.days = []
    }
    schedule.updatedAt = Date()

    do {
      try BlockedProfiles.updateProfile(profile, in: context, schedule: schedule)
      if enabled {
        DeviceActivityCenterUtil.scheduleTimerActivity(for: profile)
      } else {
        DeviceActivityCenterUtil.removeScheduleTimerActivities(for: profile)
      }
    } catch {
      print("Failed to toggle schedule: \(error)")
    }
  }

  private func findConflictingSchedule(for targetProfile: BlockedProfiles) -> BlockedProfiles? {
    guard let targetSchedule = targetProfile.schedule else { return nil }

    for profile in profiles {
      guard profile.id != targetProfile.id,
        let otherSchedule = profile.schedule,
        otherSchedule.isActive
      else { continue }

      let targetDays = Set(
        targetSchedule.days.isEmpty ? Weekday.allCases : targetSchedule.days)
      let otherDays = Set(otherSchedule.days)
      guard !targetDays.isDisjoint(with: otherDays) else { continue }

      let targetStart = targetSchedule.startHour * 60 + targetSchedule.startMinute
      let targetEnd = targetSchedule.endHour * 60 + targetSchedule.endMinute
      let otherStart = otherSchedule.startHour * 60 + otherSchedule.startMinute
      let otherEnd = otherSchedule.endHour * 60 + otherSchedule.endMinute

      if targetStart < otherEnd && otherStart < targetEnd {
        return profile
      }
    }
    return nil
  }
}

// MARK: - Schedule Card

private struct ScheduleCard: View {
  let profile: BlockedProfiles
  let onToggle: (Bool) -> Void
  let onTap: () -> Void

  @EnvironmentObject var themeManager: ThemeManager

  var body: some View {
    Button(action: onTap) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(cardTitle)
            .font(.headline)
            .fontWeight(.bold)
            .foregroundStyle(.primary)

          if let schedule = profile.schedule {
            Text(scheduleSubtitle(schedule))
              .font(.subheadline)
              .foregroundStyle(.secondary)

            Text(
              String(localized: "模式：") + profile.name
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
          }
        }

        Spacer()

        Toggle(
          "",
          isOn: Binding(
            get: { profile.schedule?.isActive ?? false },
            set: { newValue in onToggle(newValue) }
          )
        )
        .labelsHidden()
        .tint(themeManager.themeColor)
      }
      .padding(16)
      .background(
        RoundedRectangle(cornerRadius: 16)
          .fill(Color(.secondarySystemGroupedBackground))
      )
    }
    .buttonStyle(.plain)
  }

  private var cardTitle: String {
    if let name = profile.schedule?.name, !name.isEmpty {
      return name
    }
    return profile.name
  }

  private func scheduleSubtitle(_ schedule: BlockedProfileSchedule) -> String {
    let timeStr = formatTime(hour: schedule.startHour, minute: schedule.startMinute)
    let daysStr = formatDays(schedule.days)
    return "\(timeStr) · \(daysStr)"
  }

  private func formatTime(hour: Int, minute: Int) -> String {
    var h = hour % 12
    if h == 0 { h = 12 }
    let isPM = hour >= 12
    return "\(h):\(String(format: "%02d", minute)) \(isPM ? "PM" : "AM")"
  }

  private func formatDays(_ days: [Weekday]) -> String {
    if days.isEmpty { return String(localized: "未設定") }

    let sorted = days.sorted { $0.rawValue < $1.rawValue }
    let weekdays: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday]
    let weekends: [Weekday] = [.saturday, .sunday]

    if Set(sorted) == Set(Weekday.allCases) {
      return String(localized: "每天")
    } else if Set(sorted) == Set(weekdays) {
      return String(localized: "平日")
    } else if Set(sorted) == Set(weekends) {
      return String(localized: "週末")
    } else {
      return sorted.map { $0.chineseShortLabel }.joined(separator: " ")
    }
  }
}

// MARK: - Schedule Edit Sheet

struct ScheduleEditSheet: View {
  @Environment(\.modelContext) private var context
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject var themeManager: ThemeManager

  let profile: BlockedProfiles?
  let profiles: [BlockedProfiles]

  // Form state
  @State private var scheduleName: String = ""
  @State private var selectedProfileId: UUID?
  @State private var selectedDays: Set<Weekday> = []
  @State private var startTime: Date = Calendar.current.date(
    from: DateComponents(hour: 9, minute: 0))!
  @State private var endTime: Date = Calendar.current.date(
    from: DateComponents(hour: 17, minute: 0))!
  @State private var endType: ScheduleEndType = .cardTap

  @State private var showConflictAlert = false
  @State private var conflictProfileName = ""
  @State private var showDeleteConfirmation = false
  @State private var showTimerConflictAlert = false

  // For editing/creating profiles from mode picker
  @State private var profileToEdit: BlockedProfiles? = nil
  @State private var showNewProfileView = false

  var isEditing: Bool { profile != nil }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          // Name field
          ScheduleFieldCard {
            HStack {
              Text(String(localized: "名稱"))
                .foregroundStyle(.secondary)
              Spacer()
              TextField(String(localized: "排程名稱"), text: $scheduleName)
                .multilineTextAlignment(.trailing)
            }
          }

          // Start / End time
          ScheduleFieldCard {
            VStack(spacing: 0) {
              HStack {
                Text(String(localized: "開始"))
                  .foregroundStyle(.secondary)
                Spacer()
                DatePicker(
                  "",
                  selection: $startTime,
                  displayedComponents: .hourAndMinute
                )
                .labelsHidden()
              }

              Divider()
                .padding(.vertical, 8)

              HStack {
                Text(String(localized: "結束"))
                  .foregroundStyle(.secondary)
                Spacer()

                Menu {
                  Button {
                    endType = .cardTap
                  } label: {
                    HStack {
                      Text(String(localized: "感應卡片"))
                      if endType == .cardTap {
                        Image(systemName: "checkmark")
                      }
                    }
                  }

                  Button {
                    endType = .specificTime
                  } label: {
                    HStack {
                      Text(String(localized: "指定時間"))
                      if endType == .specificTime {
                        Image(systemName: "checkmark")
                      }
                    }
                  }
                } label: {
                  if endType == .cardTap {
                    Text(String(localized: "感應卡片"))
                      .foregroundStyle(.primary)
                  } else {
                    DatePicker(
                      "",
                      selection: $endTime,
                      displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                  }
                }
              }
            }
          }

          // Profile/mode picker — NavigationLink push
          NavigationLink {
            ModePickerView(
              profiles: profiles,
              selectedProfileId: $selectedProfileId,
              onEditProfile: { profile in
                profileToEdit = profile
              },
              onNewProfile: {
                showNewProfileView = true
              }
            )
          } label: {
            ScheduleFieldCard {
              HStack {
                Text(String(localized: "模式"))
                  .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                  Text(selectedProfileName)
                    .foregroundStyle(themeManager.themeColor)
                  Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
            }
          }
          .buttonStyle(.plain)

          // Repeat / Day selector
          ScheduleFieldCard {
            VStack(alignment: .leading, spacing: 16) {
              HStack {
                Text(String(localized: "重複"))
                  .foregroundStyle(.secondary)
                Spacer()
                Text(daysLabel)
                  .foregroundStyle(.primary)
              }

              HStack(spacing: 6) {
                ForEach(Weekday.allCases, id: \.self) { day in
                  DayCircleButton(
                    label: day.chineseShortLabel,
                    isSelected: selectedDays.contains(day),
                    themeColor: themeManager.themeColor
                  ) {
                    if selectedDays.contains(day) {
                      selectedDays.remove(day)
                    } else {
                      selectedDays.insert(day)
                    }
                  }
                }
              }
            }
          }

          Spacer(minLength: 60)

          // Save button
          Button(action: saveSchedule) {
            Text(String(localized: "儲存排程"))
              .font(.headline)
              .fontWeight(.semibold)
              .foregroundStyle(.white)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 16)
              .background(
                RoundedRectangle(cornerRadius: 16)
                  .fill(themeManager.themeColor)
              )
          }
          .opacity((!isEditing && selectedProfileId == nil) || selectedDays.isEmpty ? 0.4 : 1.0)
          .disabled((!isEditing && selectedProfileId == nil) || selectedDays.isEmpty)

          // Delete button (edit mode)
          if isEditing {
            Button(action: { showDeleteConfirmation = true }) {
              Text(String(localized: "刪除排程"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 32)
      }
      .background(Color(.systemGroupedBackground).ignoresSafeArea())
      .navigationTitle(
        isEditing ? String(localized: "編輯排程") : String(localized: "新增排程"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(action: { dismiss() }) {
            Image(systemName: "xmark")
              .font(.body)
              .fontWeight(.medium)
              .foregroundStyle(.primary)
              .frame(width: 32, height: 32)
              .background(
                Circle()
                  .fill(Color(.systemGray5))
              )
          }
        }
      }
    }
    .onAppear {
      if let profile = profile, let schedule = profile.schedule {
        scheduleName = schedule.name
        selectedProfileId = profile.id
        selectedDays = Set(schedule.days)
        endType = schedule.endType
        let cal = Calendar.current
        startTime =
          cal.date(from: DateComponents(hour: schedule.startHour, minute: schedule.startMinute))
          ?? startTime
        endTime =
          cal.date(from: DateComponents(hour: schedule.endHour, minute: schedule.endMinute))
          ?? endTime
      }
    }
    .sheet(item: $profileToEdit) { profile in
      BlockedProfileView(profile: profile)
    }
    .sheet(isPresented: $showNewProfileView) {
      BlockedProfileView(profile: nil)
    }
    .alert(String(localized: "時間衝突"), isPresented: $showConflictAlert) {
      Button(String(localized: "OK"), role: .cancel) {}
    } message: {
      Text(String(localized: "此排程與「\(conflictProfileName)」的排程時間衝突"))
    }
    .alert(String(localized: "確認刪除"), isPresented: $showDeleteConfirmation) {
      Button(String(localized: "取消"), role: .cancel) {}
      Button(String(localized: "刪除"), role: .destructive) { deleteSchedule() }
    } message: {
      Text(String(localized: "確定要刪除此排程嗎？"))
    }
    .alert(String(localized: "無法建立排程"), isPresented: $showTimerConflictAlert) {
      Button(String(localized: "好"), role: .cancel) {}
    } message: {
      Text(String(localized: "計時模式無法與排程同時使用，請先將模式切換為經典模式"))
    }
  }

  // MARK: - Computed

  private var selectedProfileName: String {
    if let id = selectedProfileId, let p = profiles.first(where: { $0.id == id }) {
      return p.name
    }
    return String(localized: "請選擇")
  }

  private var daysLabel: String {
    if selectedDays.isEmpty { return String(localized: "未設定") }

    let weekdays = Set<Weekday>([.monday, .tuesday, .wednesday, .thursday, .friday])
    let weekends = Set<Weekday>([.saturday, .sunday])

    if selectedDays == Set(Weekday.allCases) {
      return String(localized: "每天")
    } else if selectedDays == weekdays {
      return String(localized: "平日")
    } else if selectedDays == weekends {
      return String(localized: "週末")
    } else {
      return selectedDays.sorted { $0.rawValue < $1.rawValue }
        .map { $0.chineseShortLabel }
        .joined(separator: " ")
    }
  }

  // MARK: - Actions

  private func saveSchedule() {
    let cal = Calendar.current
    let startComponents = cal.dateComponents([.hour, .minute], from: startTime)
    let endComponents = cal.dateComponents([.hour, .minute], from: endTime)

    let newSchedule = BlockedProfileSchedule(
      name: scheduleName,
      days: Array(selectedDays),
      startHour: startComponents.hour ?? 9,
      startMinute: startComponents.minute ?? 0,
      endHour: endType == .cardTap ? 23 : (endComponents.hour ?? 17),
      endMinute: endType == .cardTap ? 59 : (endComponents.minute ?? 0),
      endType: endType
    )

    let targetProfile: BlockedProfiles?
    if isEditing {
      targetProfile = profile
    } else {
      targetProfile = profiles.first { $0.id == selectedProfileId }
    }

    guard let targetProfile = targetProfile else { return }

    // Prevent scheduling for timer-based strategies
    if StrategyManager.isTimerStrategy(targetProfile.blockingStrategyId ?? "") {
      showTimerConflictAlert = true
      return
    }

    // Check for conflicts
    if endType == .specificTime {
      if let conflicting = findConflict(schedule: newSchedule, excludingProfile: targetProfile) {
        conflictProfileName = conflicting.name
        showConflictAlert = true
        return
      }
    }

    do {
      try BlockedProfiles.updateProfile(targetProfile, in: context, schedule: newSchedule)
      DeviceActivityCenterUtil.scheduleTimerActivity(for: targetProfile)
      dismiss()
    } catch {
      print("Failed to save schedule: \(error)")
    }
  }

  private func deleteSchedule() {
    guard let profile = profile else { return }
    do {
      DeviceActivityCenterUtil.removeScheduleTimerActivities(for: profile)
      profile.schedule = nil
      try context.save()
      dismiss()
    } catch {
      print("Failed to delete schedule: \(error)")
    }
  }

  private func findConflict(schedule: BlockedProfileSchedule, excludingProfile: BlockedProfiles)
    -> BlockedProfiles?
  {
    let targetDays = Set(schedule.days)
    let targetStart = schedule.startHour * 60 + schedule.startMinute
    let targetEnd = schedule.endHour * 60 + schedule.endMinute

    for p in profiles {
      guard p.id != excludingProfile.id,
        let otherSchedule = p.schedule,
        otherSchedule.isActive
      else { continue }

      let otherDays = Set(otherSchedule.days)
      guard !targetDays.isDisjoint(with: otherDays) else { continue }

      let otherStart = otherSchedule.startHour * 60 + otherSchedule.startMinute
      let otherEnd = otherSchedule.endHour * 60 + otherSchedule.endMinute

      if targetStart < otherEnd && otherStart < targetEnd {
        return p
      }
    }
    return nil
  }
}

// MARK: - Mode Picker View (Full-screen push)

private struct ModePickerView: View {
  let profiles: [BlockedProfiles]
  @Binding var selectedProfileId: UUID?
  let onEditProfile: (BlockedProfiles) -> Void
  let onNewProfile: () -> Void

  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject var themeManager: ThemeManager

  var body: some View {
    List {
      Section(header: Text(String(localized: "已建立模式"))) {
        ForEach(profiles, id: \.id) { profile in
          let isTimerProfile = StrategyManager.isTimerStrategy(
            profile.blockingStrategyId ?? "")

          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(profile.name)
                .font(.body)
                .foregroundStyle(isTimerProfile ? .secondary : .primary)

              if isTimerProfile {
                Text(String(localized: "計時模式無法使用排程"))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }

            Spacer()

            if selectedProfileId == profile.id && !isTimerProfile {
              Image(systemName: "checkmark")
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(themeManager.themeColor)
            }
          }
          .contentShape(Rectangle())
          .onTapGesture {
            if !isTimerProfile {
              selectedProfileId = profile.id
              dismiss()
            }
          }
          .swipeActions(edge: .trailing) {
            Button {
              onEditProfile(profile)
            } label: {
              Text(String(localized: "編輯"))
            }
            .tint(.gray)
          }
        }
      }

      Section {
        Button(action: onNewProfile) {
          HStack {
            Image(systemName: "plus")
              .foregroundStyle(themeManager.themeColor)
            Text(String(localized: "新增模式"))
              .foregroundStyle(.primary)
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle(String(localized: "選擇模式"))
    .navigationBarTitleDisplayMode(.inline)
  }
}

// MARK: - Schedule Field Card

private struct ScheduleFieldCard<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    content
      .padding(16)
      .background(
        RoundedRectangle(cornerRadius: 16)
          .fill(Color(.secondarySystemGroupedBackground))
      )
  }
}

// MARK: - Day Circle Button

private struct DayCircleButton: View {
  let label: String
  let isSelected: Bool
  let themeColor: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(label)
        .font(.system(size: 16, weight: .bold, design: .rounded))
        .padding(8)
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fill)
        .background(
          Circle()
            .fill(isSelected ? Color(.systemGray2) : Color(.systemGray5))
        )
        .foregroundStyle(isSelected ? .white : .secondary)
    }
    .buttonStyle(.plain)
  }
}

#Preview {
  ScheduleTabView()
    .environmentObject(ThemeManager.shared)
}
