//
//  ProfileStoreTests.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import Foundation
import Testing
@testable import CleanDockCore

@Suite("ProfileStore")
@MainActor
struct ProfileStoreTests {
    @Test("Save/load roundtrip preserves profiles and app order")
    func roundtrip() throws {
        let temp = try TemporaryDirectory()
        let store = ProfileStore(directory: temp.url)
        var profile = Profile(name: "Standard Büro", symbol: "briefcase.fill", hideRecents: true)
        profile.apps = [
            DockApp(name: "Safari", bundleID: "com.apple.Safari", path: "/Applications/Safari.app"),
            DockApp(name: "Mail", bundleID: "com.apple.mail", path: "/System/Applications/Mail.app")
        ]
        store.add(profile)

        let reloaded = ProfileStore(directory: temp.url)
        #expect(reloaded.profiles.count == 1)
        let loaded = try #require(reloaded.profiles.first)
        #expect(loaded.id == profile.id)
        #expect(loaded.name == "Standard Büro")
        #expect(loaded.symbol == "briefcase.fill")
        #expect(loaded.hideRecents)
        #expect(loaded.apps.map(\.name) == ["Safari", "Mail"])
        #expect(loaded.apps.map(\.bundleID) == ["com.apple.Safari", "com.apple.mail"])
    }

    @Test("Externally added profiles survive the next GUI save (no last-writer-wins)")
    func externalWriterIsMerged() throws {
        let temp = try TemporaryDirectory()
        let store = ProfileStore(directory: temp.url)
        store.add(Profile(name: "Mine"))

        // A second store simulates `cleandock capture` writing the same
        // file from another process while the app is running.
        let cli = ProfileStore(directory: temp.url)
        cli.add(Profile(name: "Captured"))

        // The next GUI mutation must adopt the externally added profile
        // instead of overwriting the file with the stale in-memory state.
        store.rename(id: try #require(store.profiles.first?.id), to: "Mine Renamed")
        #expect(store.profiles.map(\.name).contains("Captured"))

        let reloaded = ProfileStore(directory: temp.url)
        #expect(Set(reloaded.profiles.map(\.name)) == ["Mine Renamed", "Captured"])
    }

    @Test("A newer-format file written externally is preserved, not overwritten")
    func externalNewerFormatIsPreserved() throws {
        let temp = try TemporaryDirectory()
        let store = ProfileStore(directory: temp.url)
        store.add(Profile(name: "Mine"))

        // A future CleanDock version rewrites the file as v2 while this
        // instance is still running.
        let v2 = Data(#"{"version": 2, "profiles": []}"#.utf8)
        try v2.write(to: temp.url.appendingPathComponent("profiles.json"))

        // The next mutation must NOT silently overwrite the newer data -
        // the same invariant load() enforces via preservation.
        store.add(Profile(name: "Second"))

        let preserved = try FileManager.default.contentsOfDirectory(atPath: temp.url.path)
            .filter { $0.hasPrefix("profiles.json.unsupported-version-") }
        #expect(preserved.count == 1)
        // The store's own state was still saved as v1 afterwards.
        let reloaded = ProfileStore(directory: temp.url)
        #expect(Set(reloaded.profiles.map(\.name)) == ["Mine", "Second"])
    }

    @Test("A read-only merge NEVER moves a newer-format file away")
    func readOnlyMergeLeavesNewerFormatInPlace() throws {
        let temp = try TemporaryDirectory()
        let store = ProfileStore(directory: temp.url)
        store.add(Profile(name: "Mine"))

        let fileURL = temp.url.appendingPathComponent("profiles.json")
        try Data(#"{"version": 2, "profiles": []}"#.utf8).write(to: fileURL)

        // refresh() calls this without a following save - moving the file
        // here would leave NO profiles.json behind until the next mutation.
        store.mergeExternalChanges()

        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        let preserved = try FileManager.default.contentsOfDirectory(atPath: temp.url.path)
            .filter { $0.hasPrefix("profiles.json.unsupported-version-") }
        #expect(preserved.isEmpty)

        // The save() path afterwards must still detect and preserve it.
        store.add(Profile(name: "Second"))
        let preservedAfterSave = try FileManager.default.contentsOfDirectory(atPath: temp.url.path)
            .filter { $0.hasPrefix("profiles.json.unsupported-version-") }
        #expect(preservedAfterSave.count == 1)
    }

    @Test("File format contains version wrapper")
    func fileFormat() throws {
        let temp = try TemporaryDirectory()
        let store = ProfileStore(directory: temp.url)
        store.createProfile(named: "Test")
        let data = try Data(contentsOf: store.fileURL)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["version"] as? Int == 1)
        #expect((object["profiles"] as? [[String: Any]])?.count == 1)
    }

    @Test("Corrupt file is preserved as .corrupt backup and store starts empty")
    func corruptFile() throws {
        let temp = try TemporaryDirectory()
        let fileURL = temp.url.appendingPathComponent("profiles.json")
        try Data("this is not json {{{".utf8).write(to: fileURL)

        let store = ProfileStore(directory: temp.url)
        #expect(store.profiles.isEmpty)

        let contents = try FileManager.default.contentsOfDirectory(atPath: temp.url.path)
        #expect(contents.contains { $0.hasPrefix("profiles.json.corrupt-") })

        // The store must be fully usable afterwards.
        store.createProfile(named: "Fresh")
        #expect(ProfileStore(directory: temp.url).profiles.count == 1)
    }

    @Test("A newer format version is preserved and never re-saved as version 1")
    func newerFormatVersionPreserved() throws {
        let temp = try TemporaryDirectory()
        let fileURL = temp.url.appendingPathComponent("profiles.json")
        try Data(#"{"version": 2, "profiles": []}"#.utf8).write(to: fileURL)

        let store = ProfileStore(directory: temp.url)
        #expect(store.profiles.isEmpty)

        // The newer file must be moved aside, not silently downgraded.
        let contents = try FileManager.default.contentsOfDirectory(atPath: temp.url.path)
        #expect(contents.contains { $0.hasPrefix("profiles.json.unsupported-version-") })
        #expect(!contents.contains("profiles.json"))
    }

    @Test("A failed save surfaces in lastSaveError, a successful one clears it")
    func saveErrorIsObservable() throws {
        let temp = try TemporaryDirectory()
        // A regular file where the store expects its directory makes every
        // write fail, regardless of privileges.
        let blockedDirectory = temp.url.appendingPathComponent("blocked")
        try Data().write(to: blockedDirectory)

        let blockedStore = ProfileStore(directory: blockedDirectory)
        blockedStore.createProfile(named: "Doomed")
        #expect(blockedStore.lastSaveError != nil)

        let store = ProfileStore(directory: temp.url)
        store.createProfile(named: "Fine")
        #expect(store.lastSaveError == nil)
    }

    @Test("Duplicate regenerates IDs and appends counter to the name")
    func duplicate() throws {
        let temp = try TemporaryDirectory()
        let store = ProfileStore(directory: temp.url)
        var profile = Profile(name: "Büro")
        profile.apps = [DockApp(name: "Safari")]
        store.add(profile)

        let copy = try #require(store.duplicate(id: profile.id))
        #expect(copy.name == "Büro (2)")
        #expect(copy.id != profile.id)
        #expect(copy.apps.first?.id != profile.apps.first?.id)
        #expect(copy.apps.first?.name == "Safari")

        let second = try #require(store.duplicate(id: profile.id))
        #expect(second.name == "Büro (3)")
    }

    @Test("Import assigns fresh UUIDs and resolves name collisions")
    func importProfile() throws {
        let temp = try TemporaryDirectory()
        let store = ProfileStore(directory: temp.url)
        let original = store.createProfile(named: "Standard")

        var incoming = Profile(name: "Standard")
        incoming.apps = [DockApp(name: "Mail")]
        let imported = store.importProfile(incoming)
        #expect(imported.name == "Standard (2)")
        #expect(imported.id != original.id)
        #expect(imported.id != incoming.id)
    }

    @Test("Rename enforces unique names")
    func renameUnique() throws {
        let temp = try TemporaryDirectory()
        let store = ProfileStore(directory: temp.url)
        store.createProfile(named: "A")
        let b = store.createProfile(named: "B")
        store.rename(id: b.id, to: "A")
        #expect(store.profile(withID: b.id)?.name == "A (2)")
    }

    @Test("Delete removes and persists")
    func delete() throws {
        let temp = try TemporaryDirectory()
        let store = ProfileStore(directory: temp.url)
        let profile = store.createProfile(named: "Gone")
        store.delete(id: profile.id)
        #expect(store.profiles.isEmpty)
        #expect(ProfileStore(directory: temp.url).profiles.isEmpty)
    }
}
