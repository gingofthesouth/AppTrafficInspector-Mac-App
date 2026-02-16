//
//  DevLogger.swift
//  App Traffic Inspector
//
//  Logs only when building with DEBUG. In Release these calls are no-ops.
//  Keeps a ring buffer of recent entries for MCP get_error_log tool.
//

import Foundation
import os

public enum DevLogger {
#if DEBUG
    private static let log = Logger(subsystem: "AppTrafficInspectorKit", category: "Error")
    private static let maxRecentEntries = 200
    private static let lock = NSLock()
    private nonisolated(unsafe) static var _recentEntries: [String] = []

    public static func logError(_ error: Error) {
        let message = error.localizedDescription
        log.error("\(message)")
        appendRecent(level: "error", message: message)
    }

    public static func logError(message: String) {
        log.error("\(message)")
        appendRecent(level: "error", message: message)
    }

    public static func logInfo(message: String) {
        log.info("\(message)")
        appendRecent(level: "info", message: message)
    }

    private static func appendRecent(level: String, message: String) {
        lock.lock()
        defer { lock.unlock() }
        let line = "[\(level)] \(message)"
        _recentEntries.append(line)
        if _recentEntries.count > maxRecentEntries {
            _recentEntries.removeFirst(_recentEntries.count - maxRecentEntries)
        }
    }

    /// Recent log entries for MCP get_error_log tool. Thread-safe.
    public static var recentEntries: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _recentEntries
    }
#else
    public static func logError(_ error: Error) {}
    public static func logError(message: String) {}
    public static func logInfo(message: String) {}
    public static var recentEntries: [String] { [] }
#endif
}
