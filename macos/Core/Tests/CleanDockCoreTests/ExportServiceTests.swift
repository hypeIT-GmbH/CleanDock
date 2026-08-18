//
//  ExportServiceTests.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import Foundation
import Testing
@testable import CleanDockCore

@Suite("ExportService")
struct ExportServiceTests {
    @Test("Slug rules: lowercase, a-z0-9-, umlauts folded, runs collapsed")
    func slugRules() {
        #expect(ExportService.slug(for: "Standard Büro") == "standard-buro")
        #expect(ExportService.slug(for: "Groß & Klein!! 2") == "gross-klein-2")
        #expect(ExportService.slug(for: "  --Design--  ") == "design")
        #expect(ExportService.slug(for: "äöü") == "aou")
        #expect(ExportService.slug(for: "@@@") == "profile")
    }

    @Test("Managed file slugs are collision-free for names that slugify alike")
    func managedFileSlugUniqueness() {
        // Different names whose readable slugs collide would overwrite each
        // other in the managed directory - the hash suffix keeps them apart
        // while staying deterministic per name.
        let kanji = ExportService.managedFileSlug(for: "事務")
        let hangul = ExportService.managedFileSlug(for: "사무실")
        #expect(kanji != hangul)
        #expect(kanji.hasPrefix("profile-"))
        #expect(kanji == ExportService.managedFileSlug(for: "事務"))
    }

    @Test("Import rejects wrappers written by a newer format version")
    func importRejectsNewerVersion() {
        let json = Data("""
        {"version": \(ProfileFileFormat.version + 1), "profiles": []}
        """.utf8)
        #expect(throws: CleanDockError.self) {
            try ExportService.decodeProfiles(from: json)
        }
    }

    @Test("Import accepts ISO 8601 dates with fractional seconds")
    func importAcceptsFractionalSeconds() throws {
        // Third-party exporters commonly emit milliseconds - both plain and
        // fractional ISO 8601 must decode.
        let json = Data("""
        {
          "name": "Fraction",
          "apps": [],
          "createdAt": "2026-08-18T09:00:00.000Z",
          "updatedAt": "2026-08-18T09:00:00Z"
        }
        """.utf8)
        let profiles = try ExportService.decodeProfiles(from: json)
        #expect(profiles.first?.name == "Fraction")
    }

    @Test("MDM script embeds valid JSON with autoApply inside the heredoc")
    func mdmScriptJSON() throws {
        var profile = Profile(name: "Standard Büro", symbol: "briefcase.fill", hideRecents: true)
        profile.apps = [
            DockApp(name: "Safari", bundleID: "com.apple.Safari", path: "/Applications/Safari.app")
        ]
        let script = try ExportService().mdmScript(for: profile, appVersion: "1.0.0")

        let data = try heredocData(in: script)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["autoApply"] as? Bool == true)
        #expect(object["name"] as? String == "Standard Büro")
        #expect(object["hideRecents"] as? Bool == true)
        #expect((object["apps"] as? [[String: Any]])?.first?["bundleID"] as? String == "com.apple.Safari")

        // The embedded JSON must decode back into an equivalent profile.
        let roundtripped = try ExportService.decodeProfiles(from: data)
        #expect(roundtripped.first?.name == "Standard Büro")
        #expect(roundtripped.first?.apps.count == 1)
    }

    @Test("MDM script uses the correct slug and metadata")
    func mdmScriptMetadata() throws {
        let profile = Profile(name: "Standard Büro")
        let script = try ExportService().mdmScript(for: profile, appVersion: "1.2.3")
        #expect(script.hasPrefix("#!/bin/bash"))
        #expect(script.contains("CONFIG_FILE=\"$CONFIG_DIR/\(ExportService.managedFileSlug(for: "Standard Büro")).json\""))
        // The script migrates away the pre-1.0 filename (slug without hash
        // suffix) - but only when the file's profile name matches, because
        // legacy slugs are not unique per profile (collision → the file
        // could belong to a DIFFERENT deployed profile).
        #expect(script.contains("LEGACY_FILE=\"$CONFIG_DIR/standard-buro.json\""))
        #expect(script.contains("plutil -extract name raw"))
        #expect(script.contains("[ \"$LEGACY_NAME\" = \"$NEW_NAME\" ]"))
        #expect(script.contains("Managed Profile: Standard Büro"))
        #expect(script.contains("Generiert von CleanDock 1.2.3"))
        #expect(script.contains("apply --managed"))
        #expect(script.hasSuffix("exit 0"))
    }

    @Test("Deploy-only script omits the immediate apply and marks autoApply false")
    func deployOnlyScript() throws {
        var profile = Profile(name: "Standard Büro")
        profile.apps = [DockApp(name: "Safari", bundleID: "com.apple.Safari")]
        let script = try ExportService().mdmScript(for: profile, autoApply: false)

        #expect(!script.contains("apply --managed"))
        #expect(!script.contains("APP_CLI"))
        #expect(script.contains("CONFIG_FILE=\"$CONFIG_DIR/\(ExportService.managedFileSlug(for: "Standard Büro")).json\""))
        #expect(script.hasPrefix("#!/bin/bash"))
        #expect(script.hasSuffix("exit 0"))

        // The embedded JSON must opt the profile out of automatic application.
        let object = try heredocJSON(in: script)
        #expect(object["autoApply"] as? Bool == false)
    }

    @Test("Both script variants are valid bash", arguments: [true, false])
    func scriptSyntax(autoApply: Bool) throws {
        let profile = Profile(name: "Syntax Check", apps: [DockApp(name: "Safari")])
        let script = try ExportService().mdmScript(for: profile, autoApply: autoApply)

        let temp = try TemporaryDirectory()
        let scriptURL = temp.url.appendingPathComponent("postinstall.sh")
        try Data(script.utf8).write(to: scriptURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-n", scriptURL.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test("Deploy-only export is listed as managed but never pending")
    func deployOnlyIsNotPending() throws {
        let temp = try TemporaryDirectory()
        let service = ManagedProfileService(
            managedDirectory: try temp.subdirectory("managed"),
            markerDirectory: try temp.subdirectory("markers")
        )
        let profile = Profile(name: "Manual Rollout", apps: [DockApp(name: "Safari")])
        let json = try ExportService().managedProfileJSON(for: profile, autoApply: false)
        try json.write(to: service.managedDirectory.appendingPathComponent("manual-rollout.json"))

        #expect(service.list().count == 1)
        #expect(service.list().first?.autoApply == false)
        #expect(service.pending().isEmpty)
    }

    @Test("Profile names with control characters cannot break out of script comment lines")
    func scriptInjectionSanitized() throws {
        let profile = Profile(name: "Office\nrm -rf ~\r\u{1B}[2Jevil")
        let script = try ExportService().mdmScript(for: profile, appVersion: "1.0.0")
        // The name must stay confined to its comment line: outside the
        // heredoc, any line containing name fragments must be a comment,
        // and control characters must be gone entirely.
        let heredoc = try heredocRange(in: script)
        for (index, line) in heredoc.lines.enumerated()
        where index < heredoc.start || index > heredoc.end {
            if line.contains("rm -rf") {
                #expect(line.hasPrefix("#"))
            }
            #expect(!line.contains("\u{1B}"))
            #expect(!line.contains("\r"))
        }
        #expect(script.contains("# CleanDock - Managed Profile: Office rm -rf ~"))
    }

    @Test("A profile name containing a literal placeholder token is not re-expanded")
    func placeholderTokenInNameStaysVerbatim() throws {
        let profile = Profile(name: "x {{PROFILE_JSON}}", apps: [DockApp(name: "Safari")])
        let script = try ExportService().mdmScript(for: profile, appVersion: "1.0.0")

        // The token must survive verbatim in its comment line …
        #expect(script.contains("# CleanDock - Managed Profile: x {{PROFILE_JSON}}"))

        // … and the profile JSON must exist only inside the heredoc. A
        // substitution that re-scans already-substituted text would expand
        // the token a second time and spill multi-line JSON - breaking out
        // of the comment - into a script that runs as root.
        let heredoc = try heredocRange(in: script)
        for (index, line) in heredoc.lines.enumerated()
        where index < heredoc.start || index > heredoc.end {
            #expect(!line.contains("\"autoApply\""))
        }
    }

    @Test("Plain JSON export contains no autoApply and roundtrips")
    func plainJSONExport() throws {
        var profile = Profile(name: "Home", hideRecents: false)
        profile.apps = [DockApp(name: "Mail", bundleID: "com.apple.mail")]
        let data = try ExportService().profileJSON(for: profile)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["autoApply"] == nil)

        let decoded = try ExportService.decodeProfiles(from: data)
        #expect(decoded.first?.id == profile.id)
        #expect(decoded.first?.apps.first?.bundleID == "com.apple.mail")
    }

    @Test("Import accepts a full profiles.json wrapper")
    func importWrapper() throws {
        let json = """
        {
          "version": 1,
          "profiles": [
            { "name": "A", "apps": [] },
            { "name": "B", "apps": [{ "name": "Safari" }] }
          ]
        }
        """
        let profiles = try ExportService.decodeProfiles(from: Data(json.utf8))
        #expect(profiles.map(\.name) == ["A", "B"])
    }

    @Test("Invalid JSON throws invalidProfileJSON")
    func invalidJSON() {
        #expect(throws: CleanDockError.self) {
            try ExportService.decodeProfiles(from: Data("nope".utf8))
        }
    }

    // MARK: - Heredoc helpers

    /// Locates the DOCKPROFILE heredoc: the marker line indices plus all
    /// script lines.
    private func heredocRange(in script: String) throws -> (start: Int, end: Int, lines: [String]) {
        let lines = script.components(separatedBy: "\n")
        let start = try #require(lines.firstIndex { $0.hasSuffix("<<'DOCKPROFILE'") })
        let end = try #require(lines.firstIndex { $0 == "DOCKPROFILE" })
        return (start, end, lines)
    }

    /// The raw profile JSON between the heredoc markers.
    private func heredocData(in script: String) throws -> Data {
        let heredoc = try heredocRange(in: script)
        return Data(heredoc.lines[(heredoc.start + 1)..<heredoc.end].joined(separator: "\n").utf8)
    }

    /// Extracts and parses the profile JSON between the heredoc markers.
    private func heredocJSON(in script: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: heredocData(in: script)) as? [String: Any])
    }
}
