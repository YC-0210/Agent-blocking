import Foundation

// MARK: - Status

enum PairingStatus: String, Codable, Sendable {
  case waitingJoin = "waiting_join"
  case waitingTap  = "waiting_tap"
  case active
  case completed
  case cancelled
  case expired
  case abandoned
}

extension PairingStatus {
  var isInFlight: Bool {
    switch self {
    case .waitingJoin, .waitingTap, .active: return true
    case .completed, .cancelled, .expired, .abandoned: return false
    }
  }
}

// MARK: - PairingSession (mirrors public.pairing_sessions)

struct PairingSession: Codable, Sendable, Identifiable, Equatable {
  let id: UUID
  let code: String?
  let initiatorUserId: UUID
  let initiatorNickname: String
  let joinerUserId: UUID?
  let joinerNickname: String?
  let status: PairingStatus
  let initiatorTappedAt: Date?
  let joinerTappedAt: Date?
  let sessionStartAt: Date?
  let sessionEndAt: Date?
  let endedByUserId: UUID?
  let expiresAt: Date
  let tapDeadline: Date?
  let createdAt: Date

  enum CodingKeys: String, CodingKey {
    case id, code, status
    case initiatorUserId   = "initiator_user_id"
    case initiatorNickname = "initiator_nickname"
    case joinerUserId      = "joiner_user_id"
    case joinerNickname    = "joiner_nickname"
    case initiatorTappedAt = "initiator_tapped_at"
    case joinerTappedAt    = "joiner_tapped_at"
    case sessionStartAt    = "session_start_at"
    case sessionEndAt      = "session_end_at"
    case endedByUserId     = "ended_by_user_id"
    case expiresAt         = "expires_at"
    case tapDeadline       = "tap_deadline"
    case createdAt         = "created_at"
  }
}

extension PairingSession {
  func isParticipant(_ userId: UUID) -> Bool {
    userId == initiatorUserId || userId == joinerUserId
  }

  func partnerNickname(forCaller userId: UUID) -> String? {
    if userId == initiatorUserId { return joinerNickname }
    if userId == joinerUserId    { return initiatorNickname }
    return nil
  }

  func partnerUserId(forCaller userId: UUID) -> UUID? {
    if userId == initiatorUserId { return joinerUserId }
    if userId == joinerUserId    { return initiatorUserId }
    return nil
  }

  func hasTapped(_ userId: UUID) -> Bool {
    if userId == initiatorUserId { return initiatorTappedAt != nil }
    if userId == joinerUserId    { return joinerTappedAt != nil }
    return false
  }

  /// True iff `userId` is the one who first unlocked (set when status flips to .completed).
  func wasEndedBy(_ userId: UUID) -> Bool {
    endedByUserId == userId
  }
}

// MARK: - PairFocusRecord (mirrors public.pair_focus_records)

struct PairFocusRecord: Codable, Sendable, Identifiable, Equatable {
  let id: UUID
  let userId: UUID
  let partnerUserId: UUID
  let partnerNickname: String
  let sessionStartAt: Date
  let sessionEndAt: Date
  let durationSeconds: Int
  let pairingSessionId: UUID
  let createdAt: Date

  enum CodingKeys: String, CodingKey {
    case id
    case userId           = "user_id"
    case partnerUserId    = "partner_user_id"
    case partnerNickname  = "partner_nickname"
    case sessionStartAt   = "session_start_at"
    case sessionEndAt     = "session_end_at"
    case durationSeconds  = "duration_seconds"
    case pairingSessionId = "pairing_session_id"
    case createdAt        = "created_at"
  }
}

// MARK: - Aggregates

struct CoFocusMonthlyTotal: Codable, Sendable, Equatable {
  let totalSeconds: Int
  let sessionCount: Int

  static let zero = CoFocusMonthlyTotal(totalSeconds: 0, sessionCount: 0)

  enum CodingKeys: String, CodingKey {
    case totalSeconds = "total_seconds"
    case sessionCount = "session_count"
  }
}
