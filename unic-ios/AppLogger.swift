import Foundation
import os.log

// MARK: - AppLogger

/// Writes structured log entries to the Xcode console and to a rotating file in the app's
/// Documents directory (`app.log`, backup in `app.log.bak`).
///
/// Usage:
///   AppLogger.log(.info,    "FlexiBee", "→ GET /faktura-vydana.json")
///   AppLogger.log(.error,   "Auth",     "Login failed: \(error)")
///
/// Log file location (visible in Finder via connected device or Files app):
///   <Documents>/app.log
final class AppLogger: @unchecked Sendable {

    // MARK: - Level

    enum Level: String {
        case debug   = "DEBUG"
        case info    = "INFO"
        case warning = "WARN"
        case error   = "ERROR"

        fileprivate var osType: OSLogType {
            switch self {
            case .debug:   return .debug
            case .info:    return .info
            case .warning: return .default
            case .error:   return .error
            }
        }
    }

    // MARK: - Singleton

    static let shared = AppLogger()

    // MARK: - Internals

    private let fileURL:    URL
    private let backupURL:  URL
    private let queue = DispatchQueue(label: "unic.logger", qos: .utility)
    private let osLog  = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "unic-ios", category: "app")

    /// Max size before the file is rotated (~2 MB).
    private static let maxBytes: UInt64 = 2 * 1024 * 1024

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL   = docs.appendingPathComponent("app.log")
        backupURL = docs.appendingPathComponent("app.log.bak")
        // Rotate previous session's log into backup, start fresh
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.moveItem(at: fileURL, to: backupURL)
    }

    // MARK: - Public

    static func log(_ level: Level = .info, _ category: String, _ message: String) {
        shared.write(level: level, category: category, message: message)
    }

    /// Returns the contents of the current log file as a String (for in-app display / share sheet).
    static func currentLogContents() -> String {
        (try? String(contentsOf: shared.fileURL, encoding: .utf8)) ?? ""
    }

    static var logFileURL: URL { shared.fileURL }

    // MARK: - Private

    private func write(level: Level, category: String, message: String) {
        let lvlRaw    = level.rawValue
        let osType    = level.osType
        let log       = osLog
        let formatter = Self.formatter
        let maxBytes  = Self.maxBytes
        queue.async { [fileURL, backupURL, formatter, maxBytes] in
            let timestamp = formatter.string(from: Date())
            let line = "[\(timestamp)] [\(lvlRaw)] [\(category)] \(message)"

            os_log("%{public}@", log: log, type: osType, line as NSString)

            let fm = FileManager()
            guard let data = (line + "\n").data(using: .utf8) else { return }

            if let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
               let size = attrs[.size] as? UInt64, size >= maxBytes {
                try? fm.removeItem(at: backupURL)
                try? fm.moveItem(at: fileURL, to: backupURL)
            }

            if fm.fileExists(atPath: fileURL.path) {
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    defer { try? handle.close() }
                    handle.seekToEndOfFile()
                    handle.write(data)
                }
            } else {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }
}
