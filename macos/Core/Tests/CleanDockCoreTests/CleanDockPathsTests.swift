//
//  CleanDockPathsTests.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import Foundation
import Testing
@testable import CleanDockCore

@Suite("CleanDockPaths")
struct CleanDockPathsTests {
    private let fileManager = FileManager.default

    @discardableResult
    private func makeDirectory(_ name: String, marker: String, in base: URL) throws -> URL {
        let directory = base.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(marker.utf8).write(to: directory.appendingPathComponent("\(marker).txt"))
        return directory
    }

    @Test("Legacy directory is moved when the target does not exist")
    func migratesLegacyDirectory() throws {
        let temp = try TemporaryDirectory()
        let legacy = try makeDirectory("Dock Cleanup", marker: "legacy", in: temp.url)

        CleanDockPaths.migrateLegacySupportDirectoryIfNeeded(in: temp.url)

        let target = temp.url.appendingPathComponent("CleanDock", isDirectory: true)
        #expect(!fileManager.fileExists(atPath: legacy.path))
        #expect(fileManager.fileExists(atPath: target.appendingPathComponent("legacy.txt").path))
    }

    @Test("Existing target directory is left untouched")
    func keepsExistingTarget() throws {
        let temp = try TemporaryDirectory()
        let legacy = try makeDirectory("Dock Cleanup", marker: "legacy", in: temp.url)
        let target = try makeDirectory("CleanDock", marker: "current", in: temp.url)

        CleanDockPaths.migrateLegacySupportDirectoryIfNeeded(in: temp.url)

        #expect(fileManager.fileExists(atPath: legacy.appendingPathComponent("legacy.txt").path))
        #expect(fileManager.fileExists(atPath: target.appendingPathComponent("current.txt").path))
        #expect(!fileManager.fileExists(atPath: target.appendingPathComponent("legacy.txt").path))
    }

    @Test("Missing legacy directory is a no-op")
    func missingLegacyDirectory() throws {
        let temp = try TemporaryDirectory()

        CleanDockPaths.migrateLegacySupportDirectoryIfNeeded(in: temp.url)

        let target = temp.url.appendingPathComponent("CleanDock", isDirectory: true)
        #expect(!fileManager.fileExists(atPath: target.path))
    }

    @Test("The pre-1.0 \"Clean Dock\" directory migrates too")
    func migratesCleanDockWithSpace() throws {
        let temp = try TemporaryDirectory()
        let legacy = try makeDirectory("Clean Dock", marker: "spaced", in: temp.url)

        CleanDockPaths.migrateLegacySupportDirectoryIfNeeded(in: temp.url)

        let target = temp.url.appendingPathComponent("CleanDock", isDirectory: true)
        #expect(!fileManager.fileExists(atPath: legacy.path))
        #expect(fileManager.fileExists(atPath: target.appendingPathComponent("spaced.txt").path))
    }

    @Test("The most recent legacy NAME (Clean Dock) wins, independent of timestamps")
    func mostRecentLegacyNameWins() throws {
        let temp = try TemporaryDirectory()
        try makeDirectory("Dock Cleanup", marker: "oldest", in: temp.url)
        try makeDirectory("Clean Dock", marker: "newer", in: temp.url)

        CleanDockPaths.migrateLegacySupportDirectoryIfNeeded(in: temp.url)

        let target = temp.url.appendingPathComponent("CleanDock", isDirectory: true)
        #expect(fileManager.fileExists(atPath: target.appendingPathComponent("newer.txt").path))
        #expect(!fileManager.fileExists(atPath: target.appendingPathComponent("oldest.txt").path))
    }
}
