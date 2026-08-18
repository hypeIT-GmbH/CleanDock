//
//  ModelDecodingTests.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import Foundation
import Testing
@testable import CleanDockCore

@Suite("Model decoding")
struct ModelDecodingTests {
    private func decodeDockApp(_ json: String) throws -> DockApp {
        try JSONDecoder.cleanDock().decode(DockApp.self, from: Data(json.utf8))
    }

    private func decodeProfile(_ json: String) throws -> Profile {
        try JSONDecoder.cleanDock().decode(Profile.self, from: Data(json.utf8))
    }

    @Test("DockApp derives its name from the path when the name is missing")
    func dockAppNameFromPath() throws {
        let app = try decodeDockApp(#"{"path": "/Applications/Safari.app"}"#)
        #expect(app.name == "Safari")
        #expect(app.path == "/Applications/Safari.app")
        #expect(app.bundleID == nil)
    }

    @Test("DockApp keeps an explicit name and generates a missing id")
    func dockAppExplicitName() throws {
        let app = try decodeDockApp(#"{"name": "Mail", "bundleID": "com.apple.mail"}"#)
        #expect(app.name == "Mail")
        #expect(app.bundleID == "com.apple.mail")
        #expect(app.path == nil)
    }

    @Test("DockApp with neither name nor path decodes with an empty name")
    func dockAppEmptyName() throws {
        let app = try decodeDockApp(#"{"bundleID": "com.example.tool"}"#)
        #expect(app.name.isEmpty)
    }

    @Test("Profile defaults symbol, apps, hideRecents and dates for minimal JSON")
    func profileMinimalDefaults() throws {
        let profile = try decodeProfile(#"{"name": "Minimal"}"#)
        #expect(profile.name == "Minimal")
        #expect(profile.symbol == Profile.defaultSymbol)
        #expect(profile.apps.isEmpty)
        #expect(!profile.hideRecents)
        // Both dates default to the same "now".
        #expect(profile.createdAt == profile.updatedAt)
    }

    @Test("Profile decodes explicit hideRecents and ISO 8601 dates")
    func profileExplicitFields() throws {
        let profile = try decodeProfile("""
        {
          "name": "Office",
          "hideRecents": true,
          "createdAt": "2026-01-02T03:04:05Z",
          "apps": [{ "path": "/Applications/Safari.app" }]
        }
        """)
        #expect(profile.hideRecents)
        #expect(profile.createdAt == Date(timeIntervalSince1970: 1_767_323_045))
        #expect(profile.apps.map(\.name) == ["Safari"])
    }

    @Test("Profile without a name fails to decode")
    func profileRequiresName() {
        #expect(throws: (any Error).self) {
            try decodeProfile(#"{"symbol": "briefcase.fill"}"#)
        }
    }
}
