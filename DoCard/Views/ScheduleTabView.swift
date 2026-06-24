import OSLog
import SwiftData
import SwiftUI

private let scheduleLog = Logger(subsystem: "online.do.card.app", category: "ScheduleTab")

/// Identifies a specific schedule within a profile for editing.
private struct ScheduleEditContext: Identifiable {
  var id: UUID { schedule.id }
  let profile: BlockedProfiles
  let schedule: BlockedProfileSchedule
}

struct ScheduleTabView: View {
  @Environment(\.modelContext) private var context
  @EnvironmentObject var themeManager: ThemeManager
  @EnvironmentObject var subscriptionManager: SubscriptionManager
  @EnvironmentObject var strategyManager: StrategyManager

  @Query(sort: [
    SortDescriptor(\BlockedProfiles.order, order: .forward),
    SortDescriptor(\BlockedProfiles.createdAt, order: .reverse),
  ]) private var profiles: [BlockedProfiles]

  @State private var showCreateSheet = false
  @State private var editingContext: ScheduleEditContext? = nil
  @State private var showConflictAlert = false
  @State private var conflictProfileName = ""
  @State private var showPaywall = false
  @State private var showActiveScheduleBlockAlert = false

  /// All (profile, schedule) pairs flattened for display.
  private var scheduleEntries: [(profile: BlockedProfiles, schedule: BlockedProfileSchedule)] {
    profiles.flatMap { profile in
      profile.schedules.map { (profile: profile, schedule: $0) }
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          if scheduleEntries.isEmpty {
            ContentUnavailableView(
              String(localized: "尚無排程"),
              systemImage: "calendar.badge.clock",
              description: Text(String(localized: "建立排程以自動啟動專注模式"))
            )
            .padding(.top, 60)
          } else {
            ForEach(scheduleEntries, id: \.schedule.id) { entry in
              ScheduleCard(
                profile: entry.profile,
                schedule: entry.schedule,
                onToggle: { newValue in
                  if subscriptionManager.entitlements.canSchedule {
                    toggleSchedule(profile: entry.profile, schedule: entry.schedule, enabled: newValue)
                  } else {
                    showPaywall = true
                  }
                },
                onTap: {
                  if subscriptionManager.entitlements.canSchedule {
                    editingContext = ScheduleEditContext(
                      profile: entry.profile, schedule: entry.schedule)
                  } else {
                    showPaywall = true
                  }
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

          Button(action: {
            if subscriptionManager.entitlements.canSchedule {
              showCreateSheet = true
            } else {
              showPaywall = true
            }
          }) {
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
      ScheduleEditSheet(
        editingProfile: nil, editingSchedule: nil, profiles: profiles)
    }
    .sheet(item: $editingContext) { ctx in
      ScheduleEditSheet(
        editingProfile: ctx.profile, editingSchedule: ctx.schedule, profiles: profiles)
    }
    .sheet(isPresented: $showPaywall) {
      PremiumUpgradeView()
        .environmentObject(subscriptionManager)
    }
    .alert(String(localized: "時間衝突"), isPresented: $showConflictAlert) {
      Button(String(localized: "好"), role: .cancel) {}
    } message: {
      Text(String(localized: "此排程與「\(conflictProfileName)」的排程時間衝突"))
    }
    .alert(String(localized: "排程進行中"), isPresented: $showActiveScheduleBlockAlert) {
      Button(String(localized: "好"), role: .cancel) {}
    } message: {
      Text(String(localized: "這條排程正在進行中。請靠卡結束本次專注，或使用緊急解鎖。"))
    }
  }

  private func toggleSchedule(
    profile: BlockedProfiles, schedule: BlockedProfileSchedule, enabled: Bool
  ) {
    var updated = schedule

    if enabled {
      if let conflicting = findConflictingSchedule(
        schedule: schedule, inProfile: profile)
      {
        conflictProfileName = conflicting.name
        showConflictAlert = true
        return
      }
    } else {
      // Bug #1: prevent bypass via toggle. If THIS schedule is currently
      // driving an active scheduled blocking session for THIS profile,
      // block the toggle and surface a brand-aligned alert. Card tap and
      // emergency unlock are the only legitimate escape paths from an
      // in-progress schedule window — letting the toggle silently end the
      // session would defeat the "environment design promise" the schedule
      // exists to enforce.
      //
      // Because the SwiftData session does not record which specific
      // schedule started it, we approximate by checking that THIS
      // schedule's window is currently active. This slightly over-blocks
      // when a profile has multiple overlapping in-window schedules
      // (toggling off any of them is blocked while any is driving),
      // which is the safer default until BlockedProfileSession gains a
      // schedule_id field.
      if let session = strategyManager.activeSession,
        session.blockedProfile.id == profile.id,
        session.triggerSource == "scheduled",
        schedule.isCurrentlyInWindow()
      {
        showActiveScheduleBlockAlert = true
        return  // schedule.isActive unchanged → Toggle binding's get returns true → visual reverts.
      }
    }

    if enabled {
      if updated.days.isEmpty {
        updated.days = Weekday.allCases.map { $0 }
      }
    } else {
      updated.days = []
    }
    updated.updatedAt = Date()

    do {
      try BlockedProfiles.updateSchedule(in: profile, context: context, schedule: updated)
      if enabled {
        try DeviceActivityCenterUtil.scheduleTimerActivity(
          for: profile, schedule: updated)
        if updated.isCurrentlyInWindow(),
          let snapshot = SharedData.snapshot(for: profile.id.uuidString)
        {
          ScheduleTimerActivity().start(for: snapshot)
        }
      } else {
        DeviceActivityCenterUtil.removeScheduleTimerActivity(
          for: profile, scheduleId: updated.id)
      }
    } catch {
      scheduleLog.error("Failed to toggle schedule: \(error)")
    }
  }

  /// Finds a conflicting schedule across ALL profiles (excluding the schedule being toggled).
  private func findConflictingSchedule(
    schedule: BlockedProfileSchedule,
    inProfile targetProfile: BlockedProfiles
  ) -> BlockedProfiles? {
    let effectiveDays = schedule.days.isEmpty ? Array(Weekday.allCases) : schedule.days
    let target = BlockedProfileSchedule(
      id: schedule.id, name: schedule.name,
      days: effectiveDays,
      startHour: schedule.startHour, startMinute: schedule.startMinute,
      endHour: schedule.endHour, endMinute: schedule.endMinute,
      endType: schedule.endType, isNextDay: schedule.isNextDay)
    let targetRanges = scheduleMinuteRanges(target)

    for profile in profiles {
      for otherSchedule in profile.schedules {
        guard otherSchedule.id != schedule.id, otherSchedule.isActive else { continue }
        let otherRanges = scheduleMinuteRanges(otherSchedule)
        if minuteRangesOverlap(targetRanges, otherRanges) {
          return profile
        }
      }
    }
    return nil
  }
}

// MARK: - Conflict Detection Helpers

/// Expands a schedule into (start, end, weekday) minute-ranges.
/// Cross-midnight schedules are split into two segments per day:
///   segment 1: startMinutes → 1440 on the start weekday
///   segment 2: 0 → endMinutes on the following weekday
private func scheduleMinuteRanges(
  _ s: BlockedProfileSchedule
) -> [(start: Int, end: Int, weekday: Int)] {
  var ranges: [(start: Int, end: Int, weekday: Int)] = []
  let startMins = s.startHour * 60 + s.startMinute
  let endMins = s.endHour * 60 + s.endMinute
  for day in s.days {
    if s.isNextDay {
      ranges.append((start: startMins, end: 1440, weekday: day.rawValue))
      let nextWeekday = day.rawValue % 7 + 1
      ranges.append((start: 0, end: endMins, weekday: nextWeekday))
    } else {
      ranges.append((start: startMins, end: endMins, weekday: day.rawValue))
    }
  }
  return ranges
}

/// Returns true if any two ranges from the two sets share the same weekday and overlap in time.
private func minuteRangesOverlap(
  _ a: [(start: Int, end: Int, weekday: Int)],
  _ b: [(start: Int, end: Int, weekday: Int)]
) -> Bool {
  for ra in a {
    for rb in b {
      guard ra.weekday == rb.weekday else { continue }
      if ra.start < rb.end && rb.start < ra.end {
        return true
      }
    }
  }
  return false
}

// MARK: - Schedule Card

private struct ScheduleCard: View {
  let profile: BlockedProfiles
  let schedule: BlockedProfileSchedule
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

          Text(scheduleSubtitle(schedule))
            .font(.subheadline)
            .foregroundStyle(.secondary)

          Text(
            String(localized: "模式：") + profile.name
          )
          .font(.subheadline)
          .foregroundStyle(.secondary)
        }

        Spacer()

        Toggle(
          "",
          isOn: Binding(
            get: { schedule.isActive },
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
    if !schedule.name.isEmpty {
      return schedule.name
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

  let editingProfile: BlockedProfiles?
  let editingSchedule: BlockedProfileSchedule?
  let profiles: [BlockedProfiles]

  // Form state
  @State private var scheduleName: String = ""
  @State private var selectedProfileId: UUID?
  @State private var selectedDays: Set<Weekday> = []
  @State private var startTime: Date = Calendar.current.date(
    from: DateComponents(hour: 9, minute: 0))!
  @State private var endTime: Date = Calendar.current.date(
    from: DateComponents(hour: 17, minute: 0))!
  @State private var endType: ScheduleEndType = .specificTime
  @State private var isNextDay: Bool = false

  @State private var showConflictAlert = false
  @State private var conflictProfileName = ""
  @State private var showDeleteConfirmation = false
  @State private var showTimerConflictAlert = false
  @State private var showEndBeforeStartAlert = false
  @State private var showNextDayMismatchAlert = false

  // For editing/creating profiles from mode picker
  @State private var profileToEdit: BlockedProfiles? = nil
  @State private var showNewProfileView = false

  var isEditing: Bool { editingSchedule != nil }

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
                  endTimeMenuLabel
                }
              }

              if endType == .specificTime {
                Divider()
                  .padding(.vertical, 8)

                HStack {
                  Text(String(localized: "隔天"))
                    .foregroundStyle(.secondary)
                  Spacer()
                  Toggle("", isOn: $isNextDay)
                    .labelsHidden()
                    .tint(themeManager.themeColor)
                }
              }
            }
          }

          // Profile/mode picker — NavigationLink push (only for new schedules)
          if !isEditing {
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
          } else {
            // Show the profile name as read-only when editing
            ScheduleFieldCard {
              HStack {
                Text(String(localized: "模式"))
                  .foregroundStyle(.secondary)
                Spacer()
                Text(editingProfile?.name ?? "")
                  .foregroundStyle(themeManager.themeColor)
              }
            }
          }

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
      if let schedule = editingSchedule {
        scheduleName = schedule.name
        selectedProfileId = editingProfile?.id
        selectedDays = Set(schedule.days)
        endType = schedule.endType
        isNextDay = schedule.isNextDay
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
      Button(String(localized: "好"), role: .cancel) {}
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
    .alert(String(localized: "時間設定錯誤"), isPresented: $showEndBeforeStartAlert) {
      Button(String(localized: "確認"), role: .cancel) {}
    } message: {
      Text(String(localized: "結束時間不能早於或等於開始時間。若需跨夜排程，請開啟「隔天」設定。"))
    }
    .alert(
      String(localized: "已啟用「隔天」設定，但結束時間晚於開始時間。是否要關閉「隔天」？"),
      isPresented: $showNextDayMismatchAlert
    ) {
      Button(String(localized: "關閉隔天")) {
        isNextDay = false
      }
      Button(String(localized: "保持設定"), role: .cancel) {}
    } message: {
      Text("")
    }
  }

  // MARK: - Computed

  @ViewBuilder
  private var endTimeMenuLabel: some View {
    if endType == .cardTap {
      Text(String(localized: "感應卡片"))
        .foregroundStyle(.primary)
    } else {
      HStack(spacing: 4) {
        if isNextDay {
          Text(String(localized: "+1天"))
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(themeManager.themeColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(themeManager.themeColor.opacity(0.15)))
        }
        DatePicker("", selection: $endTime, displayedComponents: .hourAndMinute)
          .labelsHidden()
      }
    }
  }

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

    if endType == .specificTime {
      let startH = startComponents.hour ?? 9
      let startM = startComponents.minute ?? 0
      let endH = endComponents.hour ?? 17
      let endM = endComponents.minute ?? 0
      if !isNextDay {
        // Same-day schedule: end must be strictly after start
        if endH < startH || (endH == startH && endM <= startM) {
          showEndBeforeStartAlert = true
          return
        }
      } else if endH > startH || (endH == startH && endM > startM) {
        // Cross-midnight toggle is on but end is after start — likely a mistake
        showNextDayMismatchAlert = true
        return
      }
    }

    var newSchedule = BlockedProfileSchedule(
      id: editingSchedule?.id ?? UUID(),
      name: scheduleName,
      days: Array(selectedDays),
      startHour: startComponents.hour ?? 9,
      startMinute: startComponents.minute ?? 0,
      endHour: endType == .cardTap ? 23 : (endComponents.hour ?? 17),
      endMinute: endType == .cardTap ? 59 : (endComponents.minute ?? 0),
      endType: endType,
      isNextDay: endType == .specificTime ? isNextDay : false
    )

    let targetProfile: BlockedProfiles?
    if isEditing {
      targetProfile = editingProfile
    } else {
      targetProfile = profiles.first { $0.id == selectedProfileId }
    }

    guard let targetProfile = targetProfile else { return }

    // Prevent scheduling for timer-based strategies
    if StrategyManager.isTimerStrategy(targetProfile.blockingStrategyId ?? "") {
      showTimerConflictAlert = true
      return
    }

    // Check for conflicts across all schedules in all profiles
    if endType == .specificTime {
      if let conflicting = findConflict(
        schedule: newSchedule, excludingScheduleId: newSchedule.id)
      {
        conflictProfileName = conflicting.name
        showConflictAlert = true
        return
      }
    }

    do {
      if isEditing {
        try BlockedProfiles.updateSchedule(
          in: targetProfile, context: context, schedule: newSchedule)
      } else {
        try BlockedProfiles.addSchedule(
          to: targetProfile, in: context, schedule: newSchedule)
      }
      try DeviceActivityCenterUtil.scheduleTimerActivity(
        for: targetProfile, schedule: newSchedule)
      // Start immediately if currently within the new schedule window.
      if newSchedule.isCurrentlyInWindow(),
        let snapshot = SharedData.snapshot(for: targetProfile.id.uuidString)
      {
        ScheduleTimerActivity().start(for: snapshot)
      }
      dismiss()
    } catch {
      scheduleLog.error("Failed to save schedule: \(error)")
    }
  }

  private func deleteSchedule() {
    guard let profile = editingProfile, let schedule = editingSchedule else { return }
    do {
      DeviceActivityCenterUtil.removeScheduleTimerActivity(
        for: profile, scheduleId: schedule.id)
      try BlockedProfiles.removeSchedule(
        from: profile, in: context, scheduleId: schedule.id)
      dismiss()
    } catch {
      scheduleLog.error("Failed to delete schedule: \(error)")
    }
  }

  /// Checks for time conflicts across ALL schedules in ALL profiles.
  private func findConflict(
    schedule: BlockedProfileSchedule, excludingScheduleId: UUID
  ) -> BlockedProfiles? {
    let targetRanges = scheduleMinuteRanges(schedule)
    for p in profiles {
      for otherSchedule in p.schedules {
        guard otherSchedule.id != excludingScheduleId, otherSchedule.isActive else { continue }
        let otherRanges = scheduleMinuteRanges(otherSchedule)
        if minuteRangesOverlap(targetRanges, otherRanges) {
          return p
        }
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
    .environmentObject(SubscriptionManager.shared)
}
