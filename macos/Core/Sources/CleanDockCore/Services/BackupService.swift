//
//  BackupService.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import Foundation
import os

/// Filename-safe ISO 8601 timestamps, shared by backup snapshots and
/// preserved profile stores. ":" is legal in POSIX names but confusing in
/// Finder - it is replaced with "-".
enum FilenameTimestamp {
    static func stamp(for date: Date = Date()) -> String {
        iso8601Fractional.string(from: date).replacingOccurrences(of: ":", with: "-")
    }
}

/// Writes a JSON snapshot of the Dock's `persistent-apps` array (plus the
/// show-recents value) before every cleanup and restores the most recent
/// snapshot for "Undo".
///
/// Snapshots live in `~/Library/Application Support/CleanDock/backups/`
/// as `<ISO-timestamp>.json`. At most 10 snapshots are kept; the oldest are
/// pruned automatically.
public struct BackupService: Sendable {
    public static let maxBackups = 10

    public let directory: URL

    private static let logger = Logger(
        subsystem: CleanDockInfo.appBundleID,
        category: "BackupService"
    )

    public init(directory: URL = CleanDockPaths.backupsDirectory) {
        self.directory = directory
    }

    /// Everything a backup records: the `persistent-apps` tiles plus the
    /// `show-recents` value at snapshot time (`nil` for backups from
    /// versions that only stored the tile array). Not Sendable - tiles are
    /// raw property-list values, consumed synchronously by DockService.
    public struct Contents {
        public let tiles: [[String: Any]]
        public let showRecents: Bool?
    }

    /// Persists the given `persistent-apps` tiles (and the current
    /// `show-recents` value, so a restore can put it back) as a new backup
    /// and prunes old backups beyond `maxBackups`.
    @discardableResult
    public func write(tiles: [[String: Any]], showRecents: Bool? = nil) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var payload: [String: Any] = ["tiles": PropertyListJSON.jsonObject(from: tiles)]
        if let showRecents {
            payload["show-recents"] = showRecents
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        let url = try uniqueBackupURL()
        try data.write(to: url, options: .atomic)
        // Pruning failure must never abort the cleanup itself - the backup
        // is written, only housekeeping lagged (e.g. one locked old file).
        do {
            try prune()
        } catch {
            Self.logger.error("Backup pruning failed: \(error.localizedDescription)")
        }
        return url
    }

    /// A backup snapshot as shown to the user: when it was taken and how
    /// many apps it holds.
    public struct BackupInfo: Identifiable, Sendable {
        public let url: URL
        public let date: Date
        public let appCount: Int

        public var id: String { url.path }
    }

    /// All backups, newest first. ISO timestamps sort lexicographically,
    /// so sorting by filename is chronological.
    public func backups() -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// All backups with their metadata, newest first. Unreadable files are
    /// skipped - they cannot be restored anyway.
    public func backupInfos() -> [BackupInfo] {
        backups().compactMap { url in
            guard let tiles = try? tiles(at: url) else { return nil }
            let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate)
                ?? Date.distantPast
            return BackupInfo(url: url, date: date, appCount: tiles.count)
        }
    }

    /// The contents of the most recent backup, or `nil` if no backup exists.
    public func latestContents() throws -> Contents? {
        guard let url = backups().first else { return nil }
        return try contents(at: url)
    }

    /// Reads a specific backup file. Accepts both the current object format
    /// (`{"tiles": …, "show-recents": …}`) and the legacy plain tile array.
    /// Internal: restoring goes through `DockService`.
    func contents(at url: URL) throws -> Contents {
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data)
        if let wrapper = json as? [String: Any], let rawTiles = wrapper["tiles"] {
            guard let array = PropertyListJSON.plistObject(from: rawTiles) as? [[String: Any]] else {
                throw CleanDockError.invalidBackup(url.lastPathComponent)
            }
            return Contents(tiles: array, showRecents: wrapper["show-recents"] as? Bool)
        }
        guard let array = PropertyListJSON.plistObject(from: json) as? [[String: Any]] else {
            throw CleanDockError.invalidBackup(url.lastPathComponent)
        }
        return Contents(tiles: array, showRecents: nil)
    }

    /// The tiles stored in a specific backup file.
    func tiles(at url: URL) throws -> [[String: Any]] {
        try contents(at: url).tiles
    }

    public var hasBackups: Bool {
        !backups().isEmpty
    }

    /// Deletes all backups.
    public func removeAll() throws {
        for url in backups() {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func uniqueBackupURL() throws -> URL {
        let stamp = FilenameTimestamp.stamp()
        var url = directory.appendingPathComponent("\(stamp).json")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            // "_" sorts after "." so same-millisecond collisions stay in
            // chronological filename order; zero-padded for stable sorting.
            url = directory.appendingPathComponent(String(format: "%@_%03d.json", stamp, counter))
            counter += 1
        }
        return url
    }

    private func prune() throws {
        let all = backups()
        guard all.count > Self.maxBackups else { return }
        for url in all.dropFirst(Self.maxBackups) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

/// Lossless JSON encoding for property-list values.
///
/// Dock tiles may contain `Data` (bookmark blobs) and `Date` values, which
/// plain JSON cannot represent. These are wrapped in tagged objects so a
/// backup restores byte-identical tiles.
enum PropertyListJSON {
    // Deliberate: the tag keys are not escaped when encoding. A genuine
    // single-key dictionary {"$data": …} in a tile would be misread on
    // restore - but com.apple.dock never produces such keys, and escaping
    // would complicate the format for a purely theoretical input.
    private static let dataKey = "$data"
    private static let dateKey = "$date"

    static func jsonObject(from plist: Any) -> Any {
        switch plist {
        case let dictionary as [String: Any]:
            return dictionary.mapValues { jsonObject(from: $0) }
        case let array as [Any]:
            return array.map { jsonObject(from: $0) }
        case let data as Data:
            return [dataKey: data.base64EncodedString()]
        case let date as Date:
            return [dateKey: iso8601Fractional.string(from: date)]
        default:
            // String, NSNumber (Bool/Int/Double) pass through unchanged.
            return plist
        }
    }

    static func plistObject(from json: Any) -> Any {
        switch json {
        case let dictionary as [String: Any]:
            if dictionary.count == 1, let base64 = dictionary[dataKey] as? String,
               let data = Data(base64Encoded: base64) {
                return data
            }
            if dictionary.count == 1, let iso = dictionary[dateKey] as? String,
               let date = iso8601Fractional.date(from: iso) {
                return date
            }
            return dictionary.mapValues { plistObject(from: $0) }
        case let array as [Any]:
            return array.map { plistObject(from: $0) }
        default:
            return json
        }
    }
}
