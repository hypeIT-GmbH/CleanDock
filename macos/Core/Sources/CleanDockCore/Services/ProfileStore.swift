//
//  ProfileStore.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import Foundation
import Observation
import os

/// Loads and saves the user's profiles atomically and publishes them for the
/// GUI and the menu bar extra, which share one instance.
///
/// Storage: `~/Library/Application Support/CleanDock/profiles.json`.
/// A corrupt file is preserved as `.corrupt-<timestamp>` (a file with a newer
/// format version as `.unsupported-version-<timestamp>`) and the store starts
/// empty instead of crashing or silently overwriting user data.
@MainActor
@Observable
public final class ProfileStore {
    public private(set) var profiles: [Profile] = []
    public let fileURL: URL

    /// The error of the most recent save, or `nil` once a save succeeds.
    /// The mutating methods deliberately stay non-throwing - the
    /// `@Observable` UI calls them directly from actions - so a failed write
    /// surfaces here instead of via `throws`; callers that must report
    /// persistence failures (CLI, alerts) check it right after mutating.
    public private(set) var lastSaveError: (any Error)?

    @ObservationIgnored
    private let logger = Logger(subsystem: CleanDockInfo.appBundleID, category: "ProfileStore")

    /// Modification token of the file state this store last read or wrote.
    /// Used to detect external writers (the CLI) before overwriting the file.
    @ObservationIgnored
    private var lastKnownFileToken: FileToken?

    private struct FileToken: Equatable {
        var modificationDate: Date
        var size: Int
    }

    private struct ProfilesFile: Codable {
        var version: Int
        var profiles: [Profile]
    }

    public init(directory: URL = CleanDockPaths.userSupportDirectory) {
        self.fileURL = directory.appendingPathComponent("profiles.json")
        load()
        lastKnownFileToken = currentFileToken()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            profiles = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let file = try JSONDecoder.cleanDock().decode(ProfilesFile.self, from: data)
            guard file.version <= ProfileFileFormat.version else {
                // Data written by a newer format must never be re-saved as
                // version 1 - preserve the file and start empty instead.
                logger.error("profiles.json has newer format version \(file.version), starting empty")
                preserveFile(suffix: "unsupported-version")
                profiles = []
                return
            }
            profiles = file.profiles
        } catch {
            logger.error("profiles.json is corrupt, starting empty: \(error.localizedDescription)")
            preserveFile(suffix: "corrupt")
            profiles = []
        }
    }

    private func preserveFile(suffix: String) {
        let preservedURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("profiles.json.\(suffix)-\(FilenameTimestamp.stamp())")
        try? FileManager.default.moveItem(at: fileURL, to: preservedURL)
    }

    private func save() {
        mergeExternalChanges(preservingNewerFormat: true)
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder.cleanDock()
            let data = try encoder.encode(ProfilesFile(version: ProfileFileFormat.version, profiles: profiles))
            try data.write(to: fileURL, options: .atomic)
            lastSaveError = nil
            lastKnownFileToken = currentFileToken()
        } catch {
            lastSaveError = error
            logger.error("Failed to save profiles: \(error.localizedDescription)")
        }
    }

    /// The CLI writes profiles.json from a second process; writing blindly
    /// would make the last writer win and silently drop e.g. a profile
    /// captured via `cleandock capture` while the app is open. Detects an
    /// external change via the file's modification token and adopts
    /// externally added profiles before this store's state hits the disk.
    /// For profiles both sides know, the in-memory state wins.
    ///
    /// Deliberately lock-free best effort: micro-windows remain in which a
    /// write landing between merge and save (or between save and the token
    /// read) is lost. Guarding them would need file coordination across
    /// processes - out of proportion for the human-triggered CLI scenario
    /// this protects.
    ///
    /// `preservingNewerFormat` is true only on the save() path: there, a
    /// file written by a newer format version must be moved aside before it
    /// is overwritten with v1 data. Read-only callers (refresh) pass false -
    /// moving the file WITHOUT a following save would leave no profiles.json
    /// behind at all.
    public func mergeExternalChanges(preservingNewerFormat: Bool = false) {
        let token = currentFileToken()
        guard token != lastKnownFileToken else { return }
        guard
            let data = try? Data(contentsOf: fileURL),
            let file = try? JSONDecoder.cleanDock().decode(ProfilesFile.self, from: data)
        else {
            lastKnownFileToken = token
            return
        }
        guard file.version <= ProfileFileFormat.version else {
            // Same invariant as load(): data written by a newer format must
            // never be overwritten as version 1. Only the save() path may
            // preserve (move) the file - it writes fresh v1 right after.
            if preservingNewerFormat {
                logger.error("profiles.json was rewritten by a newer format (version \(file.version)) - preserving it")
                preserveFile(suffix: "unsupported-version")
                lastKnownFileToken = currentFileToken()
            }
            return
        }
        lastKnownFileToken = token
        let knownIDs = Set(profiles.map(\.id))
        let external = file.profiles.filter { !knownIDs.contains($0.id) }
        guard !external.isEmpty else { return }
        logger.notice("Adopting \(external.count) externally added profile(s) from profiles.json")
        for var profile in external {
            // Adopted profiles must honor the store's unique-name invariant:
            // the CLI uniquified against the file, not against unsaved
            // in-memory state - a collision would make the name-based CLI
            // lookup non-deterministic.
            profile.name = uniqueName(for: profile.name, excluding: profile.id)
            profiles.append(profile)
        }
    }

    private func currentFileToken() -> FileToken? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path) else {
            return nil
        }
        return FileToken(
            modificationDate: (attributes[.modificationDate] as? Date) ?? .distantPast,
            size: (attributes[.size] as? NSNumber)?.intValue ?? 0
        )
    }

    // MARK: - Lookup

    public func profile(withID id: UUID) -> Profile? {
        profiles.first { $0.id == id }
    }

    public func profile(named name: String) -> Profile? {
        profiles.first { $0.name == name }
            ?? profiles.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    // MARK: - Mutations (all persist immediately)

    @discardableResult
    public func add(_ profile: Profile) -> Profile {
        var profile = profile
        profile.name = uniqueName(for: profile.name, excluding: profile.id)
        profiles.append(profile)
        save()
        return profile
    }

    @discardableResult
    public func createProfile(named name: String, symbol: String = Profile.defaultSymbol) -> Profile {
        add(Profile(name: name, symbol: symbol))
    }

    /// Replaces the stored profile with the same `id` and stamps `updatedAt`.
    public func update(_ profile: Profile, touchDate: Bool = true) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        var profile = profile
        if touchDate {
            profile.updatedAt = Date()
        }
        profiles[index] = profile
        save()
    }

    public func rename(id: UUID, to newName: String) {
        guard var profile = profile(withID: id) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != profile.name else { return }
        profile.name = uniqueName(for: trimmed, excluding: id)
        update(profile)
    }

    @discardableResult
    public func duplicate(id: UUID) -> Profile? {
        guard let original = profile(withID: id),
              let index = profiles.firstIndex(where: { $0.id == id })
        else { return nil }
        var copy = original.withRegeneratedIDs()
        copy.name = uniqueName(for: original.name, excluding: copy.id)
        let now = Date()
        copy.createdAt = now
        copy.updatedAt = now
        profiles.insert(copy, at: index + 1)
        save()
        return copy
    }

    public func delete(id: UUID) {
        profiles.removeAll { $0.id == id }
        save()
    }

    /// Imports a profile (JSON import / drag & drop): fresh UUIDs and a
    /// collision-free name ("Name (2)", "Name (3)", …).
    @discardableResult
    public func importProfile(_ profile: Profile) -> Profile {
        var copy = profile.withRegeneratedIDs()
        let now = Date()
        copy.createdAt = now
        copy.updatedAt = now
        return add(copy)
    }

    /// Returns `base` if free, otherwise "base (2)", "base (3)", …
    private func uniqueName(for base: String, excluding excludedID: UUID? = nil) -> String {
        let taken = Set(profiles.filter { $0.id != excludedID }.map(\.name))
        guard taken.contains(base) else { return base }
        var counter = 2
        while taken.contains("\(base) (\(counter))") {
            counter += 1
        }
        return "\(base) (\(counter))"
    }
}
