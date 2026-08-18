//
//  Profile.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import Foundation

/// A named, ordered list of applications. The array order equals the Dock order.
public struct Profile: Codable, Identifiable, Sendable, Hashable {
    public var id: UUID
    public var name: String
    /// SF Symbol name shown in the sidebar and the menu bar extra.
    public var symbol: String
    /// Array order = Dock order.
    public var apps: [DockApp]
    /// `true` → additionally set `show-recents = false` when applying.
    public var hideRecents: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public static let defaultSymbol = "dock.rectangle"

    public init(
        id: UUID = UUID(),
        name: String,
        symbol: String = Profile.defaultSymbol,
        apps: [DockApp] = [],
        hideRecents: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.apps = apps
        self.hideRecents = hideRecents
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, symbol, apps, hideRecents, createdAt, updatedAt
    }

    /// Lenient decoding: only `name` is truly required. This keeps imports of
    /// hand-written or MDM-provided profile JSON robust.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? Profile.defaultSymbol
        self.apps = try container.decodeIfPresent([DockApp].self, forKey: .apps) ?? []
        self.hideRecents = try container.decodeIfPresent(Bool.self, forKey: .hideRecents) ?? false
        let now = Date()
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? now
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? now
    }

    /// A copy of this profile with fresh identifiers for the profile and all
    /// of its apps. Used when duplicating and importing.
    public func withRegeneratedIDs() -> Profile {
        var copy = self
        copy.id = UUID()
        copy.apps = apps.map { app in
            var app = app
            app.id = UUID()
            return app
        }
        return copy
    }
}
