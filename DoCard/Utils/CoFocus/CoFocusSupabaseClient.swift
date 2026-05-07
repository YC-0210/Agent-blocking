import Foundation
import Supabase

/// Singleton SupabaseClient configured for the co-focus feature.
///
/// Reuses the project URL and anon key from MacSupabaseClient — same Supabase
/// project, separate auth flow (Anonymous Auth vs the Mac sync's anon-key +
/// custom header pattern). The two coexist; mac_* tables are not visible to the
/// authenticated role used by anon-auth users (verified by Migration 1).
@MainActor
enum CoFocusSupabase {
  static let shared: SupabaseClient = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let raw = try container.decode(String.self)
      if let date = isoFractional.date(from: raw) ?? isoPlain.date(from: raw) {
        return date
      }
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Could not parse Postgres timestamptz: \(raw)"
      )
    }

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    let options = SupabaseClientOptions(
      db: SupabaseClientOptions.DatabaseOptions(
        encoder: encoder,
        decoder: decoder
      )
    )

    return SupabaseClient(
      supabaseURL: MacSupabaseClient.baseURL,
      supabaseKey: MacSupabaseClient.anonKey,
      options: options
    )
  }()

  // Postgres timestamptz can come back with or without fractional seconds.
  private static let isoFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()

  private static let isoPlain: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
  }()
}

// MARK: - RPC param structs

/// Encodable parameter envelopes that match the SQL RPCs in Migration 3.
/// Keeping these typed avoids string-keyed dictionary mistakes.
enum CoFocusRPC {
  struct CreatePairingParams: Encodable {
    let p_initiator_nickname: String
  }
  struct JoinPairingParams: Encodable {
    let p_code: String
    let p_joiner_nickname: String
  }
  struct PairingIdParams: Encodable {
    let p_pairing_id: UUID
  }
}
