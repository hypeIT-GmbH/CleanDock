//
//  AppVersion.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import CleanDockCore
import Foundation

/// Single source of truth for the version shown in the UI (About window and
/// Settings tabs), so the displayed version cannot drift between views.
enum AppVersion {
    /// Marketing version, e.g. "1.0.0". Reads the installed bundle and falls
    /// back to the compiled-in `CleanDockInfo.version` (kept in sync with
    /// MARKETING_VERSION in project.yml).
    ///
    /// One deliberate exception: the update-check result alert shows
    /// `CleanDockInfo.version` directly - that is the value the comparison
    /// actually ran against, and the alert must not claim a different one.
    /// Both sources are release-gated to be identical (make-pkg.sh and
    /// release.yml verify them against each other).
    static var displayVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? CleanDockInfo.version
    }

    /// Marketing version with build number, e.g. "1.0.0 (1)".
    static var displayVersionWithBuild: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(displayVersion) (\(build))"
    }
}
