//
//  UpdateChecker.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import CleanDockCore
import Foundation

/// A newer release found on GitHub.
struct UpdateInfo: Equatable {
    let version: String
    let releaseURL: URL
}

/// Fetches the latest release from the GitHub API and compares it with the
/// running version.
///
/// This is the app's ONLY network access. It runs exclusively for the
/// opt-in automatic check (off by default) and user-initiated
/// "Check for Updates" - never silently in the background.
struct UpdateChecker: Sendable {
    private let endpoint = SupportLinks.latestReleaseAPI

    /// Ephemeral session: the no-data-collection promise extends to leaving
    /// no persistent URL cache/cookies on disk, and a hung request must not
    /// occupy the .checking state for the default 60 seconds.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    /// The newer release, or `nil` when the running version is current.
    func checkForUpdate() async throws -> UpdateInfo? {
        struct Release: Decodable {
            let tagName: String
            let htmlURL: URL

            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
                case htmlURL = "html_url"
            }
        }

        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let release = try JSONDecoder().decode(Release.self, from: data)
        // The release URL is server-provided input that ends up in
        // NSWorkspace.open - accept only GitHub HTTPS pages.
        guard release.htmlURL.scheme?.lowercased() == "https",
              let host = release.htmlURL.host?.lowercased(),
              host == "github.com" || host.hasSuffix(".github.com")
        else {
            throw URLError(.badServerResponse)
        }
        let version = release.tagName.hasPrefix("v")
            ? String(release.tagName.dropFirst())
            : release.tagName
        guard CleanDockInfo.isVersion(version, newerThan: CleanDockInfo.version) else {
            return nil
        }
        return UpdateInfo(version: version, releaseURL: release.htmlURL)
    }
}
