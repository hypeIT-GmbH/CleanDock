//
//  TestSupport.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import Foundation

/// Creates a unique temporary directory and removes it when deallocated.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        // Use the /private/var form so path comparisons are stable -
        // FileManager APIs return symlink-resolved paths on macOS.
        var basePath = FileManager.default.temporaryDirectory.path
        if basePath.hasPrefix("/var/") {
            basePath = "/private" + basePath
        }
        url = URL(fileURLWithPath: basePath, isDirectory: true)
            .appendingPathComponent("CleanDockCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func subdirectory(_ name: String) throws -> URL {
        let sub = url.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        return sub
    }

    /// Creates an empty fake `.app` bundle directory and returns its URL.
    @discardableResult
    func makeFakeApp(named name: String, in relativePath: String? = nil) throws -> URL {
        var directory = url
        if let relativePath {
            directory = directory.appendingPathComponent(relativePath, isDirectory: true)
        }
        let appURL = directory.appendingPathComponent("\(name).app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: appURL.appendingPathComponent("Contents/MacOS", isDirectory: true),
            withIntermediateDirectories: true
        )
        return appURL
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Shared capture box for the dockWriter test hook. `showRecents` is a
/// double optional on purpose: `.some(nil)` distinguishes "writer called
/// with nil" from "writer never called" (seed the initial value per test).
final class DockWriteCapture: @unchecked Sendable {
    var tiles: [[String: Any]] = []
    var showRecents: Bool??

    init(showRecents: Bool?? = nil) {
        self.showRecents = showRecents
    }
}
