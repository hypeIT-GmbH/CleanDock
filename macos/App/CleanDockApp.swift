//
//  CleanDockApp.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import AppKit
import SwiftUI

enum WindowID {
    static let main = "main"
    static let about = "about"
}

@main
struct CleanDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    // AppStorage gives the scene a STABLE binding. Recreating a binding on
    // every body evaluation (e.g. via Bindable(model)) makes the scene see a
    // changed input each pass and live-locks the menu graph in an
    // invalidate/rebuild loop.
    @AppStorage(AppModel.showMenuBarIconKey) private var showMenuBarIcon = true

    var body: some Scene {
        Window("CleanDock", id: WindowID.main) {
            ContentView()
                .environment(model)
                // Wide enough for the single-line cleanup feedback between
                // the Undo and Load Profile buttons, in German too.
                .frame(minWidth: 980, minHeight: 580)
        }
        .defaultSize(width: 1060, height: 640)
        .commands {
            AppCommands(model: model)
        }

        Window("About CleanDock", id: WindowID.about) {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // Quick cleanup from the menu bar, also while the main window is
        // closed. The icon can be disabled in Settings.
        MenuBarExtra(
            "CleanDock",
            systemImage: "dock.rectangle",
            isInserted: $showMenuBarIcon
        ) {
            MenuBarView()
                .environment(model)
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

/// Keeps the app alive when the main window closes (the menu bar extra keeps
/// running), manages the Dock presence and intercepts ⌘Q with a
/// "quit completely vs. keep in menu bar" choice.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the menu bar extra's explicit quit button - that intent is
    /// unambiguous, so the quit dialog is skipped.
    static var isForceQuitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Tooltips (help modifiers) otherwise take seconds to appear -
        // AppKit reads this per-app override in milliseconds.
        UserDefaults.standard.set(400, forKey: "NSInitialToolTipDelay")

        // Re-evaluate the Dock presence whenever a window closes: with the
        // menu bar icon enabled, the app leaves the Dock once its last
        // window is gone. Evaluated on the next runloop turn because the
        // closing window still counts as visible during willClose.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    AppDelegate.refreshActivationPolicy()
                }
            }
        }
    }

    /// Dock presence rule: with the menu bar icon enabled the app shows in
    /// the Dock only while a regular window is open; without the icon it
    /// always keeps its Dock presence (it would be unreachable otherwise).
    /// Deliberately touches no observable state - safe to call from window
    /// lifecycle events.
    static func refreshActivationPolicy() {
        guard AppModel.isMenuBarIconEnabled else {
            NSApp.setActivationPolicy(.regular)
            return
        }
        let hasVisibleWindow = NSApp.windows.contains {
            $0.isVisible && $0.styleMask.contains(.closable)
        }
        NSApp.setActivationPolicy(hasVisibleWindow ? .regular : .accessory)
    }

    /// Brings the app forward when the main window is opened from the
    /// menu bar; the window would otherwise appear behind the frontmost app.
    /// Also regains the Dock icon, which is dropped while the app lives
    /// menu-bar-only (see refreshActivationPolicy).
    static func regainDockPresenceAndActivate() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // Relaunching from Finder/Spotlight while the app lives menu-bar-only:
        // the reopened window needs its Dock presence back.
        NSApp.setActivationPolicy(.regular)
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // The flag is one-shot: a cancelled termination must not skip the
        // quit dialog on a later ordinary ⌘Q.
        defer { Self.isForceQuitting = false }
        if Self.isForceQuitting {
            return .terminateNow
        }
        // Logout, restart and shutdown deliver the quit AppleEvent with a
        // kAEQuitReason attribute; a plain user quit (⌘Q, Dock menu) carries
        // none. Never intercept system-initiated quits: returning
        // .terminateCancel would abort the user's logout with CleanDock
        // named as the culprit, and the modal dialog below would stall a
        // shutdown until someone answers it.
        if quitIsSystemInitiated {
            return .terminateNow
        }
        // Without a menu bar icon, "keep running in the menu bar" would leave
        // the app unreachable - quitting then always quits completely.
        guard AppModel.isMenuBarIconEnabled else {
            return .terminateNow
        }
        let defaults = UserDefaults.standard
        switch QuitBehavior(rawValue: defaults.string(forKey: QuitBehavior.defaultsKey) ?? "") ?? .ask {
        case .quit:
            return .terminateNow
        case .menuBar:
            keepRunningInMenuBar(sender)
            return .terminateCancel
        case .ask:
            break
        }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = String(localized: "Quit CleanDock completely?")
        alert.informativeText = String(
            localized: "CleanDock can keep running in the menu bar so your profiles stay one click away."
        )
        alert.addButton(withTitle: String(localized: "Quit Completely"))
        alert.addButton(withTitle: String(localized: "Keep Running in Menu Bar"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = String(localized: "Don’t ask again")

        let response = alert.runModal()
        let remember = alert.suppressionButton?.state == .on
        switch response {
        case .alertFirstButtonReturn:
            if remember {
                defaults.set(QuitBehavior.quit.rawValue, forKey: QuitBehavior.defaultsKey)
            }
            return .terminateNow
        case .alertSecondButtonReturn:
            if remember {
                defaults.set(QuitBehavior.menuBar.rawValue, forKey: QuitBehavior.defaultsKey)
            }
            keepRunningInMenuBar(sender)
            return .terminateCancel
        default:
            return .terminateCancel
        }
    }

    /// True while the currently handled AppleEvent is a quit that macOS
    /// sent on behalf of a logout, restart or shutdown (those carry a
    /// kAEQuitReason attribute - any reason at all means the quit is not a
    /// plain user quit).
    private var quitIsSystemInitiated: Bool {
        NSAppleEventManager.shared()
            .currentAppleEvent?
            .attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason)) != nil
    }

    /// Cancels termination but closes all regular windows and drops the
    /// Dock presence, so the app fully "disappears" into the menu bar.
    private func keepRunningInMenuBar(_ application: NSApplication) {
        for window in application.windows
        where window.isVisible && window.styleMask.contains(.closable) {
            window.close()
        }
        Self.refreshActivationPolicy()
    }
}

/// The persisted ⌘Q behavior ("ask" is the default when unset).
enum QuitBehavior: String {
    case ask
    case quit
    case menuBar = "menubar"

    static let defaultsKey = "quitBehavior"
}

struct AppCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About CleanDock") {
                openWindow(id: WindowID.about)
            }
        }
        CommandGroup(replacing: .newItem) {
            Button("New Profile") {
                model.createAndSelectProfile()
            }
            .keyboardShortcut("n", modifiers: .command)
            Button("Adopt Current Dock") {
                model.adoptCurrentDock()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Import Profile…") {
                model.importViaOpenPanel()
            }
        }
        CommandGroup(replacing: .help) {
            Button("View on GitHub") {
                NSWorkspace.shared.open(SupportLinks.gitHub)
            }
            Button("Report a Problem…") {
                NSWorkspace.shared.open(SupportLinks.newIssue)
            }
            Divider()
            Button("Check for Updates…") {
                model.checkForUpdates(presentAlert: true)
            }
        }
    }
}
