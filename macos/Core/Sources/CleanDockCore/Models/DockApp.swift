//
//  DockApp.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import Foundation

/// A single application entry inside a profile.
///
/// Resolution at apply time prefers `bundleID`, then the last known `path`,
/// then a case-insensitive name search in the standard application folders.
public struct DockApp: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    /// Display name, e.g. "Safari".
    public var name: String
    /// Primary key used to resolve the app on the target system.
    public var bundleID: String?
    /// Last known path, used as a fallback when the bundle ID cannot be resolved.
    public var path: String?

    public init(id: UUID = UUID(), name: String, bundleID: String? = nil, path: String? = nil) {
        self.id = id
        self.name = name
        self.bundleID = bundleID
        self.path = path
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, bundleID, path
    }

    /// Lenient decoding so hand-written or MDM-provided JSON with missing
    /// optional fields still imports cleanly.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID)
        self.path = try container.decodeIfPresent(String.self, forKey: .path)
        var name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        if name.isEmpty, let path = self.path {
            name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        }
        self.name = name
    }
}
