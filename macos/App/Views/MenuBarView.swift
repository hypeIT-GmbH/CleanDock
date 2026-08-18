//
//  MenuBarView.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import AppKit
import CleanDockCore
import SwiftUI

/// Menu bar extra: one click on a profile applies it immediately - no
/// confirmation, no main window needed. Deliberately no support links here.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            if model.store.profiles.isEmpty && model.managedProfiles.isEmpty {
                Text("No profiles yet")
            }
            ForEach(model.store.profiles) { profile in
                Button {
                    model.applyProfile(profile, notify: true)
                } label: {
                    Label(profile.name, systemImage: profile.symbol)
                }
            }
            if !model.managedProfiles.isEmpty {
                Divider()
                ForEach(model.managedProfiles) { managed in
                    Button {
                        model.applyProfile(managed.profile, isManaged: true, notify: true)
                    } label: {
                        Label(managed.profile.name, systemImage: "lock.fill")
                    }
                }
            }
            Divider()
            if let update = model.availableUpdate {
                Button {
                    NSWorkspace.shared.open(update.releaseURL)
                } label: {
                    Label(
                        String(localized: "Update available: \(update.version)…"),
                        systemImage: "arrow.down.circle"
                    )
                }
                Divider()
            }
            Button("Open CleanDock…") {
                openMainWindow()
            }
            Button("Settings…") {
                // Open the window BEFORE activating: activating the app while
                // it has no visible window makes SwiftUI present the main
                // window, which would then lurk behind the settings window.
                // Activating afterwards merely brings settings to the front.
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button("Quit CleanDock") {
                // Quitting from the menu bar is unambiguous - skip the dialog.
                AppDelegate.isForceQuitting = true
                NSApp.terminate(nil)
            }
        }
        // No onAppear side effects here: the menu host evaluates this content
        // eagerly at launch, and mutating observable state during that pass
        // live-locks the menu graph. State is refreshed by the main window
        // and after every profile operation instead.
    }

    private func openMainWindow() {
        AppDelegate.regainDockPresenceAndActivate()
        openWindow(id: WindowID.main)
    }
}
