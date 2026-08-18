//
//  DockServiceTests.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import Foundation
import Testing
@testable import CleanDockCore

@Suite("DockService")
struct DockServiceTests {
    @Test("Tile dictionary uses file URL with trailing slash and type 15")
    func tileFormat() throws {
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        let tile = DockService.tile(forAppAt: url)

        #expect(tile["tile-type"] as? String == "file-tile")
        let tileData = try #require(tile["tile-data"] as? [String: Any])
        let fileData = try #require(tileData["file-data"] as? [String: Any])
        #expect(fileData["_CFURLString"] as? String == "file:///Applications/Safari.app/")
        #expect(fileData["_CFURLStringType"] as? Int == 15)
    }

    @Test("Tile URL percent-encodes spaces")
    func tilePercentEncoding() throws {
        let url = URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
        let tile = DockService.tile(forAppAt: url)
        let tileData = try #require(tile["tile-data"] as? [String: Any])
        let fileData = try #require(tileData["file-data"] as? [String: Any])
        #expect(fileData["_CFURLString"] as? String == "file:///Applications/Visual%20Studio%20Code.app/")
    }

    @Test("resolveApps splits into resolved (in order) and skipped")
    func resolveSplit() throws {
        let temp = try TemporaryDirectory()
        let safari = try temp.makeFakeApp(named: "Safari")
        let mail = try temp.makeFakeApp(named: "Mail")
        let resolver = AppResolver(searchDirectories: [temp.url], bundleIDLookup: { _ in nil })
        let service = DockService(
            resolver: resolver,
            backupService: BackupService(directory: try temp.subdirectory("backups"))
        )
        let profile = Profile(name: "Test", apps: [
            DockApp(name: "Safari"),
            DockApp(name: "Ghost App"),
            DockApp(name: "Mail")
        ])
        let (resolved, skipped) = service.resolveApps(of: profile)
        #expect(resolved.map(\.url.path) == [safari.path, mail.path])
        #expect(skipped.map(\.name) == ["Ghost App"])
    }

    @Test("apply builds tiles in profile order, skips silently and writes a backup")
    func applyWithInjectedWriter() throws {
        let temp = try TemporaryDirectory()
        try temp.makeFakeApp(named: "Safari")
        try temp.makeFakeApp(named: "Mail")
        let backupDirectory = try temp.subdirectory("backups")
        let resolver = AppResolver(searchDirectories: [temp.url], bundleIDLookup: { _ in nil })

        let captured = DockWriteCapture()
        let service = DockService(
            resolver: resolver,
            backupService: BackupService(directory: backupDirectory),
            dockWriter: { tiles, showRecents in
                captured.tiles = tiles
                captured.showRecents = showRecents
            }
        )

        let profile = Profile(name: "Test", apps: [
            DockApp(name: "Mail"),
            DockApp(name: "Missing"),
            DockApp(name: "Safari")
        ], hideRecents: true)

        let result = try service.apply(profile)
        #expect(result.applied.map(\.name) == ["Mail", "Safari"])
        #expect(result.skipped.map(\.name) == ["Missing"])
        #expect(captured.showRecents == false)
        let urls = captured.tiles.compactMap {
            (($0["tile-data"] as? [String: Any])?["file-data"] as? [String: Any])?["_CFURLString"] as? String
        }
        #expect(urls.count == 2)
        #expect(urls[0].hasSuffix("/Mail.app/"))
        #expect(urls[1].hasSuffix("/Safari.app/"))

        // A backup of the previous Dock state must exist.
        #expect(BackupService(directory: backupDirectory).hasBackups)
    }

    @Test("capture parses persistent-apps tiles, skipping malformed and non-file entries")
    func captureParsesTiles() throws {
        let temp = try TemporaryDirectory()
        let safari = try temp.makeFakeApp(named: "Safari")

        final class TileBox: @unchecked Sendable {
            let tiles: [[String: Any]]
            init(_ tiles: [[String: Any]]) { self.tiles = tiles }
        }
        let box = TileBox([
            DockService.tile(forAppAt: safari),
            // Malformed tile without file data.
            ["tile-type": "file-tile"],
            // Non-file URL must be ignored.
            [
                "tile-data": [
                    "file-data": [
                        "_CFURLString": "https://example.com/",
                        "_CFURLStringType": 15
                    ]
                ],
                "tile-type": "file-tile"
            ]
        ])
        let service = DockService(
            resolver: AppResolver(searchDirectories: [temp.url], bundleIDLookup: { _ in nil }),
            backupService: BackupService(directory: try temp.subdirectory("backups")),
            dockReader: { box.tiles }
        )

        let apps = service.capture()
        #expect(apps.map(\.name) == ["Safari"])
        #expect(apps.first?.path == safari.path)
    }

    @Test("captureDock mirrors the current hide-recents state into the profile")
    func captureDockIncludesHideRecents() throws {
        let temp = try TemporaryDirectory()
        // The user has recents hidden system-wide: the adopted profile must
        // carry hideRecents=true, otherwise applying it (two-way write)
        // would flip the recents section back on.
        let hidden = DockService(
            resolver: AppResolver(searchDirectories: [temp.url], bundleIDLookup: { _ in nil }),
            backupService: BackupService(directory: try temp.subdirectory("b1")),
            dockReader: { [] },
            showRecentsReader: { false }
        )
        #expect(hidden.captureDock().hideRecents)

        let shown = DockService(
            resolver: AppResolver(searchDirectories: [temp.url], bundleIDLookup: { _ in nil }),
            backupService: BackupService(directory: try temp.subdirectory("b2")),
            dockReader: { [] },
            showRecentsReader: { true }
        )
        #expect(!shown.captureDock().hideRecents)
    }

    @Test("capturedDock(inBackupAt:) surfaces the recorded recents state")
    func capturedDockFromBackup() throws {
        let temp = try TemporaryDirectory()
        let backupService = BackupService(directory: try temp.subdirectory("backups"))
        let service = DockService(
            resolver: AppResolver(searchDirectories: [], bundleIDLookup: { _ in nil }),
            backupService: backupService,
            dockWriter: { _, _ in }
        )
        let recorded = try backupService.write(tiles: [], showRecents: false)
        let legacy = try backupService.write(tiles: [])
        #expect(try service.capturedDock(inBackupAt: recorded).hideRecents == true)
        #expect(try service.capturedDock(inBackupAt: legacy).hideRecents == nil)
    }

    @Test("restoreLastBackup replays the latest backup through the writer")
    func restoreReplaysLatestBackup() throws {
        let temp = try TemporaryDirectory()
        let backupService = BackupService(directory: try temp.subdirectory("backups"))
        try backupService.write(tiles: [["index": 1]])
        try backupService.write(tiles: [["index": 2]])

        let captured = DockWriteCapture(showRecents: false)
        let service = DockService(
            resolver: AppResolver(searchDirectories: [], bundleIDLookup: { _ in nil }),
            backupService: backupService,
            dockWriter: { tiles, showRecents in
                captured.tiles = tiles
                captured.showRecents = showRecents
            }
        )

        try service.restoreLastBackup()
        #expect(captured.tiles.first?["index"] as? Int == 2)
        // A legacy backup without a recorded show-recents value must leave
        // the preference untouched.
        #expect(captured.showRecents == Bool??.some(nil))
    }

    @Test("restore puts a recorded show-recents value back")
    func restoreRestoresShowRecents() throws {
        let temp = try TemporaryDirectory()
        let backupService = BackupService(directory: try temp.subdirectory("backups"))
        try backupService.write(tiles: [["index": 7]], showRecents: false)

        let captured = DockWriteCapture()
        let service = DockService(
            resolver: AppResolver(searchDirectories: [], bundleIDLookup: { _ in nil }),
            backupService: backupService,
            dockWriter: { _, showRecents in captured.showRecents = showRecents }
        )

        try service.restoreLastBackup()
        // Undo must be symmetric to the two-way apply: the user's
        // show-recents state from before the cleanup comes back.
        #expect(captured.showRecents == false)
    }

    @Test("apply records the current show-recents value in the backup")
    func applyRecordsShowRecents() throws {
        let temp = try TemporaryDirectory()
        try temp.makeFakeApp(named: "Safari")
        let backupService = BackupService(directory: try temp.subdirectory("backups"))
        let service = DockService(
            resolver: AppResolver(searchDirectories: [temp.url], bundleIDLookup: { _ in nil }),
            backupService: backupService,
            dockWriter: { _, _ in },
            showRecentsReader: { false }
        )

        try service.apply(Profile(name: "Test", apps: [DockApp(name: "Safari")]))
        let contents = try #require(try backupService.latestContents())
        #expect(contents.showRecents == false)
    }

    @Test("apply with backingUp false writes no backup")
    func applySkipsBackupOnDemand() throws {
        let temp = try TemporaryDirectory()
        try temp.makeFakeApp(named: "Safari")
        let backupService = BackupService(directory: try temp.subdirectory("backups"))
        let service = DockService(
            resolver: AppResolver(searchDirectories: [temp.url], bundleIDLookup: { _ in nil }),
            backupService: backupService,
            dockWriter: { _, _ in }
        )

        try service.apply(Profile(name: "Test", apps: [DockApp(name: "Safari")]), backingUp: false)
        #expect(!backupService.hasBackups)
    }

    @Test("apply with hideRecents off explicitly re-enables show-recents")
    func applyReenablesShowRecents() throws {
        let temp = try TemporaryDirectory()
        try temp.makeFakeApp(named: "Safari")
        let resolver = AppResolver(searchDirectories: [temp.url], bundleIDLookup: { _ in nil })

        let captured = DockWriteCapture()
        let service = DockService(
            resolver: resolver,
            backupService: BackupService(directory: try temp.subdirectory("backups")),
            dockWriter: { _, showRecents in captured.showRecents = showRecents }
        )

        // The switch must be two-way: turning it off and re-applying has to
        // bring the recents section back.
        try service.apply(Profile(name: "Test", apps: [DockApp(name: "Safari")], hideRecents: false))
        #expect(captured.showRecents == true)
    }

    @Test("restoreLastBackup without a backup throws noBackupAvailable")
    func restoreWithoutBackup() throws {
        let temp = try TemporaryDirectory()
        let service = DockService(
            resolver: AppResolver(searchDirectories: [], bundleIDLookup: { _ in nil }),
            backupService: BackupService(directory: try temp.subdirectory("backups")),
            dockWriter: { _, _ in }
        )
        #expect(throws: CleanDockError.noBackupAvailable) {
            try service.restoreLastBackup()
        }
    }

    @Test("restoreBackup(at:) replays that backup and snapshots the current Dock first")
    func restoreSpecificBackup() throws {
        let temp = try TemporaryDirectory()
        let backupService = BackupService(directory: try temp.subdirectory("backups"))
        let oldBackupURL = try backupService.write(tiles: [["index": 1]])
        try backupService.write(tiles: [["index": 2]])

        let captured = DockWriteCapture(showRecents: false)
        let service = DockService(
            resolver: AppResolver(searchDirectories: [], bundleIDLookup: { _ in nil }),
            backupService: backupService,
            dockWriter: { tiles, showRecents in
                captured.tiles = tiles
                captured.showRecents = showRecents
            },
            dockReader: { [["index": 99]] }
        )

        try service.restoreBackup(at: oldBackupURL)

        // The selected (older) backup was written to the Dock …
        #expect(captured.tiles.first?["index"] as? Int == 1)
        // … without a recorded show-recents value (legacy backup) the
        // preference stays untouched …
        #expect(captured.showRecents == Bool??.some(nil))
        // … and the pre-restore Dock became the newest backup, keeping the
        // restore itself undoable.
        let newest = try #require(try backupService.latestContents()).tiles
        #expect(newest.first?["index"] as? Int == 99)
        #expect(backupService.backups().count == 3)
    }

    @Test("capturedDock(inBackupAt:) turns stored tiles into DockApps")
    func appsFromBackup() throws {
        let temp = try TemporaryDirectory()
        let safari = try temp.makeFakeApp(named: "Safari")
        let backupService = BackupService(directory: try temp.subdirectory("backups"))
        let backupURL = try backupService.write(tiles: [
            [
                "tile-type": "file-tile",
                "tile-data": [
                    "file-data": [
                        "_CFURLString": "file://\(safari.path)/",
                        "_CFURLStringType": 15
                    ]
                ]
            ]
        ])
        let service = DockService(
            resolver: AppResolver(searchDirectories: [temp.url], bundleIDLookup: { _ in nil }),
            backupService: backupService,
            dockWriter: { _, _ in }
        )

        let apps = try service.capturedDock(inBackupAt: backupURL).apps
        #expect(apps.map(\.name) == ["Safari"])
        #expect(apps.first?.path == safari.path)
    }
}
