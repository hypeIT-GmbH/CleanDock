//
//  AppResolver.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import AppKit
import Foundation

/// An application found in one of the standard application folders.
public struct InstalledApp: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let name: String
    public let url: URL
    public let bundleID: String?

    public init(name: String, url: URL, bundleID: String?) {
        self.name = name
        self.url = url
        self.bundleID = bundleID
    }

    public var dockApp: DockApp {
        DockApp(name: name, bundleID: bundleID, path: url.path)
    }
}

/// Resolves a `DockApp` to an on-disk application URL.
///
/// Resolution order (first hit wins):
/// 1. `bundleID` via `NSWorkspace`
/// 2. `path`, if it still exists
/// 3. Case-insensitive search for `"<name>.app"` in the standard folders
///    (including one level of subfolders)
/// 4. No hit → `nil`. The caller silently skips the app - never an error.
public struct AppResolver: Sendable {
    public let searchDirectories: [URL]
    /// Paths of directories whose direct subfolders are also searched
    /// (one level). Per spec this applies to /Applications only.
    public let deepSearchPaths: Set<String>
    private let bundleIDLookup: @Sendable (String) -> URL?

    private static var defaultSearchDirectories: [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
        ]
    }

    public init(
        searchDirectories: [URL]? = nil,
        deepSearchPaths: Set<String>? = nil,
        bundleIDLookup: (@Sendable (String) -> URL?)? = nil
    ) {
        self.searchDirectories = searchDirectories ?? AppResolver.defaultSearchDirectories
        self.deepSearchPaths = deepSearchPaths ?? ["/Applications"]
        self.bundleIDLookup = bundleIDLookup ?? { identifier in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
        }
    }

    /// Returns the resolved application URL, or `nil` if the app is not
    /// installed anywhere we can find it.
    public func resolve(_ app: DockApp) -> URL? {
        if let bundleID = app.bundleID, !bundleID.isEmpty,
           let url = bundleIDLookup(bundleID) {
            return url
        }
        if let path = app.path, !path.isEmpty,
           path.lowercased().hasSuffix(".app"),
           FileManager.default.fileExists(atPath: path) {
            // Only .app bundles: a hand-written profile pointing at, say,
            // /etc/hosts must fall through to the name search (and then be
            // skipped) instead of becoming a broken Dock tile.
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        if !app.name.isEmpty {
            return findByName(app.name)
        }
        return nil
    }

    /// Case-insensitive search for `"<name>.app"` in the standard folders;
    /// one level of subfolders is searched only for `deepSearchPaths`
    /// (per spec: /Applications).
    private func findByName(_ name: String) -> URL? {
        let target = name.lowercased() + ".app"
        for directory in searchDirectories {
            let hit = appBundleCandidates(in: directory)
                .first { $0.lastPathComponent.lowercased() == target }
            if let hit {
                return hit
            }
        }
        return nil
    }

    /// All applications found in the standard folders (subfolders one level
    /// deep for `deepSearchPaths` only). Used by the app picker.
    public func installedApplications() -> [InstalledApp] {
        var seenPaths = Set<String>()
        var result: [InstalledApp] = []
        for directory in searchDirectories {
            for url in appBundleCandidates(in: directory) where seenPaths.insert(url.path).inserted {
                result.append(installedApp(at: url))
            }
        }
        return result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func isAppBundle(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "app"
    }

    /// All `.app` bundles directly inside `directory` - followed, for
    /// `deepSearchPaths`, by those one level down in non-app subfolders.
    /// Direct children come first so name matches prefer the shallower hit.
    private func appBundleCandidates(in directory: URL) -> [URL] {
        let children = directChildren(of: directory)
        var candidates = children.filter(isAppBundle)
        if deepSearchPaths.contains(directory.path) {
            for child in children where !isAppBundle(child) {
                candidates.append(contentsOf: directChildren(of: child).filter(isAppBundle))
            }
        }
        return candidates
    }

    /// Builds an `InstalledApp` for an on-disk `.app` bundle URL.
    public func installedApp(at url: URL) -> InstalledApp {
        let bundle = Bundle(url: url)
        var name = FileManager.default.displayName(atPath: url.path)
        if name.lowercased().hasSuffix(".app") {
            name = String(name.dropLast(4))
        }
        return InstalledApp(name: name, url: url, bundleID: bundle?.bundleIdentifier)
    }

    private func directChildren(of directory: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let contents = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: [.isHiddenKey, .isSymbolicLinkKey]
              )
        else { return [] }
        // Deliberately NOT .skipsHiddenFiles: system apps that live in the
        // OS cryptex (Safari) are exposed in /Applications as SYMLINKS that
        // carry the hidden flag - skipping hidden entries would hide Safari
        // from the picker and the name search. The exception is scoped to
        // exactly that case: hidden symlinks pass, hidden regular bundles
        // (vendor helpers, chflags hidden) stay hidden, dotfiles are
        // always skipped.
        return contents.filter { url in
            guard !url.lastPathComponent.hasPrefix(".") else { return false }
            guard let values = try? url.resourceValues(forKeys: [.isHiddenKey, .isSymbolicLinkKey]),
                  values.isHidden == true
            else { return true }
            return values.isSymbolicLink == true
        }
    }
}
