//
//  DockService.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import Foundation
import os

/// The result of applying a profile to the Dock.
public struct ApplyResult: Sendable {
    /// Apps that were resolved and placed in the Dock, in Dock order.
    public let applied: [DockApp]
    /// Apps that are not installed; they are skipped and reported here,
    /// never treated as an error.
    public let skipped: [DockApp]

    public init(applied: [DockApp], skipped: [DockApp]) {
        self.applied = applied
        self.skipped = skipped
    }
}

/// Reads and writes the Dock's `persistent-apps` via CFPreferences and
/// restarts the Dock. Never touches `persistent-others`.
///
/// Writing goes through CFPreferences exclusively - writing the plist file
/// directly would be overwritten by cfprefsd's cache.
public struct DockService: Sendable {
    public static let dockDomain = "com.apple.dock"

    private static let logger = Logger(
        subsystem: CleanDockInfo.appBundleID,
        category: "DockService"
    )

    public let resolver: AppResolver
    public let backupService: BackupService
    /// Test hook: replaces the actual CFPreferences write + Dock restart.
    /// `showRecents` is tri-state: true/false writes the value, nil leaves
    /// the user's setting untouched (legacy-backup restore).
    private let dockWriter: (@Sendable (_ tiles: [[String: Any]], _ showRecents: Bool?) throws -> Void)?
    /// Test hook: replaces the actual CFPreferences read.
    private let dockReader: (@Sendable () -> [[String: Any]]?)?
    /// Test hook: replaces the actual `show-recents` read.
    private let showRecentsReader: (@Sendable () -> Bool)?

    public init(
        resolver: AppResolver = AppResolver(),
        backupService: BackupService = BackupService(),
        dockWriter: (@Sendable ([[String: Any]], Bool?) throws -> Void)? = nil,
        dockReader: (@Sendable () -> [[String: Any]]?)? = nil,
        showRecentsReader: (@Sendable () -> Bool)? = nil
    ) {
        self.resolver = resolver
        self.backupService = backupService
        self.dockWriter = dockWriter
        self.dockReader = dockReader
        self.showRecentsReader = showRecentsReader
    }

    // MARK: - Tile construction

    /// Builds a minimal `persistent-apps` tile for an application URL.
    ///
    /// `_CFURLString` must be a file URL *with a trailing slash* and correct
    /// percent-encoding; `_CFURLStringType` 15 marks it as a URL string.
    /// The Dock fills in missing fields (GUID etc.) by itself.
    static func tile(forAppAt url: URL) -> [String: Any] {
        let directoryURL = URL(fileURLWithPath: url.path, isDirectory: true)
        return [
            "tile-data": [
                "file-data": [
                    "_CFURLString": directoryURL.absoluteString,
                    "_CFURLStringType": 15
                ]
            ],
            "tile-type": "file-tile"
        ]
    }

    /// Resolves the profile's apps into (resolved URL, app) pairs plus the
    /// list of skipped apps.
    func resolveApps(of profile: Profile) -> (resolved: [(url: URL, app: DockApp)], skipped: [DockApp]) {
        var resolved: [(URL, DockApp)] = []
        var skipped: [DockApp] = []
        for app in profile.apps {
            if let url = resolver.resolve(app) {
                resolved.append((url, app))
            } else {
                // Silent skip by design - a debug log is the only trace
                // besides the returned list.
                Self.logger.debug("Skipping app that is not installed: \(app.name, privacy: .public)")
                skipped.append(app)
            }
        }
        return (resolved, skipped)
    }

    // MARK: - Apply / capture / restore

    /// Applies a profile: resolve → backup → write tiles → restart Dock.
    /// Apps that cannot be resolved are silently skipped (returned in the
    /// result so the UI can show a subtle hint).
    ///
    /// `backingUp: false` skips the snapshot - only for multi-profile CLI
    /// runs, where per-apply backups would rotate the run's actual starting
    /// state out of the backup list.
    @discardableResult
    public func apply(_ profile: Profile, backingUp: Bool = true) throws -> ApplyResult {
        let (resolved, skipped) = resolveApps(of: profile)

        if backingUp {
            // Back up the current Dock before touching anything - tiles AND
            // the show-recents value, so undo restores both.
            let currentTiles = try readPersistentAppsForBackup()
            try backupService.write(tiles: currentTiles, showRecents: readShowRecents())
        }

        let tiles = resolved.map { Self.tile(forAppAt: $0.url) }
        // Two-way on purpose: writing show-recents only when hiding would
        // leave it stuck after a single hide-recents profile - the profile
        // switch must also be able to bring the recents section back. The
        // backup above records the previous value, so undo stays symmetric.
        try writeTilesAndRestart(tiles, showRecents: !profile.hideRecents)
        return ApplyResult(applied: resolved.map(\.app), skipped: skipped)
    }

    /// Reads the current Dock's apps; callers outside the module go through
    /// `captureDock()`, which also mirrors the hide-recents state.
    func capture() -> [DockApp] {
        apps(fromTiles: readPersistentApps() ?? [])
    }

    /// Reads the current Dock as a full profile snapshot: the apps AND the
    /// hide-recents state. An adopted profile must reproduce the user's
    /// whole left-side Dock on apply - capturing only the apps would flip a
    /// manually hidden recents section back on (apply writes show-recents
    /// two-way).
    public func captureDock() -> (apps: [DockApp], hideRecents: Bool) {
        (capture(), !readShowRecents())
    }

    /// The apps and hide-recents state stored in a specific backup file
    /// ("Save as Profile"). `hideRecents` is `nil` for legacy backups that
    /// recorded only tiles.
    public func capturedDock(inBackupAt url: URL) throws -> (apps: [DockApp], hideRecents: Bool?) {
        let contents = try backupService.contents(at: url)
        return (apps(fromTiles: contents.tiles), contents.showRecents.map { !$0 })
    }

    /// Turns `persistent-apps` tiles into `DockApp`s - shared by capturing
    /// the live Dock and by converting a backup into a profile.
    func apps(fromTiles tiles: [[String: Any]]) -> [DockApp] {
        var apps: [DockApp] = []
        for tile in tiles {
            guard let tileData = tile["tile-data"] as? [String: Any],
                  let fileData = tileData["file-data"] as? [String: Any],
                  let urlString = fileData["_CFURLString"] as? String,
                  let url = URL(string: urlString),
                  url.isFileURL
            else { continue }
            let appURL = URL(fileURLWithPath: url.path, isDirectory: true)
            let installed = resolver.installedApp(at: appURL)
            apps.append(DockApp(name: installed.name, bundleID: installed.bundleID, path: appURL.path))
        }
        return apps
    }

    /// Restores the most recent backup (same write path as apply, but without
    /// creating a new backup).
    public func restoreLastBackup() throws {
        guard let contents = try backupService.latestContents() else {
            throw CleanDockError.noBackupAvailable
        }
        // Restores the recorded show-recents value; legacy backups without
        // one (nil) leave the preference untouched - restore must not
        // overwrite what the backup never recorded.
        try writeTilesAndRestart(contents.tiles, showRecents: contents.showRecents)
    }

    /// Restores a specific backup. The current Dock is snapshotted first, so
    /// an explicit restore from the backup list stays undoable.
    public func restoreBackup(at url: URL) throws {
        let contents = try backupService.contents(at: url)
        let currentTiles = try readPersistentAppsForBackup()
        try backupService.write(tiles: currentTiles, showRecents: readShowRecents())
        try writeTilesAndRestart(contents.tiles, showRecents: contents.showRecents)
    }

    // MARK: - CFPreferences plumbing

    /// The current `persistent-apps` array, or `nil` if unreadable.
    private func readPersistentApps() -> [[String: Any]]? {
        if let dockReader {
            return dockReader()
        }
        let value = CFPreferencesCopyAppValue(
            "persistent-apps" as CFString,
            Self.dockDomain as CFString
        )
        return value as? [[String: Any]]
    }

    /// Like `readPersistentApps`, but for the backup-before-write paths: a
    /// missing key is a legitimately empty Dock, while a present but
    /// untypeable value (a domain mangled by third-party tools) must abort -
    /// otherwise the backup would record an empty Dock exactly when the
    /// user's real Dock could not be read, and undo would "restore" nothing.
    private func readPersistentAppsForBackup() throws -> [[String: Any]] {
        if let dockReader {
            return dockReader() ?? []
        }
        guard let value = CFPreferencesCopyAppValue(
            "persistent-apps" as CFString,
            Self.dockDomain as CFString
        ) else {
            return []
        }
        guard let tiles = value as? [[String: Any]] else {
            throw CleanDockError.dockPreferencesUnreadable
        }
        return tiles
    }

    /// The effective `show-recents` value; a missing key means the system
    /// default (recents shown).
    private func readShowRecents() -> Bool {
        if let showRecentsReader {
            return showRecentsReader()
        }
        let value = CFPreferencesCopyAppValue(
            "show-recents" as CFString,
            Self.dockDomain as CFString
        )
        return value as? Bool ?? true
    }

    private func writeTilesAndRestart(_ tiles: [[String: Any]], showRecents: Bool?) throws {
        if let dockWriter {
            try dockWriter(tiles, showRecents)
            return
        }
        let domain = Self.dockDomain as CFString
        CFPreferencesSetAppValue("persistent-apps" as CFString, tiles as CFArray, domain)
        if let showRecents {
            CFPreferencesSetAppValue(
                "show-recents" as CFString,
                showRecents ? kCFBooleanTrue : kCFBooleanFalse,
                domain
            )
        }
        // Synchronize *before* restarting the Dock - non-negotiable.
        guard CFPreferencesAppSynchronize(domain) else {
            throw CleanDockError.preferencesSynchronizationFailed
        }
        restartDock()
    }

    /// Restarts the Dock so it picks up the new preferences. A short
    /// disappearance of the Dock is normal. A failing `killall` (e.g. Dock
    /// not running) is not an error - the Dock reads the preferences on its
    /// next launch anyway.
    private func restartDock() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // Non-fatal by design; see above.
        }
    }
}
