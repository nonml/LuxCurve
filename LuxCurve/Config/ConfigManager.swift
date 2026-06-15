//
//  ConfigManager.swift
//  LuxCurve
//
//  Loads/saves AppConfig at ~/.config/lux-curve/config.json. Writes are atomic
//  and a corrupt file is backed up rather than silently discarded.
//

import Foundation

@MainActor
final class ConfigManager {
    static let shared = ConfigManager()

    let directoryURL: URL
    let fileURL: URL

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        directoryURL = home.appendingPathComponent(".config/lux-curve", isDirectory: true)
        fileURL = directoryURL.appendingPathComponent("config.json")
    }

    /// Load config, falling back to defaults when missing or unreadable.
    func load() -> AppConfig {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .default
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(AppConfig.self, from: data)
        } catch {
            // Preserve the user's calibration on a parse error by moving the
            // file aside so it can be recovered, rather than discarding it.
            backupCorruptFile()
            NSLog("LuxCurve: failed to load config (\(error)); using defaults.")
            return .default
        }
    }

    /// Persist config atomically, creating the directory if needed.
    func save(_ config: AppConfig) {
        do {
            try FileManager.default.createDirectory(at: directoryURL,
                                                    withIntermediateDirectories: true)
            let data = try encoder.encode(config)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("LuxCurve: failed to save config (\(error)).")
        }
    }

    private func backupCorruptFile() {
        let backup = directoryURL.appendingPathComponent("config.corrupt.json")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.copyItem(at: fileURL, to: backup)
    }
}
