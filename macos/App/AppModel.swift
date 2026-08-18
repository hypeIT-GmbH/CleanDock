//
//  AppModel.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import AppKit
import CleanDockCore
import Observation
import UniformTypeIdentifiers
import UserNotifications

/// Which sidebar entry is selected.
enum SidebarItem: Hashable {
    case profile(UUID)
    case managed(String)
}

/// Shared application state for the main window, the menu bar extra and the
/// settings window. One instance lives for the whole app session.
@MainActor
@Observable
final class AppModel {
    static let showMenuBarIconKey = "showMenuBarIcon"
    private static let cleanupCountKey = "successfulCleanupCount"
    private static let supportPromptOptOutKey = "supportPromptOptOut"
    private static let automaticUpdateChecksKey = "automaticUpdateChecks"
    private static let lastUpdateCheckKey = "lastUpdateCheck"

    let store: ProfileStore
    let resolver: AppResolver
    let backupService: BackupService
    private let dockService: DockService
    let managedService: ManagedProfileService
    private let exportService = ExportService()
    /// Hourly anchor for menu-bar-only sessions: drives the daily automatic
    /// update check AND the refresh of externally changeable state (see init).
    @ObservationIgnored private var hourlyTickTimer: Timer?

    private(set) var managedProfiles: [ManagedProfile] = []
    private(set) var canUndo = false

    var selection: SidebarItem?
    var errorMessage: String?
    /// Set after creating a profile so the sidebar starts inline renaming
    /// without further clicks.
    var pendingRenameProfileID: UUID?

    /// Feedback shown in the footer after a successful cleanup.
    struct CleanupFeedback: Equatable {
        var profileID: UUID
        var skipped: [DockApp]
    }
    var feedback: CleanupFeedback?

    init() {
        CleanDockPaths.migrateLegacySupportDirectoryIfNeeded()
        store = ProfileStore()
        resolver = AppResolver()
        backupService = BackupService()
        dockService = DockService(resolver: resolver, backupService: backupService)
        managedService = ManagedProfileService()
        refresh()
        if selection == nil, let first = store.profiles.first {
            selection = .profile(first.id)
        }
        runAutomaticUpdateCheckIfDue()
        // The app is built to keep running in the menu bar for weeks - the
        // launch-time check alone would never fire again in that mode. The
        // hourly tick is cheap; runAutomaticUpdateCheckIfDue keeps the
        // actual once-a-day cadence (and the opt-in gate). The tick also
        // refreshes externally changeable state (managed profiles, CLI
        // backups/captures) for menu-bar-only sessions - deliberately NOT
        // done from the menu's own lifecycle, which must stay free of side
        // effects (see the live-lock note on refresh()).
        hourlyTickTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.runAutomaticUpdateCheckIfDue()
                self?.refresh()
            }
        }
        // Window focus is the natural anchor for picking up external state.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    /// Re-reads state that can change behind our back (managed profile files,
    /// backups written by the CLI).
    ///
    /// managedProfiles/canUndo are written only on actual change: the menu
    /// graph reads them, @Observable signals every assignment (even a
    /// value-equal one), and an unconditional write from view lifecycle hooks
    /// can live-lock SwiftUI's menu graph in an invalidate/rebuild loop. The
    /// resolutionEpoch bump below is deliberately unconditional - no menu
    /// content observes it, only the row views' task keys.
    func refresh() {
        let managed = managedService.list()
        if managed != managedProfiles {
            managedProfiles = managed
        }
        let hasBackups = backupService.hasBackups
        if hasBackups != canUndo {
            canUndo = hasBackups
        }
        // Profiles the CLI wrote while the app is running become visible
        // here. Installs/uninstalls invalidate the row resolution cache,
        // and the epoch bump makes already-rendered rows re-resolve (their
        // .task is keyed on it) - a bare cache clear would only affect rows
        // rendered afterwards.
        store.mergeExternalChanges()
        resolutionCache.removeAll()
        resolutionEpoch += 1
    }

    // MARK: - Row resolution cache

    /// Bumped by refresh(); row views key their resolution task on it so
    /// visible "Not installed" badges pick up installs/uninstalls.
    private(set) var resolutionEpoch = 0

    /// Per-session cache for list-row resolution: resolving a NOT installed
    /// app scans the application folders, and doing that per row on every
    /// list rebuild is wasted work. Invalidated by refresh(). The first
    /// resolution of each app runs off the main actor - a foreign profile
    /// full of missing apps must not stall the UI on first display.
    @ObservationIgnored private var resolutionCache: [DockApp: URL?] = [:]

    func resolvedURL(for app: DockApp) async -> URL? {
        if let cached = resolutionCache[app] {
            return cached
        }
        let epoch = resolutionEpoch
        let resolver = resolver
        let url = await Task.detached(priority: .userInitiated) {
            resolver.resolve(app)
        }.value
        // A refresh() during the suspension cleared the cache and bumped the
        // epoch - writing this (now possibly stale) result would poison the
        // fresh cache and silently defeat the epoch invalidation. Return it
        // to the caller, but do not cache it.
        if epoch == resolutionEpoch {
            resolutionCache[app] = url
        }
        return url
    }

    // MARK: - Cleanup

    /// Applies a profile to the Dock. Skipped apps are not an error - they
    /// surface as a subtle hint in the returned feedback.
    ///
    /// Deliberately synchronous on the main actor: the whole apply (resolve,
    /// backup, CFPreferences write, `killall Dock`) completes in tens of
    /// milliseconds, and keeping it synchronous rules out every reentrancy
    /// race between backup, write and UI state for free.
    @discardableResult
    func applyProfile(_ profile: Profile, isManaged: Bool = false, notify: Bool = false) -> ApplyResult? {
        // The backup is written before the Dock write can fail, so the Undo
        // affordance must be refreshed on every exit path.
        defer { canUndo = backupService.hasBackups }
        do {
            let result = try dockService.apply(profile)
            if isManaged, let managed = managedProfiles.first(where: { $0.profile.id == profile.id }) {
                do {
                    try managedService.markApplied(managed)
                } catch {
                    // Without the marker the LaunchAgent re-applies this
                    // profile at the next login - worth telling the user.
                    presentError(error)
                }
            }
            registerSuccessfulCleanup(profile: profile, result: result)
            if notify {
                postCleanupNotification(profileName: profile.name)
            }
            return result
        } catch {
            presentError(error)
            return nil
        }
    }

    private func registerSuccessfulCleanup(profile: Profile, result: ApplyResult) {
        let defaults = UserDefaults.standard
        let count = defaults.integer(forKey: Self.cleanupCountKey) + 1
        defaults.set(count, forKey: Self.cleanupCountKey)
        feedback = CleanupFeedback(profileID: profile.id, skipped: result.skipped)
        writeCleanupLog(profile: profile, result: result)
        maybeShowSupportPrompt(count: count)
    }

    // MARK: - Support prompt

    // Deliberate product decision (2026-08-18): the prompt RECURS (first
    // after 10 successful cleanups, then every 20) until the user opts out
    // via the "Don't show this again" checkbox - it never activates the
    // app or steals focus. This supersedes the original spec's
    // "once per installation" inline hint.
    /// First prompt after this many successful cleanups …
    private static let supportPromptFirstCount = 10
    /// … then again every this many cleanups, until the user opts out.
    private static let supportPromptInterval = 20

    private func maybeShowSupportPrompt(count: Int) {
        guard !UserDefaults.standard.bool(forKey: Self.supportPromptOptOutKey) else { return }
        let first = Self.supportPromptFirstCount
        guard count == first
            || (count > first && (count - first) % Self.supportPromptInterval == 0)
        else { return }
        // Deliberate fixed delay: lets the Dock restart settle so the
        // prompt never competes with the animation the user just triggered.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            SupportPrompt.present(model: self)
        }
    }

    /// Bound to the prompt's "Don't show this again" checkbox - written
    /// immediately, so every way of closing the prompt respects it.
    func setSupportPromptOptOut(_ optOut: Bool) {
        UserDefaults.standard.set(optOut, forKey: Self.supportPromptOptOutKey)
    }

    // MARK: - Cleanup log

    /// Log describing the most recent cleanup - the feedback line's "?"
    /// button opens it so skipped apps can be diagnosed.
    var cleanupLogURL: URL {
        CleanDockPaths.userSupportDirectory.appendingPathComponent("last-cleanup.log")
    }

    func showCleanupLog() {
        guard FileManager.default.fileExists(atPath: cleanupLogURL.path) else { return }
        NSWorkspace.shared.open(cleanupLogURL)
    }

    private func writeCleanupLog(profile: Profile, result: ApplyResult) {
        let dateText = Date().formatted(date: .abbreviated, time: .standard)
        var lines: [String] = [
            String(localized: "CleanDock cleanup log"),
            String(localized: "Date: \(dateText)"),
            String(localized: "Profile: \(profile.name)"),
            "",
            String(localized: "Applied: \(result.applied.count) apps")
        ]
        lines.append(contentsOf: result.applied.map { "  ✓ \($0.name)" })
        if !result.skipped.isEmpty {
            lines.append("")
            lines.append(String(localized: "Skipped: \(result.skipped.count) apps (not installed)"))
            for app in result.skipped {
                lines.append("  ✗ \(app.name)")
                lines.append(contentsOf: skipReasons(for: app).map { "      - \($0)" })
            }
        }
        do {
            try FileManager.default.createDirectory(
                at: CleanDockPaths.userSupportDirectory,
                withIntermediateDirectories: true
            )
            try Data(lines.joined(separator: "\n").appending("\n").utf8)
                .write(to: cleanupLogURL, options: .atomic)
        } catch {
            // The log is diagnostics only - its failure must never surface
            // as a cleanup error.
        }
    }

    /// A skipped app failed every lookup the resolver tries; each provided
    /// key gets its own explanation line.
    private func skipReasons(for app: DockApp) -> [String] {
        var reasons: [String] = []
        if let bundleID = app.bundleID, !bundleID.isEmpty {
            reasons.append(String(localized: "no installed app with bundle ID “\(bundleID)”"))
        }
        if let path = app.path, !path.isEmpty {
            reasons.append(String(localized: "path does not exist: \(path)"))
        }
        reasons.append(String(localized: "no “\(app.name).app” found in the standard application folders"))
        return reasons
    }

    func dismissFeedback() {
        feedback = nil
    }

    func undo() {
        do {
            try dockService.restoreLastBackup()
            feedback = nil
        } catch {
            presentError(error)
        }
        canUndo = backupService.hasBackups
    }

    // MARK: - Backups

    /// Restores a specific backup from the settings list. The current Dock
    /// is snapshotted first, so the restore itself stays undoable.
    func restoreBackup(_ backup: BackupService.BackupInfo) {
        do {
            try dockService.restoreBackup(at: backup.url)
            feedback = nil
        } catch {
            presentError(error)
        }
        canUndo = backupService.hasBackups
    }

    /// Converts a backup into a regular, editable profile.
    @discardableResult
    func saveBackupAsProfile(_ backup: BackupService.BackupInfo) -> Profile? {
        do {
            let captured = try dockService.capturedDock(inBackupAt: backup.url)
            let name = String(
                localized: "Backup from \(backup.date.formatted(date: .abbreviated, time: .shortened))"
            )
            let profile = store.add(Profile(
                name: name,
                apps: captured.apps,
                // Legacy backups did not record the recents state - false
                // (the model default) is the conservative reading there.
                hideRecents: captured.hideRecents ?? false
            ))
            selection = .profile(profile.id)
            reportPersistenceFailure()
            return profile
        } catch {
            presentError(error)
            return nil
        }
    }

    /// Core errors carry English descriptions (shared with the CLI); the app
    /// presents them localized.
    func presentError(_ error: Error) {
        presentErrorMessage(localizedMessage(for: error))
    }

    private func localizedMessage(for error: Error) -> String {
        guard let coreError = error as? CleanDockError else {
            return error.localizedDescription
        }
        switch coreError {
        case .preferencesSynchronizationFailed:
            return String(localized: "The Dock preferences could not be synchronized.")
        case .dockPreferencesUnreadable:
            return String(localized: "The Dock preferences could not be read, so no backup was possible. Nothing was changed.")
        case .invalidBackup(let name):
            return String(localized: "The backup file “\(name)” is not a valid Dock backup.")
        case .noBackupAvailable:
            return String(localized: "No backup is available to restore.")
        case .profileNotFound(let name):
            return String(localized: "No profile named “\(name)” was found.")
        case .invalidProfileJSON(let detail):
            return String(localized: "The profile JSON is invalid: \(detail)")
        case .mustRunAsUser:
            return String(localized: "This action must run in a user context.")
        }
    }

    /// Errors normally surface via the alert bound to the main window's
    /// content view. Without a visible main window (menu bar cleanup,
    /// Settings-only, Help menu) that alert has no presentation surface -
    /// the failure would be silent now and pop up as a stale, contextless
    /// alert whenever the window opens later. Fall back to a standalone
    /// alert in that case.
    func presentErrorMessage(_ message: String) {
        if hasVisibleMainWindow {
            errorMessage = message
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "An Error Occurred")
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private var hasVisibleMainWindow: Bool {
        // isVisible alone stays true for windows on another Space or fully
        // covered by other apps ("ordered in") - exactly the cases where an
        // alert bound to the window would go unseen. Require an active app,
        // actual on-screen presence AND key status: errors triggered from
        // the Settings window (key at that moment) must not surface as a
        // dialog attached to the main window behind it.
        NSApp.isActive && NSApp.windows.contains { window in
            window.isVisible
                && window.isKeyWindow
                && window.occlusionState.contains(.visible)
                && window.identifier?.rawValue.contains(WindowID.main) == true
        }
    }

    /// ProfileStore mutations are non-throwing by design; a failed
    /// profiles.json write lands in `lastSaveError`. Check it after every
    /// GUI mutation - otherwise the session's changes would silently vanish
    /// with the next app quit.
    private func reportPersistenceFailure() {
        guard let saveError = store.lastSaveError else { return }
        presentError(saveError)
    }

    /// Optional success notification for menu bar cleanups. Notifications are
    /// nice-to-have - any failure here is silently ignored.
    private func postCleanupNotification(profileName: String) {
        let center = UNUserNotificationCenter.current()
        Task {
            do {
                let granted = try await center.requestAuthorization(options: [.alert])
                guard granted else { return }
                let content = UNMutableNotificationContent()
                content.title = String(localized: "Dock updated")
                content.body = String(localized: "Profile “\(profileName)” has been applied.")
                let request = UNNotificationRequest(
                    identifier: UUID().uuidString,
                    content: content,
                    trigger: nil
                )
                try await center.add(request)
            } catch {
                // Notifications are optional by design.
            }
        }
    }

    // MARK: - Profile management

    func createAndSelectProfile() {
        let profile = store.createProfile(named: String(localized: "New Profile"))
        selection = .profile(profile.id)
        pendingRenameProfileID = profile.id
        reportPersistenceFailure()
    }

    /// "Adopt Current Dock": reads the current Dock into a new profile,
    /// including the hide-recents state - the adopted profile must
    /// reproduce the user's Dock exactly, recents section included.
    func adoptCurrentDock() {
        let captured = dockService.captureDock()
        let profile = store.add(Profile(
            name: String(localized: "My Dock"),
            apps: captured.apps,
            hideRecents: captured.hideRecents
        ))
        selection = .profile(profile.id)
        reportPersistenceFailure()
    }

    func deleteProfile(_ profile: Profile) {
        store.delete(id: profile.id)
        if selection == .profile(profile.id) {
            selection = store.profiles.first.map { .profile($0.id) }
        }
        reportPersistenceFailure()
    }

    func duplicateProfile(_ profile: Profile) {
        if let copy = store.duplicate(id: profile.id) {
            selection = .profile(copy.id)
        }
        reportPersistenceFailure()
    }

    /// Renames a profile; the store normalizes the name (trims, resolves
    /// collisions) and ignores empty drafts.
    func renameProfile(id: UUID, to newName: String) {
        store.rename(id: id, to: newName)
        reportPersistenceFailure()
    }

    /// Creates an editable user profile from a managed (read-only) profile.
    func duplicateManagedProfile(_ managed: ManagedProfile) {
        var copy = managed.profile.withRegeneratedIDs()
        let now = Date()
        copy.createdAt = now
        copy.updatedAt = now
        let added = store.add(copy)
        selection = .profile(added.id)
        reportPersistenceFailure()
    }

    /// Applies a mutation to a stored profile and persists it.
    func updateProfile(id: UUID, _ mutate: (inout Profile) -> Void) {
        guard var profile = store.profile(withID: id) else { return }
        mutate(&profile)
        store.update(profile)
        reportPersistenceFailure()
    }

    // MARK: - Adding apps

    /// Adds `.app` bundles to a profile, optionally at a specific position.
    /// Non-app URLs and duplicates (same path, whether already in the profile
    /// or repeated within the batch) are ignored. Returns the number of apps
    /// actually added.
    @discardableResult
    func addApps(urls: [URL], to profileID: UUID, at index: Int? = nil) -> Int {
        let apps = urls
            .filter { $0.pathExtension.lowercased() == "app" }
            .map { resolver.installedApp(at: $0).dockApp }
        guard !apps.isEmpty, let profile = store.profile(withID: profileID) else { return 0 }

        // Imported profiles may carry foreign paths or path-less,
        // bundle-ID-only entries - a path comparison alone would let
        // the same app in twice (and produce duplicate Dock tiles).
        // Deduplicated BEFORE the store mutation: an all-duplicates drop
        // must not stamp updatedAt and rewrite profiles.json for nothing.
        var seenPaths = Set(profile.apps.compactMap(\.path))
        var seenBundleIDs = Set(profile.apps.compactMap(\.bundleID))
        let newApps = apps.filter { app in
            if let path = app.path, seenPaths.contains(path) { return false }
            if let bundleID = app.bundleID, seenBundleIDs.contains(bundleID) { return false }
            if let path = app.path { seenPaths.insert(path) }
            if let bundleID = app.bundleID { seenBundleIDs.insert(bundleID) }
            return true
        }
        guard !newApps.isEmpty else { return 0 }

        updateProfile(id: profileID) { profile in
            let insertionIndex = min(index ?? profile.apps.count, profile.apps.count)
            profile.apps.insert(contentsOf: newApps, at: insertionIndex)
        }
        return newApps.count
    }

    func addApps(_ installedApps: [InstalledApp], to profileID: UUID) {
        addApps(urls: installedApps.map(\.url), to: profileID)
    }

    /// NSOpenPanel fallback for adding apps.
    func addAppsViaOpenPanel(to profileID: UUID) {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Add App")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK else { return }
        addApps(urls: panel.urls, to: profileID)
    }

    // MARK: - Export / import

    func exportMDMScript(for profile: Profile) {
        guard let autoApply = askForMDMApplyBehavior() else { return }
        exportViaSavePanel(
            title: String(localized: "Export MDM Script"),
            defaultFileName: "\(ExportService.slug(for: profile.name))-postinstall.sh",
            contentType: .shellScript,
            makeData: { try Data(exportService.mdmScript(for: profile, autoApply: autoApply).utf8) },
            postProcess: { url in
                // MDM postinstall scripts must be executable. A failure here
                // surfaces like any other export error (see exportViaSavePanel).
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: url.path
                )
            }
        )
    }

    /// Lets the admin decide whether the exported script cleans up the Dock
    /// right after installation or only deploys the profile for applying it
    /// manually later. Returns `nil` when the export is cancelled.
    private func askForMDMApplyBehavior() -> Bool? {
        let alert = NSAlert()
        alert.messageText = String(localized: "Clean up the Dock right after installation?")
        alert.informativeText = String(localized: "The script always deploys the profile to the managed profiles folder. It can additionally clean up the Dock right after enrollment - or the profile just waits in CleanDock to be applied manually.")
        alert.addButton(withTitle: String(localized: "Clean Up Immediately"))
        alert.addButton(withTitle: String(localized: "Deploy Only"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return true
        case .alertSecondButtonReturn:
            return false
        default:
            return nil
        }
    }

    func exportJSON(for profile: Profile) {
        exportViaSavePanel(
            title: String(localized: "Export Profile as JSON"),
            defaultFileName: "\(ExportService.slug(for: profile.name)).json",
            contentType: .json,
            makeData: { try exportService.profileJSON(for: profile) }
        )
    }

    /// One save-panel flow for every export format, so they cannot drift.
    private func exportViaSavePanel(
        title: String,
        defaultFileName: String,
        contentType: UTType,
        makeData: () throws -> Data,
        postProcess: ((URL) throws -> Void)? = nil
    ) {
        let panel = NSSavePanel()
        panel.title = title
        panel.nameFieldStringValue = defaultFileName
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try makeData().write(to: url, options: .atomic)
            try postProcess?(url)
        } catch {
            presentError(error)
        }
    }

    /// Imports profile JSON files (open panel or drag & drop onto the sidebar).
    /// Fresh UUIDs are assigned; name collisions get "(2)" appended.
    @discardableResult
    func importProfiles(from urls: [URL]) -> Int {
        var imported = 0
        for url in urls where url.pathExtension.lowercased() == "json" {
            do {
                let data = try Data(contentsOf: url)
                if isBackupFile(data) {
                    // A Dock backup is tile data, not a profile - point to
                    // the place that can actually use it.
                    presentErrorMessage(String(localized: "This file is a Dock backup, not a profile. You can restore backups - or turn them into profiles - in Settings → Storage."))
                    continue
                }
                for profile in try ExportService.decodeProfiles(from: data) {
                    let added = store.importProfile(profile)
                    selection = .profile(added.id)
                    imported += 1
                }
                reportPersistenceFailure()
            } catch {
                presentError(error)
            }
        }
        return imported
    }

    /// Backup files are either the current wrapper object (`{"tiles": …}`)
    /// or the legacy top-level ARRAY of Dock tiles; profiles are objects
    /// with name/apps. Cheap shape check for a friendly import error.
    private func isBackupFile(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return false }
        if let wrapper = json as? [String: Any] {
            return wrapper["tiles"] is [Any]
                && wrapper["name"] == nil
                && wrapper["profiles"] == nil
        }
        // An empty array is NOT a backup - without a single tile to check
        // the shape means nothing, and the misleading "this is a backup"
        // hint would point users at the wrong feature.
        guard let array = json as? [[String: Any]], !array.isEmpty else { return false }
        return array.allSatisfy { $0["tile-type"] != nil || $0["tile-data"] != nil }
    }

    func importViaOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Import Profile")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        importProfiles(from: panel.urls)
    }

    // MARK: - Menu bar icon

    /// Whether the menu bar extra is shown; on by default. Views bind to the
    /// key via @AppStorage - this read exists for the app delegate's quit
    /// handling.
    static var isMenuBarIconEnabled: Bool {
        UserDefaults.standard.object(forKey: showMenuBarIconKey) == nil
            || UserDefaults.standard.bool(forKey: showMenuBarIconKey)
    }

    // MARK: - Update check

    enum UpdateStatus: Equatable {
        case unknown
        case checking
        case upToDate
        case available(UpdateInfo)
        case failed
    }

    private(set) var updateStatus: UpdateStatus = .unknown

    /// The newer release, once a check found one - drives the menu bar entry.
    var availableUpdate: UpdateInfo? {
        if case .available(let info) = updateStatus {
            return info
        }
        return nil
    }

    /// Opt-in automatic update check, off by default. Enabling it triggers
    /// an immediate check so the toggle gives instant feedback.
    var automaticUpdateChecks: Bool {
        get {
            access(keyPath: \.automaticUpdateChecks)
            return UserDefaults.standard.bool(forKey: Self.automaticUpdateChecksKey)
        }
        set {
            withMutation(keyPath: \.automaticUpdateChecks) {
                UserDefaults.standard.set(newValue, forKey: Self.automaticUpdateChecksKey)
            }
            if newValue {
                checkForUpdates()
            }
        }
    }

    /// Runs the enabled automatic check at most once per day.
    func runAutomaticUpdateCheckIfDue() {
        guard automaticUpdateChecks else { return }
        let lastCheck = UserDefaults.standard.double(forKey: Self.lastUpdateCheckKey)
        let dayInSeconds: TimeInterval = 24 * 60 * 60
        guard Date().timeIntervalSince1970 - lastCheck >= dayInSeconds else { return }
        checkForUpdates()
    }

    /// Queries GitHub for the latest release. With `presentAlert` (the Help
    /// menu path) the outcome is reported in an alert; otherwise it only
    /// updates `updateStatus` for the Settings pane and the menu bar entry.
    func checkForUpdates(presentAlert: Bool = false) {
        guard updateStatus != .checking else {
            // A manual "Check for Updates…" while the automatic check is in
            // flight must not be silently swallowed - the running check's
            // outcome is presented instead.
            if presentAlert {
                presentAlertForRunningCheck = true
            }
            return
        }
        updateStatus = .checking
        // Stamped per ATTEMPT, not per success: the hourly timer would
        // otherwise retry a failing endpoint every hour - up to 24 requests
        // a day instead of the single daily request the Settings text
        // promises for this privacy-sensitive feature.
        UserDefaults.standard.set(
            Date().timeIntervalSince1970,
            forKey: Self.lastUpdateCheckKey
        )
        Task {
            defer { presentAlertForRunningCheck = false }
            do {
                let update = try await UpdateChecker().checkForUpdate()
                updateStatus = update.map { .available($0) } ?? .upToDate
                if presentAlert || presentAlertForRunningCheck {
                    presentUpdateResult(update)
                }
            } catch {
                updateStatus = .failed
                if presentAlert || presentAlertForRunningCheck {
                    presentErrorMessage(String(localized: "The update check failed. Please try again later."))
                }
            }
        }
    }

    /// Set when a manual check request arrives while a check is running, so
    /// the in-flight check presents its result as if it were the manual one.
    @ObservationIgnored private var presentAlertForRunningCheck = false

    private func presentUpdateResult(_ update: UpdateInfo?) {
        // Symmetric to the error path: the user may have switched apps
        // during the (up to 15s) check - without activation the modal alert
        // would sit invisibly behind other apps while blocking the actor.
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        if let update {
            alert.messageText = String(localized: "Version \(update.version) is available.")
            alert.informativeText = String(localized: "You are using version \(CleanDockInfo.version).")
            alert.addButton(withTitle: String(localized: "View Release"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(update.releaseURL)
            }
        } else {
            alert.messageText = String(localized: "CleanDock is up to date.")
            alert.informativeText = String(localized: "Version \(CleanDockInfo.version) is the latest release.")
            alert.addButton(withTitle: String(localized: "OK"))
            alert.runModal()
        }
    }
}
