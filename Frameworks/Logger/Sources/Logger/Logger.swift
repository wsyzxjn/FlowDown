//
//  Logger.swift
//  Storage
//
//  Created by king on 2025/10/14.
//

@_exported import Foundation
@_exported import OSLog

public extension Logger {
    static let loggingSubsystem: String = {
        if let identifier = Bundle.main.bundleIdentifier, !identifier.isEmpty {
            return identifier
        }
        return ProcessInfo.processInfo.processName
    }()

    static let database = Logger(subsystem: Self.loggingSubsystem, category: "Database")
    static let syncEngine = Logger(subsystem: Self.loggingSubsystem, category: "SyncEngine")
    static let chatService = Logger(subsystem: Self.loggingSubsystem, category: "ChatService")
    static let app = Logger(subsystem: Self.loggingSubsystem, category: "App")
    static let ui = Logger(subsystem: Self.loggingSubsystem, category: "UI")
    static let network = Logger(subsystem: Self.loggingSubsystem, category: "Network")
    static let model = Logger(subsystem: Self.loggingSubsystem, category: "Model")
}

public enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case error = "ERROR"
}

public final class LogStore {
    public static let shared = LogStore()

    private let queue = DispatchQueue(label: "wiki.qaq.flowdown.logstore", qos: .utility)
    private let fileManager = FileManager.default

    private let maxFileSize: Int = 128 * 1024 * 1024 // 5 MB
    private let maxFiles: Int = 5

    private lazy var logsDir: URL = {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("Logs", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var logFileURL: URL { logsDir.appendingPathComponent("FlowDown.log") }

    public func append(level: LogLevel, category: String, message: String) {
        let line = "\(timestamp()) [\(level.rawValue)] [\(category)] \(message)\n"
        queue.async { [weak self] in
            guard let self else { return }
            if !fileManager.fileExists(atPath: logFileURL.path) {
                fileManager.createFile(atPath: logFileURL.path, contents: nil)
            }
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                defer { try? handle.close() }
                do { try handle.seekToEnd(); if let data = line.data(using: .utf8) { try handle.write(contentsOf: data) } } catch {}
            }
            rotateIfNeeded()
        }
    }

    public func readTail(maxBytes: Int = 128 * 1024) -> String {
        guard let data = try? Data(contentsOf: logFileURL) else { return "" }
        if data.count <= maxBytes { return String(data: data, encoding: .utf8) ?? "" }
        let slice = data.suffix(maxBytes)
        return String(data: slice, encoding: .utf8) ?? ""
    }

    public func clear() {
        try? fileManager.removeItem(at: logFileURL)
    }

    private func rotateIfNeeded() {
        guard let attrs = try? fileManager.attributesOfItem(atPath: logFileURL.path),
              let size = attrs[.size] as? NSNumber else { return }
        if size.intValue < maxFileSize { return }

        // Shift old files
        for i in stride(from: maxFiles - 1, through: 1, by: -1) {
            let src = logsDir.appendingPathComponent("FlowDown.log.\(i)")
            let dst = logsDir.appendingPathComponent("FlowDown.log.\(i + 1)")
            if fileManager.fileExists(atPath: dst.path) { try? fileManager.removeItem(at: dst) }
            if fileManager.fileExists(atPath: src.path) { try? fileManager.moveItem(at: src, to: dst) }
        }
        let first = logsDir.appendingPathComponent("FlowDown.log.1")
        if fileManager.fileExists(atPath: first.path) { try? fileManager.removeItem(at: first) }
        try? fileManager.moveItem(at: logFileURL, to: first)
        fileManager.createFile(atPath: logFileURL.path, contents: nil)
    }

    private func timestamp() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }
}

public extension Logger {
    private func inferredCategory(from fileID: String) -> String {
        let lower = fileID.lowercased()
        if lower.contains("model") { return "Model" }
        if lower.contains("network") { return "Network" }
        if lower.contains("ui") || lower.contains("view") || lower.contains("controller") { return "UI" }
        if lower.contains("storage") || lower.contains("database") { return "Database" }
        return "App"
    }

    func debugFile(_ message: String, category: String? = nil, fileID: String = #fileID) {
        debug("\(message)")
        LogStore.shared.append(level: .debug, category: category ?? inferredCategory(from: fileID), message: message)
    }

    func infoFile(_ message: String, category: String? = nil, fileID: String = #fileID) {
        info("\(message)")
        LogStore.shared.append(level: .info, category: category ?? inferredCategory(from: fileID), message: message)
    }

    func errorFile(_ message: String, category: String? = nil, fileID: String = #fileID) {
        error("\(message)")
        LogStore.shared.append(level: .error, category: category ?? inferredCategory(from: fileID), message: message)
    }
}
