//
//  CleanDockError.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import Foundation

/// Errors that represent real failures anywhere in the Core package.
/// Skipped (not installed) apps are deliberately *not* an error anywhere
/// in the product.
public enum CleanDockError: LocalizedError, Sendable, Equatable {
    case preferencesSynchronizationFailed
    case dockPreferencesUnreadable
    case invalidBackup(String)
    case noBackupAvailable
    case profileNotFound(String)
    case invalidProfileJSON(String)
    case mustRunAsUser

    public var errorDescription: String? {
        switch self {
        case .preferencesSynchronizationFailed:
            return "Failed to synchronize the Dock preferences (com.apple.dock)."
        case .dockPreferencesUnreadable:
            return "The Dock preferences (com.apple.dock) could not be read - aborting so the backup does not record an empty Dock."
        case .invalidBackup(let name):
            return "The backup file \"\(name)\" is not a valid Dock backup."
        case .noBackupAvailable:
            return "No backup is available to restore."
        case .profileNotFound(let name):
            return "No profile named \"\(name)\" was found."
        case .invalidProfileJSON(let detail):
            return "The profile JSON is invalid: \(detail)"
        case .mustRunAsUser:
            return "This command must run in a user context (the Dock is per-user), not as root."
        }
    }
}
