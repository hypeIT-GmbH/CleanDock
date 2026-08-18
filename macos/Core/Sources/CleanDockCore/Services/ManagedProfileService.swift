//
//  ManagedProfileService.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import CryptoKit
import Foundation
import os

/// A read-only profile deployed by an administrator (MDM).
public struct ManagedProfile: Identifiable, Sendable, Hashable {
    public let profile: Profile
    /// `false` opts a deployed profile out of automatic application.
    /// Missing in the JSON means `true` (the MDM export always writes the key explicitly).
    public let autoApply: Bool
    public let fileURL: URL
    /// SHA-256 over the raw file content - the idempotency key.
    public let contentHash: String

    /// The file path is the identity: unique even when two deployed files
    /// carry identical content (the hash would collide there and break
    /// SwiftUI list identity), and stable across re-reads.
    public var id: String { fileURL.path }

    public init(profile: Profile, autoApply: Bool, fileURL: URL, contentHash: String) {
        self.profile = profile
        self.autoApply = autoApply
        self.fileURL = fileURL
        self.contentHash = contentHash
    }

    /// Equality is deliberately file + content hash, NOT the decoded
    /// profile: `Profile` regenerates random UUIDs for id-less managed JSON
    /// on every decode, so two reads of the same unchanged file would
    /// otherwise compare unequal and churn `refresh()`'s change detection
    /// on every call. The hash covers everything the file contains.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.fileURL == rhs.fileURL && lhs.contentHash == rhs.contentHash
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(fileURL)
        hasher.combine(contentHash)
    }
}

/// Discovers managed profiles in `/Library/Application Support/CleanDock/managed/`
/// and tracks which ones have already been applied for the current user.
///
/// Idempotency: a marker file `<sha256>.done` per user and file content means
/// every managed profile is applied exactly once per user - and automatically
/// re-applied when MDM ships new content (new content = new hash). Users may
/// freely change their Dock afterwards.
public struct ManagedProfileService: Sendable {
    private static let logger = Logger(
        subsystem: CleanDockInfo.appBundleID,
        category: "ManagedProfileService"
    )

    public let managedDirectory: URL
    public let markerDirectory: URL

    public init(
        managedDirectory: URL = CleanDockPaths.managedProfilesDirectory,
        markerDirectory: URL = CleanDockPaths.managedAppliedMarkersDirectory
    ) {
        self.managedDirectory = managedDirectory
        self.markerDirectory = markerDirectory
    }

    /// All readable managed profiles, sorted by filename for a deterministic
    /// apply order. Unreadable or invalid files are skipped.
    public func list() -> [ManagedProfile] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: managedDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { managedProfile(at: $0) }
    }

    /// Reads and validates a single managed profile file. Failures are
    /// logged and skipped - a broken deployment must never take down the
    /// whole managed list.
    private func managedProfile(at url: URL) -> ManagedProfile? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            Self.logger.error("Skipping unreadable managed profile \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let decoder = JSONDecoder.cleanDock()
        let profile: Profile
        do {
            profile = try decoder.decode(Profile.self, from: data)
        } catch {
            Self.logger.error("Skipping invalid managed profile \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }

        struct AutoApplyProbe: Decodable {
            var autoApply: Bool?
        }
        let autoApply: Bool
        do {
            // Absent field → default true (plain profile exports auto-apply).
            autoApply = try decoder.decode(AutoApplyProbe.self, from: data).autoApply ?? true
        } catch {
            // A present but mistyped value ("false" as string, 0/1, …) must
            // not silently escalate a deploy-only profile into auto-apply.
            // Deploy-only is the safe reading; the log line points admins
            // at the typo.
            Self.logger.error("Managed profile \(url.lastPathComponent, privacy: .public) has an invalid autoApply value - treating it as deploy-only: \(error.localizedDescription, privacy: .public)")
            autoApply = false
        }
        return ManagedProfile(
            profile: profile,
            autoApply: autoApply,
            fileURL: url,
            contentHash: Self.hash(of: data)
        )
    }

    /// Managed profiles that opted into auto-apply and have not been applied
    /// for this user yet (per content hash).
    public func pending() -> [ManagedProfile] {
        list().filter { $0.autoApply && !isApplied($0) }
    }

    func isApplied(_ managedProfile: ManagedProfile) -> Bool {
        FileManager.default.fileExists(atPath: markerURL(for: managedProfile).path)
    }

    /// Writes the per-user "applied" marker for the profile's content hash.
    public func markApplied(_ managedProfile: ManagedProfile) throws {
        try FileManager.default.createDirectory(at: markerDirectory, withIntermediateDirectories: true)
        try Data().write(to: markerURL(for: managedProfile), options: .atomic)
    }

    private func markerURL(for managedProfile: ManagedProfile) -> URL {
        markerDirectory.appendingPathComponent("\(managedProfile.contentHash).done")
    }

    private static func hash(of data: Data) -> String {
        SHA256.hash(data: data).hexString
    }
}

/// Lowercase hex encoding for digest bytes - shared by the content-hash
/// idempotency markers and the managed-filename slugs.
extension Sequence where Element == UInt8 {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
