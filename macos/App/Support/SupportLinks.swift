//
//  SupportLinks.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import Foundation

/// All outbound links in one place. Links are only ever opened in the default
/// browser via `NSWorkspace.shared.open(_:)`. The single exception is
/// `latestReleaseAPI`, which `UpdateChecker` queries directly - the app's
/// only network request, opt-in or user-initiated.
enum SupportLinks {
    static let buyMeACoffee = URL(string: "https://buymeacoffee.com/cleandock")!
    static let gitHub = URL(string: "https://github.com/hypeIT-GmbH/CleanDock")!
    static let newIssue = URL(string: "https://github.com/hypeIT-GmbH/CleanDock/issues/new/choose")!
    static let license = URL(string: "https://github.com/hypeIT-GmbH/CleanDock/blob/main/LICENSE")!
    /// GitHub API endpoint for the update check - the app's only network
    /// access (opt-in or user-initiated, see `UpdateChecker`).
    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/hypeIT-GmbH/CleanDock/releases/latest")!
}
