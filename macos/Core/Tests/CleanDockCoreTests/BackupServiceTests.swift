//
//  BackupServiceTests.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import Foundation
import Testing
@testable import CleanDockCore

@Suite("BackupService")
struct BackupServiceTests {
    @Test("Write/read roundtrip preserves tiles including binary data")
    func roundtrip() throws {
        let temp = try TemporaryDirectory()
        let service = BackupService(directory: temp.url)
        let tiles: [[String: Any]] = [
            [
                "tile-type": "file-tile",
                "tile-data": [
                    "file-data": [
                        "_CFURLString": "file:///Applications/Safari.app/",
                        "_CFURLStringType": 15
                    ],
                    "book": Data([0x01, 0x02, 0xFF]),
                    "file-label": "Safari",
                    "file-mod-date": Date(timeIntervalSince1970: 1_700_000_000.25)
                ]
            ]
        ]
        try service.write(tiles: tiles)
        let restored = try #require(try service.latestContents()).tiles
        #expect(restored.count == 1)
        let tileData = try #require(restored[0]["tile-data"] as? [String: Any])
        #expect(tileData["book"] as? Data == Data([0x01, 0x02, 0xFF]))
        #expect(tileData["file-label"] as? String == "Safari")
        // Dates must survive the $date roundtrip exactly (sub-second
        // precision included) - a formatter regression here would silently
        // alter restored Docks.
        #expect(tileData["file-mod-date"] as? Date == Date(timeIntervalSince1970: 1_700_000_000.25))
        let fileData = try #require(tileData["file-data"] as? [String: Any])
        #expect(fileData["_CFURLString"] as? String == "file:///Applications/Safari.app/")
        #expect(fileData["_CFURLStringType"] as? Int == 15)
    }

    @Test("At most 10 backups are kept; the oldest are pruned")
    func pruning() throws {
        let temp = try TemporaryDirectory()
        let service = BackupService(directory: temp.url)
        for index in 0..<13 {
            try service.write(tiles: [["index": index]])
        }
        let backups = service.backups()
        #expect(backups.count == BackupService.maxBackups)
        // The newest backup must be the last one written.
        let newest = try #require(try service.latestContents()).tiles
        #expect(newest.first?["index"] as? Int == 12)
    }

    @Test("latestContents is nil without backups")
    func emptyDirectory() throws {
        let temp = try TemporaryDirectory()
        let service = BackupService(directory: temp.url)
        #expect(try service.latestContents() == nil)
        #expect(!service.hasBackups)
    }

    @Test("show-recents roundtrips; omitting it reads back as nil")
    func showRecentsRoundtrip() throws {
        let temp = try TemporaryDirectory()
        let service = BackupService(directory: temp.url)
        let withValue = try service.write(tiles: [["index": 1]], showRecents: false)
        let withoutValue = try service.write(tiles: [["index": 2]])
        #expect(try service.contents(at: withValue).showRecents == false)
        #expect(try service.contents(at: withoutValue).showRecents == nil)
    }

    @Test("An empty legacy backup ([]) reads as zero tiles, showRecents nil")
    func emptyLegacyArrayFormat() throws {
        let temp = try TemporaryDirectory()
        let service = BackupService(directory: temp.url)
        // Pre-wrapper backup of an empty Dock - the [Any]→[[String: Any]]
        // downcast on an empty array is exactly the edge a refactor could
        // silently break.
        let url = temp.url.appendingPathComponent("2020-01-01T00-00-01.000Z.json")
        try Data("[]".utf8).write(to: url)
        let contents = try service.contents(at: url)
        #expect(contents.tiles.isEmpty)
        #expect(contents.showRecents == nil)
    }

    @Test("Legacy backups (plain tile array) stay readable, showRecents nil")
    func legacyArrayFormat() throws {
        let temp = try TemporaryDirectory()
        let service = BackupService(directory: temp.url)
        // The pre-1.0 format: the tile array at the root, no wrapper object.
        let legacy = try JSONSerialization.data(withJSONObject: [["index": 41]])
        let url = temp.url.appendingPathComponent("2020-01-01T00-00-00.000Z.json")
        try legacy.write(to: url)
        let contents = try service.contents(at: url)
        #expect(contents.tiles.first?["index"] as? Int == 41)
        #expect(contents.showRecents == nil)
    }

    @Test("backupInfos reports app counts newest first and skips broken files")
    func backupInfos() throws {
        let temp = try TemporaryDirectory()
        let service = BackupService(directory: temp.url)
        try service.write(tiles: [["tile-type": "file-tile"]])
        try service.write(tiles: [["tile-type": "file-tile"], ["tile-type": "file-tile"]])
        try Data("not json".utf8).write(to: temp.url.appendingPathComponent("zz-broken.json"))

        let infos = service.backupInfos()
        #expect(infos.map(\.appCount) == [2, 1])
        #expect(infos.allSatisfy { $0.date != .distantPast })
    }

    @Test("removeAll clears the directory")
    func removeAll() throws {
        let temp = try TemporaryDirectory()
        let service = BackupService(directory: temp.url)
        try service.write(tiles: [["a": 1]])
        try service.write(tiles: [["a": 2]])
        try service.removeAll()
        #expect(!service.hasBackups)
    }
}
