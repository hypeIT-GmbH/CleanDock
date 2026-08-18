//
//  SettingsView.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import AppKit
import CleanDockCore
import ServiceManagement
import SwiftUI

/// The settings window: one focused tab per topic, sized so no tab needs to
/// scroll.
struct SettingsView: View {
    private enum Tab: Hashable {
        case general, updates, storage, support, about
    }

    @State private var selectedTab: Tab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(Tab.general)
            UpdatesSettingsView()
                .tabItem {
                    Label("Updates", systemImage: "arrow.down.circle")
                }
                .tag(Tab.updates)
            StorageSettingsView()
                .tabItem {
                    Label("Storage", systemImage: "externaldrive")
                }
                .tag(Tab.storage)
            SupportSettingsView()
                .tabItem {
                    Label("Support", systemImage: "heart")
                }
                .tag(Tab.support)
            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(Tab.about)
        }
        .frame(width: 600, height: 440)
        // The window must always OPEN on General - the system would
        // otherwise restore the last selected tab across sessions.
        .onAppear { selectedTab = .general }
        .onDisappear { selectedTab = .general }
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @State private var launchAtLogin = false
    @State private var launchAtLoginError: String?
    @AppStorage(AppModel.showMenuBarIconKey) private var showMenuBarIcon = true
    @AppStorage(QuitBehavior.defaultsKey) private var quitBehavior = QuitBehavior.ask

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Toggle(isOn: $showMenuBarIcon) {
                    HStack(spacing: 6) {
                        Text("Show in menu bar")
                        InfoBadge(text: "Without the menu bar icon, ⌘Q always quits the app completely.")
                    }
                }
                .onChange(of: showMenuBarIcon) { _, _ in
                    AppDelegate.refreshActivationPolicy()
                }
                Picker("When quitting with ⌘Q", selection: $quitBehavior) {
                    Text("Ask Each Time").tag(QuitBehavior.ask)
                    Text("Quit Completely").tag(QuitBehavior.quit)
                    Text("Keep Running in Menu Bar").tag(QuitBehavior.menuBar)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        // No-op changes (the toggle revert after an error, the onAppear
        // initialization) must neither clear an error message just set nor
        // re-issue a registration call.
        guard enabled != (SMAppService.mainApp.status == .enabled) else { return }
        launchAtLoginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Updates

private struct UpdatesSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                LabeledContent("Installed version") {
                    Text(verbatim: AppVersion.displayVersion)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle(isOn: $model.automaticUpdateChecks) {
                    HStack(spacing: 6) {
                        Text("Check for updates automatically")
                        InfoBadge(text: "Once a day, CleanDock asks GitHub for the latest release. No other data is sent - this is the app’s only network access and it stays off unless you enable it.")
                    }
                }
            }

            Section {
                LabeledContent("Status") {
                    updateStatusView
                }
                Button("Check Now") {
                    model.checkForUpdates()
                }
                .disabled(model.updateStatus == .checking)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch model.updateStatus {
        case .unknown:
            Text(verbatim: "-")
                .foregroundStyle(.secondary)
        case .checking:
            Text("Checking…")
                .foregroundStyle(.secondary)
        case .upToDate:
            Text("CleanDock is up to date.")
                .foregroundStyle(.secondary)
        case .available(let update):
            Button("Version \(update.version) is available.") {
                NSWorkspace.shared.open(update.releaseURL)
            }
            .buttonStyle(.link)
        case .failed:
            Text("The update check failed. Please try again later.")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Storage

private struct StorageSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmClearBackups = false
    @State private var backups: [BackupService.BackupInfo] = []
    @State private var backupPendingRestore: BackupService.BackupInfo?

    var body: some View {
        Form {
            Section {
                if backups.isEmpty {
                    Text("No backups yet - one is created automatically before every load.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(backups) { backup in
                        BackupRow(
                            backup: backup,
                            onRestore: { backupPendingRestore = backup },
                            onSaveAsProfile: {
                                model.saveBackupAsProfile(backup)
                            }
                        )
                    }
                }
                HStack {
                    Button("Show in Finder") {
                        showInFinder(model.backupService.directory)
                    }
                    Button("Delete Backups…", role: .destructive) {
                        confirmClearBackups = true
                    }
                    // Keyed off the list shown right above, not the model's
                    // Undo flag - the two snapshots can briefly disagree.
                    .disabled(backups.isEmpty)
                }
            } header: {
                HStack(spacing: 6) {
                    Text("Backups")
                    InfoBadge(text: "A backup of the Dock is written before every load; the ten most recent are kept. Restoring puts that Dock back - the current Dock is saved as a new backup first.")
                }
            }

            Section {
                LabeledContent {
                    Text(model.managedService.managedDirectory.path)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                } label: {
                    HStack(spacing: 6) {
                        Text("Location")
                        InfoBadge(text: "Administrators can deploy read-only profiles to this folder via MDM.")
                    }
                }
                Button("Show in Finder") {
                    showInFinder(model.managedService.managedDirectory)
                }
            } header: {
                Text("Managed Profiles")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshBackups()
        }
        .confirmationDialog(
            "Delete all Dock backups?",
            isPresented: $confirmClearBackups,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                do {
                    try model.backupService.removeAll()
                } catch {
                    model.presentError(error)
                }
                model.refresh()
                refreshBackups()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("“Undo” will not be available until the next cleanup.")
        }
        .confirmationDialog(
            "Restore the Dock from this backup?",
            isPresented: Binding(presence: $backupPendingRestore),
            titleVisibility: .visible,
            presenting: backupPendingRestore
        ) { backup in
            Button("Restore") {
                model.restoreBackup(backup)
                refreshBackups()
            }
            Button("Cancel", role: .cancel) {}
        } message: { backup in
            Text("The Dock will be set to the state of \(backup.date.formatted(date: .abbreviated, time: .shortened)). The current Dock is saved as a new backup first.")
        }
    }

    private func refreshBackups() {
        backups = model.backupService.backupInfos()
    }

    private func showInFinder(_ url: URL) {
        // Finder cannot reveal a folder that does not exist yet - create it
        // first so the button never silently does nothing. Creation can
        // legitimately fail: the managed directory lives under /Library and
        // is only created by the installer/MDM as root. Reveal the deepest
        // EXISTING ancestor then - still better than a dead button.
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        var target = url
        while !FileManager.default.fileExists(atPath: target.path), target.path != "/" {
            target = target.deletingLastPathComponent()
        }
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }
}

/// One backup snapshot: timestamp, app count and its two actions.
private struct BackupRow: View {
    let backup: BackupService.BackupInfo
    let onRestore: () -> Void
    let onSaveAsProfile: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(backup.date.formatted(date: .abbreviated, time: .shortened))
                Text("\(backup.appCount) apps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Restore") {
                onRestore()
            }
            Menu {
                Button("Save as Profile") {
                    onSaveAsProfile()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More actions")
        }
    }
}

// MARK: - Support

private struct SupportSettingsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "cup.and.saucer.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)

            Text("Thank you for using CleanDock!")
                .font(.title3.weight(.semibold))

            Text("CleanDock is free and open source. Voluntary support keeps the project alive.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            SupportCoffeeButton()
                .padding(.top, 4)

            Button("⭐️ Star on GitHub") {
                NSWorkspace.shared.open(SupportLinks.gitHub)
            }
            .buttonStyle(.link)

            Divider()
                .frame(maxWidth: 380)
                .padding(.vertical, 4)

            // Feedback belongs next to the support links: bug reports and
            // feature requests are the other way users give back.
            Text("Found a bug or have an idea?")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Report a Problem…") {
                NSWorkspace.shared.open(SupportLinks.newIssue)
            }
            .buttonStyle(.link)

            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - About

private struct AboutSettingsView: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Version") {
                    Text(verbatim: AppVersion.displayVersion)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Provider") {
                // Full German Impressum (§ 5 DDG) - legal text, deliberately
                // not localized.
                Text(verbatim: """
                hypeit GmbH
                Prenzlauer Allee 52
                D-10405 Berlin

                Vertreten durch:
                Yannik Piwowarski und Markus Rabsch

                Telefon: +49 30 1663 883 0
                Amtsgericht Charlottenburg, HRB 284622
                USt-IdNr.: DE 32 54 43 284
                """)
                    .textSelection(.enabled)
            }

            Section("Open Source") {
                Text("CleanDock is open source software under the MIT license.")
                Text("No third-party frameworks are bundled - CleanDock uses only Apple system frameworks.")
                HStack {
                    Button("View on GitHub") {
                        NSWorkspace.shared.open(SupportLinks.gitHub)
                    }
                    Button("License") {
                        NSWorkspace.shared.open(SupportLinks.license)
                    }
                }
            }

            Section("Thanks") {
                Text("Thanks to everyone contributing issues, ideas and code - and to every supporter who keeps the project alive. ☕️")
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
    }
}
