import Foundation
import OSLog

/// File-backed rolling log shared between the main app and DeviceActivity extension.
///
/// Why this exists: Xcode's console attachment drops after iOS suspends/reaps the
/// process, so logs from extension callbacks (intervalDidStart/intervalDidEnd) and
/// from foreground transitions long after launch are routinely lost. This writer
/// persists structured lines to a file in the App Group container that DebugView
/// renders on demand — no Xcode required.
///
/// Storage: App Group container's `Library/Caches/docard.debug.log`. Caches is fine
/// because the buffer is intentionally ephemeral; iOS may evict it under memory
/// pressure and we don't care.
///
/// Cap: ~256 KB rolling. When the file passes the cap, the writer truncates to the
/// last ~128 KB by rewriting the tail. Cheap, no third-party deps.
enum DebugLogStore {

  private static let appGroupSuiteName = "group.DO.version3"
  private static let logFileName = "docard.debug.log"
  private static let maxBytes = 256 * 1024
  private static let trimToBytes = 128 * 1024

  private static let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()

  private static let writeQueue = DispatchQueue(
    label: "online.do.card.app.debug-log", qos: .utility)

  private static var logFileURL: URL? {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupSuiteName)
    else { return nil }
    let dir = container.appendingPathComponent("Library/Caches", isDirectory: true)
    try? FileManager.default.createDirectory(
      at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent(logFileName)
  }

  /// Append a structured line. Tag identifies the source (e.g. "loadActiveSession",
  /// "intervalDidEnd"). Process is "app" or "ext" so we can tell who wrote what.
  static func log(_ tag: String, _ message: String, process: String = "app") {
    let line = "\(isoFormatter.string(from: Date())) [\(process)] [\(tag)] \(message)\n"
    writeQueue.async { append(line) }
  }

  private static func append(_ line: String) {
    guard let url = logFileURL, let data = line.data(using: .utf8) else { return }

    if !FileManager.default.fileExists(atPath: url.path) {
      try? data.write(to: url, options: .atomic)
      return
    }

    if let handle = try? FileHandle(forWritingTo: url) {
      defer { try? handle.close() }
      try? handle.seekToEnd()
      try? handle.write(contentsOf: data)
    }

    // Cheap rolling cap — only trim when a write pushes us over the limit.
    if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
      let size = attrs[.size] as? Int, size > maxBytes
    {
      trim(url: url)
    }
  }

  private static func trim(url: URL) {
    guard let data = try? Data(contentsOf: url), data.count > trimToBytes else {
      return
    }
    let tail = data.suffix(trimToBytes)
    // Drop partial first line so the file always starts on a clean line.
    if let newlineIdx = tail.firstIndex(of: 0x0A) {
      let cleanTail = tail.suffix(from: tail.index(after: newlineIdx))
      try? cleanTail.write(to: url, options: .atomic)
    } else {
      try? tail.write(to: url, options: .atomic)
    }
  }

  /// Read the full current log. Returns empty string if file doesn't exist.
  static func readAll() -> String {
    guard let url = logFileURL else { return "" }
    return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
  }

  static func clear() {
    guard let url = logFileURL else { return }
    try? FileManager.default.removeItem(at: url)
  }

  static func sizeBytes() -> Int {
    guard let url = logFileURL,
      let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
      let size = attrs[.size] as? Int
    else { return 0 }
    return size
  }
}
