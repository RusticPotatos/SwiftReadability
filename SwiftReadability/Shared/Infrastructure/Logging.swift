//
//  Logging.swift
//  SwiftReadability
//
//  Created by rustic on 1/11/26.
//

import Foundation

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
}

struct LogEntry {
    let timestamp: Date
    let level: LogLevel
    let message: String

    var formatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestampString = formatter.string(from: timestamp)
        return "\(timestampString) [\(level.rawValue)]: \(message)"
    }
}

@MainActor
class Logger {
    static let shared = Logger()
    /// Controls whether debug-level logs are emitted. Defaults to true in DEBUG, false otherwise.
    #if DEBUG
    static var isVerbose: Bool = true
    #else
    static var isVerbose: Bool = false
    #endif
    private init() {}

    private(set) var logs: [LogEntry] = []

    func log(_ message: String, level: LogLevel = .debug) {
        // Skip debug logs when verbosity is off (e.g., Release builds)
        if level == .debug && Logger.isVerbose == false { return }
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        Task.detached(priority: .background) {
            await MainActor.run {
                self.logs.append(entry)
                Swift.print(entry.formatted)
                NotificationCenter.default.post(name: .didLogMessage, object: entry)
            }
        }
    }

    func readLogs() -> String {
        logs.map { $0.formatted }.joined(separator: "\n")
    }
}

#if canImport(UIKit)
import UIKit

extension Logger {
    func exportLogs(from viewController: UIViewController) {
        let logsText = readLogs()
        let tempDirectory = FileManager.default.temporaryDirectory
        let logFileURL = tempDirectory.appendingPathComponent("AppLogs.txt")

        do {
            try logsText.write(to: logFileURL, atomically: true, encoding: .utf8)

            // Use FileManager to zip the file using built-in API (or a third-party library if needed)
            // For now, just share the .txt file directly
            let activityVC = UIActivityViewController(activityItems: [logFileURL], applicationActivities: nil)
            activityVC.setValue("App Logs", forKey: "subject")
            activityVC.excludedActivityTypes = [.assignToContact, .addToReadingList]

            viewController.present(activityVC, animated: true)
        } catch {
            Swift.print("Failed to export logs: \(error)")
        }
    }
}
#endif

extension Notification.Name {
    static let didLogMessage = Notification.Name("didLogMessage")
}

/// Override the global print function so that all calls to logger() also log to our Logger.
func logger(_ items: Any..., separator: String = " ", terminator: String = "\n", level: LogLevel = .debug) {
    let message = items.map { "\($0)" }.joined(separator: separator)
    Task { @MainActor in
        Logger.shared.log(message, level: level)
    }
}
