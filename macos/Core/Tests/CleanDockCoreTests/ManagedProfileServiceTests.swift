//
//  ManagedProfileServiceTests.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import Foundation
import Testing
@testable import CleanDockCore

@Suite("ManagedProfileService")
struct ManagedProfileServiceTests {
    private func makeService(_ temp: TemporaryDirectory) throws -> ManagedProfileService {
        ManagedProfileService(
            managedDirectory: try temp.subdirectory("managed"),
            markerDirectory: try temp.subdirectory("markers")
        )
    }

    @discardableResult
    private func writeManagedProfile(
        named name: String,
        slug: String,
        autoApply: Bool? = true,
        in service: ManagedProfileService
    ) throws -> URL {
        var json: [String: Any] = [
            "name": name,
            "apps": [["name": "Safari", "bundleID": "com.apple.Safari"]]
        ]
        if let autoApply {
            json["autoApply"] = autoApply
        }
        let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        let url = service.managedDirectory.appendingPathComponent("\(slug).json")
        try data.write(to: url)
        return url
    }

    @Test("A deployed profile is pending exactly once, then marked applied")
    func appliedOnce() throws {
        let temp = try TemporaryDirectory()
        let service = try makeService(temp)
        try writeManagedProfile(named: "Standard Büro", slug: "standard-buro", in: service)

        let pending = service.pending()
        #expect(pending.count == 1)
        #expect(pending.first?.profile.name == "Standard Büro")

        try service.markApplied(try #require(pending.first))
        #expect(service.pending().isEmpty)
        // Still listed - just no longer pending.
        #expect(service.list().count == 1)
        #expect(service.isApplied(try #require(service.list().first)))
    }

    @Test("Changed file content (new hash) makes the profile pending again")
    func changedContentIsPendingAgain() throws {
        let temp = try TemporaryDirectory()
        let service = try makeService(temp)
        let url = try writeManagedProfile(named: "Standard", slug: "standard", in: service)

        try service.markApplied(try #require(service.pending().first))
        #expect(service.pending().isEmpty)

        // MDM ships an update: same file name, new content.
        var json = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        json["apps"] = [["name": "Mail", "bundleID": "com.apple.mail"]]
        try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]).write(to: url)

        let pending = service.pending()
        #expect(pending.count == 1)
        #expect(pending.first?.profile.apps.first?.name == "Mail")
    }

    @Test("autoApply: false excludes a profile from pending but not from list")
    func optOut() throws {
        let temp = try TemporaryDirectory()
        let service = try makeService(temp)
        try writeManagedProfile(named: "Manual", slug: "manual", autoApply: false, in: service)
        #expect(service.pending().isEmpty)
        #expect(service.list().count == 1)
        #expect(service.list().first?.autoApply == false)
    }

    @Test("Missing autoApply defaults to true")
    func defaultAutoApply() throws {
        let temp = try TemporaryDirectory()
        let service = try makeService(temp)
        try writeManagedProfile(named: "Implicit", slug: "implicit", autoApply: nil, in: service)
        #expect(service.pending().count == 1)
    }

    @Test("A mistyped autoApply value falls back to deploy-only, not auto-apply")
    func mistypedAutoApplyStaysManual() throws {
        let temp = try TemporaryDirectory()
        let service = try makeService(temp)
        // "false" as a string - the classic hand-written-JSON typo. It must
        // never silently escalate a deploy-only profile into auto-applying.
        let json: [String: Any] = [
            "name": "Typo",
            "apps": [["name": "Safari", "bundleID": "com.apple.Safari"]],
            "autoApply": "false"
        ]
        let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        try data.write(to: service.managedDirectory.appendingPathComponent("typo.json"))

        #expect(service.list().first?.autoApply == false)
        #expect(service.pending().isEmpty)
    }

    @Test("A numeric autoApply value (0/1) also falls back to deploy-only")
    func numericAutoApplyStaysManual() throws {
        let temp = try TemporaryDirectory()
        let service = try makeService(temp)
        // The other real-world typo form: plist-near tools emit 0/1 instead
        // of a JSON bool. Guards the strict decode against a future lenient
        // decoder strategy.
        let json: [String: Any] = [
            "name": "Numeric",
            "apps": [["name": "Safari", "bundleID": "com.apple.Safari"]],
            "autoApply": 1
        ]
        let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        try data.write(to: service.managedDirectory.appendingPathComponent("numeric.json"))

        #expect(service.list().first?.autoApply == false)
        #expect(service.pending().isEmpty)
    }

    @Test("Repeated list() calls compare equal for id-less managed JSON")
    func listEqualityIsDeterministic() throws {
        let temp = try TemporaryDirectory()
        let service = try makeService(temp)
        try writeManagedProfile(named: "Stable", slug: "stable", in: service)
        // Profile decode regenerates random UUIDs for id-less JSON; equality
        // must still hold across reads or refresh()'s change detection
        // would churn on every call.
        #expect(service.list() == service.list())
    }

    @Test("Invalid JSON files are skipped, valid ones still load")
    func invalidFilesSkipped() throws {
        let temp = try TemporaryDirectory()
        let service = try makeService(temp)
        try Data("garbage".utf8).write(to: service.managedDirectory.appendingPathComponent("broken.json"))
        try writeManagedProfile(named: "Valid", slug: "valid", in: service)
        #expect(service.list().count == 1)
        #expect(service.list().first?.profile.name == "Valid")
    }

    @Test("Missing managed directory yields an empty list (no error)")
    func missingDirectory() throws {
        let temp = try TemporaryDirectory()
        let service = ManagedProfileService(
            managedDirectory: temp.url.appendingPathComponent("does-not-exist"),
            markerDirectory: try temp.subdirectory("markers")
        )
        #expect(service.list().isEmpty)
        #expect(service.pending().isEmpty)
    }
}
