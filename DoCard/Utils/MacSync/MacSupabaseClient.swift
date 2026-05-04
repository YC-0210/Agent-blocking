import Foundation
import OSLog

private let log = Logger(subsystem: "online.do.card.app", category: "MacSupabase")

enum MacSupabaseError: Error {
  case invalidURL
  case httpError(Int, String)
  case transportError(Error)
  case decodingError(Error)
}

/// Thin REST wrapper around the project's Supabase. POC-grade: no SDK, no auth flows,
/// just the anon key. Used for the Mac ↔ iPhone session sync feature only.
enum MacSupabaseClient {

  static let baseURL = URL(string: "https://wbhicuxbvnketbdqywds.supabase.co")!
  static let anonKey =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndiaGljdXhidm5rZXRiZHF5d2RzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkzOTM1MjksImV4cCI6MjA4NDk2OTUyOX0.WJv_uaZTyFkTFgHoKXh9-4rW5WJVancLTVI5n7o0It8"

  /// Reads iphone_token without crossing the @MainActor boundary of
  /// MacPairingService.iphoneToken from this nonisolated async context.
  /// Storage priority matches the main getter: Keychain first, App Group
  /// UserDefaults as legacy fallback (covers the upgrade window where main
  /// app hasn't run since the move-to-Keychain migration).
  private static func iphoneTokenForRLS() -> String? {
    if let kc = KeychainHelper.loadString(
      MacPairingService.iphoneTokenKey,
      accessGroup: MacPairingService.keychainAccessGroup
    ) {
      return kc
    }
    return UserDefaults(suiteName: MacPairingService.appGroupSuiteName)?
      .string(forKey: MacPairingService.iphoneTokenKey)
  }

  private static let session: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 10
    config.timeoutIntervalForResource = 15
    return URLSession(configuration: config)
  }()

  /// Issues a request to `/rest/v1/{path}` and returns decoded JSON rows.
  /// `prefer` lets callers ask for `return=representation` etc.
  static func request<T: Decodable>(
    method: String,
    path: String,
    queryItems: [URLQueryItem] = [],
    body: Encodable? = nil,
    prefer: String? = nil,
    decoding: T.Type
  ) async throws -> T {
    var components = URLComponents(
      url: baseURL.appendingPathComponent("rest/v1/\(path)"),
      resolvingAgainstBaseURL: false
    )!
    if !queryItems.isEmpty {
      components.queryItems = queryItems
    }
    guard let url = components.url else { throw MacSupabaseError.invalidURL }

    var req = URLRequest(url: url)
    req.httpMethod = method
    req.setValue(anonKey, forHTTPHeaderField: "apikey")
    req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    // RLS identification: PostgREST surfaces this header to row-level policies
    // via current_setting('request.headers'). Policies on mac_pairings and
    // mac_sessions reject any request whose target row's iphone_token doesn't
    // match this header.
    if let token = iphoneTokenForRLS(), !token.isEmpty {
      req.setValue(token, forHTTPHeaderField: "X-Iphone-Token")
    }
    if let prefer = prefer {
      req.setValue(prefer, forHTTPHeaderField: "Prefer")
    }
    if let body = body {
      req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
    }

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await session.data(for: req)
    } catch {
      throw MacSupabaseError.transportError(error)
    }

    guard let http = response as? HTTPURLResponse else {
      throw MacSupabaseError.httpError(-1, "no response")
    }

    if !(200...299).contains(http.statusCode) {
      let bodyStr = String(data: data, encoding: .utf8) ?? ""
      log.error("Supabase \(method) \(path) failed: \(http.statusCode) \(bodyStr, privacy: .public)")
      throw MacSupabaseError.httpError(http.statusCode, bodyStr)
    }

    if T.self == EmptyResponse.self {
      return EmptyResponse() as! T
    }

    do {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      return try decoder.decode(T.self, from: data)
    } catch {
      throw MacSupabaseError.decodingError(error)
    }
  }
}

struct EmptyResponse: Decodable {}

private struct AnyEncodable: Encodable {
  let _encode: (Encoder) throws -> Void
  init(_ value: Encodable) {
    _encode = value.encode
  }
  func encode(to encoder: Encoder) throws {
    try _encode(encoder)
  }
}
