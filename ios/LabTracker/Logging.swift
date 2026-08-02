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
