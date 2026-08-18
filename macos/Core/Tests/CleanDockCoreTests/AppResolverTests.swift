//
//  AppResolverTests.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import Foundation
import Testing
@testable import CleanDockCore

@Suite("AppResolver")
struct AppResolverTests {
    @Test("Bundle ID hit wins over everything else")
    func bundleIDHit() throws {
        let temp = try TemporaryDirectory()
        let safari = try temp.makeFakeApp(named: "Safari")
        let resolver = AppResolver(
            searchDirectories: [],
            bundleIDLookup: { id in id == "com.apple.Safari" ? safari : nil }
        )
        let app = DockApp(name: "Safari", bundleID: "com.apple.Safari", path: "/nonexistent/Safari.app")
        #expect(resolver.resolve(app) == safari)
    }

    @Test("Path fallback when the bundle ID cannot be resolved")
    func pathFallback() throws {
        let temp = try TemporaryDirectory()
        let app = try temp.makeFakeApp(named: "MyTool")
        let resolver = AppResolver(searchDirectories: [], bundleIDLookup: { _ in nil })
        let dockApp = DockApp(name: "MyTool", bundleID: "com.example.mytool", path: app.path)
        #expect(resolver.resolve(dockApp)?.path == app.path)
    }

    @Test("Case-insensitive name search in the search directories")
    func nameSearch() throws {
        let temp = try TemporaryDirectory()
        let app = try temp.makeFakeApp(named: "Visual Studio Code")
        let resolver = AppResolver(searchDirectories: [temp.url], bundleIDLookup: { _ in nil })
        let dockApp = DockApp(name: "visual studio code")
        #expect(resolver.resolve(dockApp)?.path == app.path)
    }

    @Test("Name search descends one level of subfolders for deep-search directories")
    func nameSearchInSubfolder() throws {
        let temp = try TemporaryDirectory()
        let app = try temp.makeFakeApp(named: "Nested", in: "Utilities")
        let resolver = AppResolver(
            searchDirectories: [temp.url],
            deepSearchPaths: [temp.url.path],
            bundleIDLookup: { _ in nil }
        )
        #expect(resolver.resolve(DockApp(name: "Nested"))?.path == app.path)
    }

    @Test("Subfolders are not searched for directories outside deepSearchPaths")
    func noSubfolderSearchForShallowDirectories() throws {
        let temp = try TemporaryDirectory()
        try temp.makeFakeApp(named: "Nested", in: "Utilities")
        let resolver = AppResolver(
            searchDirectories: [temp.url],
            deepSearchPaths: [],
            bundleIDLookup: { _ in nil }
        )
        #expect(resolver.resolve(DockApp(name: "Nested")) == nil)
    }

    @Test("Unresolvable app returns nil (silent skip, never an error)")
    func unresolvableReturnsNil() throws {
        let temp = try TemporaryDirectory()
        let resolver = AppResolver(searchDirectories: [temp.url], bundleIDLookup: { _ in nil })
        let dockApp = DockApp(
            name: "Definitely Not Installed",
            bundleID: "com.example.missing",
            path: "/Applications/Definitely Not Installed.app"
        )
        #expect(resolver.resolve(dockApp) == nil)
    }

    @Test("Resolution order: dead path is skipped, name search still hits")
    func deadPathFallsThroughToNameSearch() throws {
        let temp = try TemporaryDirectory()
        let app = try temp.makeFakeApp(named: "Slack")
        let resolver = AppResolver(searchDirectories: [temp.url], bundleIDLookup: { _ in nil })
        let dockApp = DockApp(name: "Slack", bundleID: nil, path: "/gone/Slack.app")
        #expect(resolver.resolve(dockApp)?.path == app.path)
    }

    @Test("Hidden-flagged app entries (Safari's cryptex symlink) are still found; dotfiles are not")
    func hiddenFlaggedAppIsFound() throws {
        let temp = try TemporaryDirectory()
        // Reproduces /Applications/Safari.app on macOS 15+: the entry is a
        // symlink into the OS cryptex and carries the hidden flag.
        let real = try temp.makeFakeApp(named: "Safari")
        let cryptexLike = try temp.subdirectory("cryptex")
        let hiddenTarget = cryptexLike.appendingPathComponent("Safari.app", isDirectory: true)
        try FileManager.default.moveItem(at: real, to: hiddenTarget)
        var link = temp.url.appendingPathComponent("Safari.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: hiddenTarget)
        var values = URLResourceValues()
        values.isHidden = true
        try link.setResourceValues(values)
        // A dotfile ".Backup.app" must stay excluded even without
        // .skipsHiddenFiles.
        try FileManager.default.createDirectory(
            at: temp.url.appendingPathComponent(".Backup.app"),
            withIntermediateDirectories: true
        )

        // A hidden REGULAR bundle (vendor helper, chflags hidden) must stay
        // hidden - the exception is scoped to symlinks like Safari's.
        var hiddenRegular = temp.url.appendingPathComponent("HiddenHelper.app", isDirectory: true)
        try FileManager.default.createDirectory(at: hiddenRegular, withIntermediateDirectories: true)
        var hiddenValues = URLResourceValues()
        hiddenValues.isHidden = true
        try hiddenRegular.setResourceValues(hiddenValues)

        let resolver = AppResolver(searchDirectories: [temp.url], bundleIDLookup: { _ in nil })
        let names = resolver.installedApplications().map(\.name)
        #expect(names.contains("Safari"))
        #expect(!names.contains(".Backup"))
        #expect(!names.contains("HiddenHelper"))
        #expect(resolver.resolve(DockApp(name: "Safari"))?.lastPathComponent == "Safari.app")
    }

    @Test("A non-.app path never resolves - it must not become a Dock tile")
    func nonAppPathIsRejected() throws {
        let temp = try TemporaryDirectory()
        // The file exists, but only .app bundles may resolve via the path
        // fallback; /etc/hosts-style entries fall through to the name
        // search and are skipped there.
        let file = temp.url.appendingPathComponent("hosts")
        try Data("x".utf8).write(to: file)
        let resolver = AppResolver(searchDirectories: [temp.url], bundleIDLookup: { _ in nil })
        let dockApp = DockApp(name: "hosts", bundleID: nil, path: file.path)
        #expect(resolver.resolve(dockApp) == nil)
    }

    @Test("installedApplications finds apps incl. one subfolder level, sorted and deduplicated")
    func installedApplications() throws {
        let temp = try TemporaryDirectory()
        try temp.makeFakeApp(named: "Beta")
        try temp.makeFakeApp(named: "Alpha")
        try temp.makeFakeApp(named: "Gamma", in: "Subfolder")
        let resolver = AppResolver(
            searchDirectories: [temp.url, temp.url],
            deepSearchPaths: [temp.url.path],
            bundleIDLookup: { _ in nil }
        )
        let apps = resolver.installedApplications()
        #expect(apps.map(\.name) == ["Alpha", "Beta", "Gamma"])
    }
}
