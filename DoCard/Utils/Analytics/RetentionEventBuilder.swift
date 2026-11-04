import CryptoKit
import Foundation

struct RetentionUploadEvent {
  let key: String
  let revision: Int
  let name: String
  let body: [String: Any]
}

/// Explicit allowlist: no model serialization, SDK enrichment or automatic events.
enum RetentionEventBuilder {
  static func timestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  static func events(state: RetentionJournal.State, environment: String, appVersion: String) throws
    -> [RetentionUploadEvent]
  {
    guard let cohort = state.cohort else { return [] }
    guard let zone = TimeZone(identifier: cohort.timeZoneID) else {
      throw RetentionJournal.JournalError.invalidRecord
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let anchor = calendar.startOfDay(for: cohort.startedAt)
    let parts = calendar.dateComponents([.year, .month, .day], from: anchor)
    let cohortDate = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    let common: [String: Any] = [
      "metric_version": 1, "environment": environment, "install_id": state.installID,
      "cohort_started_at": timestamp(cohort.startedAt), "cohort_date": cohortDate,
      "cohort_timezone": cohort.timeZoneID, "install_classification": state.classification,
      "measurement_activated_at": timestamp(state.activatedAt), "data_quality": "app_recorded",
      "upload_app_version": appVersion, "$process_person_profile": false, "$geoip_disable": true,
      "$ip": "0.0.0.0",
      "is_synthetic": state.installID.hasPrefix("retention-upload-test-"),
    ]
    func event(_ name: String, key: String, revision: Int, at: Date, properties: [String: Any])
      -> RetentionUploadEvent
    {
      var properties = common.merging(properties) { _, new in new }
      properties["revision"] = revision
      let id = digest("retention-v1|\(environment)|\(state.installID)|\(key)|\(revision)")
      // A stable UUID-shaped retry identifier; SQL also deduplicates key/revision.
      var bytes = Array(SHA256.hash(data: Data(id.utf8)).prefix(16))
      bytes[6] = (bytes[6] & 0x0f) | 0x40
      bytes[8] = (bytes[8] & 0x3f) | 0x80
      let uuid = UUID(
        uuid: (
          bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8],
          bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
      return RetentionUploadEvent(
        key: key, revision: revision, name: name,
        body: [
          "event": name, "distinct_id": state.installID, "uuid": uuid.uuidString,
          "timestamp": timestamp(at), "properties": properties,
        ])
    }
    var result = [
      event(
        "retention_cohort_entered", key: "cohort", revision: 1, at: cohort.startedAt,
        properties: ["source_session_id": cohort.sessionID])
    ]
    for key in state.contributions.keys.sorted() {
      guard let row = state.contributions[key], let session = state.sessions[row.sessionID],
        let endedAt = session.endedAt,
        let periodEnd = calendar.date(
          byAdding: .day, value: row.periodIndex * RetentionTimeCalculator.daysPerPeriod, to: anchor
        )
      else { throw RetentionJournal.JournalError.invalidRecord }
      var properties: [String: Any] = [
        "session_id": row.sessionID, "contribution_key": key,
        "session_started_at": timestamp(session.startedAt), "session_ended_at": timestamp(endedAt),
        "local_date": row.localDate, "day_offset": row.dayOffset, "period_index": row.periodIndex,
        "period_end_utc": timestamp(periodEnd), "locked_seconds": row.lockedSeconds,
        "trigger_source": session.trigger,
      ]
      if let reason = session.endReason { properties["end_reason"] = reason }
      if let start = session.breakStartedAt { properties["break_started_at"] = timestamp(start) }
      if let end = session.breakEndedAt { properties["break_ended_at"] = timestamp(end) }
      result.append(
        event(
          "retention_locked_time_contributed", key: "contribution:\(key)",
          revision: row.revision, at: endedAt, properties: properties))
    }
    return result
  }

  static func digest(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
