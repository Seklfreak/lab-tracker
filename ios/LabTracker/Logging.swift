import Foundation
import os
import OSLog

/// App logging, centralized so the subsystem string is shared by the emitters and
/// the in-app log viewer (`LogViewerView`). Logs go to the unified log — readable
/// in Console.app with a Mac, or on-device via `recent()` below (an app may read
/// its own log store).
enum AppLog {
    static let subsystem = "dev.winktech.labtracker"

    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let healthSync = Logger(subsystem: subsystem, category: "healthsync")

    /// One rendered log entry for the on-device viewer.
    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let category: String
        let level: String
        let message: String
    }

    /// This app's own recent log entries (newest first), filtered to our subsystem.
    /// Reads the current process's store — third-party apps can read their own logs
    /// (iOS 15+). Only covers the running process, so a prior background launch's
    /// lines won't appear; foreground events (sign-in, refresh, sync) do.
    static func recent(within minutes: TimeInterval = 120) -> [Entry] {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let start = store.position(date: Date().addingTimeInterval(-minutes * 60))
            let entries = try store.getEntries(at: start)
            var out: [Entry] = []
            for case let log as OSLogEntryLog in entries where log.subsystem == subsystem {
                out.append(Entry(date: log.date, category: log.category,
                                 level: levelName(log.level), message: log.composedMessage))
            }
            return out.reversed() // newest first
        } catch {
            return []
        }
    }

    // MARK: - Persistent auth trail

    // The OSLogStore reader only sees the current process, so a sign-out that
    // happens in a *background* launch would be invisible next time the app opens.
    // Key auth events are also written to a small UserDefaults ring buffer that
    // survives across process launches, so the log viewer can show them.
    private static let authTrailKey = "authEventTrail"
    private static let authTrailMax = 40

    /// Record a key auth event to the cross-process trail (in addition to os.Logger).
    static func persistAuth(_ message: String, at date: Date = Date()) {
        let d = UserDefaults.standard
        var trail = d.stringArray(forKey: authTrailKey) ?? []
        trail.append("\(date.timeIntervalSince1970)\t\(message)")
        if trail.count > authTrailMax { trail.removeFirst(trail.count - authTrailMax) }
        d.set(trail, forKey: authTrailKey)
    }

    /// The persisted auth events, newest first.
    static func authTrail() -> [Entry] {
        let raw = UserDefaults.standard.stringArray(forKey: authTrailKey) ?? []
        return raw.reversed().map { line in
            let parts = line.split(separator: "\t", maxSplits: 1)
            let date = (parts.count == 2 ? TimeInterval(parts[0]) : nil).map { Date(timeIntervalSince1970: $0) } ?? Date()
            let msg = parts.count == 2 ? String(parts[1]) : line
            return Entry(date: date, category: "auth", level: "saved", message: msg)
        }
    }

    private static func levelName(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: return "debug"
        case .info: return "info"
        case .notice: return "notice"
        case .error: return "error"
        case .fault: return "fault"
        case .undefined: return "—"
        @unknown default: return "—"
        }
    }
}
