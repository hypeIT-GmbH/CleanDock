//
//  CleanDockInfo.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import Foundation
import os

/// Central product constants shared by the app and the CLI.
public enum CleanDockInfo {
    /// Keep in sync with `MARKETING_VERSION` in `project.yml`.
    public static let version = "1.0.0"
    public static let appBundleID = "de.hypeit.cleandock"

    /// Numeric, component-wise comparison of dotted version strings:
    /// "1.0.10" is newer than "1.0.9", missing components count as 0.
    /// Non-numeric components also count as 0 - pre-release tags are not
    /// part of this product's versioning scheme.
    public static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let lhs = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right {
                return left > right
            }
        }
        return false
    }
}

/// Well-known filesystem locations used across the product.
public enum CleanDockPaths {
    private static let logger = Logger(
        subsystem: CleanDockInfo.appBundleID,
        category: "CleanDockPaths"
    )

    /// `~/Library/Application Support/CleanDock`
    public static var userSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CleanDock", isDirectory: true)
    }

    /// One-time migration from the pre-release support directories - the app
    /// was named "Dock Cleanup" and then "Clean Dock" before 1.0. When
    /// several exist, the fixed name order below decides: "Clean Dock" (the
    /// most recent pre-release name) wins over "Dock Cleanup", regardless of
    /// directory timestamps. A failed move is logged but never fatal - the
    /// app then simply starts with a fresh directory.
    public static func migrateLegacySupportDirectoryIfNeeded(
        in baseDirectory: URL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    ) {
        let fileManager = FileManager.default
        let target = baseDirectory.appendingPathComponent("CleanDock", isDirectory: true)
        guard !fileManager.fileExists(atPath: target.path) else { return }
        for legacyName in ["Clean Dock", "Dock Cleanup"] {
            let legacy = baseDirectory.appendingPathComponent(legacyName, isDirectory: true)
            guard fileManager.fileExists(atPath: legacy.path) else { continue }
            do {
                try fileManager.moveItem(at: legacy, to: target)
            } catch {
                logger.error("Failed to migrate legacy support directory: \(error.localizedDescription)")
            }
            return
        }
    }

    /// `~/Library/Application Support/CleanDock/backups`
    public static var backupsDirectory: URL {
        userSupportDirectory.appendingPathComponent("backups", isDirectory: true)
    }

    /// `/Library/Application Support/CleanDock/managed`
    public static var managedProfilesDirectory: URL {
        URL(fileURLWithPath: "/Library/Application Support/CleanDock/managed", isDirectory: true)
    }

    /// `~/Library/Application Support/CleanDock/managed-applied`
    public static var managedAppliedMarkersDirectory: URL {
        userSupportDirectory.appendingPathComponent("managed-applied", isDirectory: true)
    }
}
