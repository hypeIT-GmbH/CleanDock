//
//  SupportPromptView.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import AppKit
import SwiftUI

/// Presents the support prompt in its own small centered window - it must
/// work from every load path, including menu bar loads without any open
/// window, which rules out sheets.
@MainActor
enum SupportPrompt {
    private static var window: NSWindow?
    /// Token of the willClose observer - held so repeated prompt cycles
    /// never accumulate dead observers in the NotificationCenter.
    private static var closeObserver: (any NSObjectProtocol)?

    static func present(model: AppModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(
            rootView: SupportPromptView(model: model) { close() }
        )
        let promptWindow = NSWindow(contentViewController: hosting)
        promptWindow.styleMask = [.titled, .closable, .fullSizeContentView]
        promptWindow.titlebarAppearsTransparent = true
        promptWindow.titleVisibility = .hidden
        promptWindow.isMovableByWindowBackground = true
        promptWindow.isReleasedWhenClosed = false
        promptWindow.center()
        window = promptWindow

        // Closing via the title bar must also drop our reference.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: promptWindow,
            queue: .main
        ) { _ in
            Task { @MainActor in
                SupportPrompt.window = nil
                SupportPrompt.removeCloseObserver()
            }
        }

        // Order the window in WITHOUT activating the app (plain NSWindow -
        // the non-activation comes solely from orderFrontRegardless): 1.2s
        // after a menu bar cleanup the user is usually back in another app,
        // and an unsolicited donation prompt must never yank the focus out
        // of their work (the spec's no-nagging rule).
        promptWindow.orderFrontRegardless()
    }

    static func close() {
        window?.close()
        window = nil
        removeCloseObserver()
    }

    private static func removeCloseObserver() {
        guard let closeObserver else { return }
        NotificationCenter.default.removeObserver(closeObserver)
        Self.closeObserver = nil
    }
}

/// The friendly ask: CleanDock is free - a coffee keeps it going.
/// The opt-out checkbox writes immediately, so every way of closing the
/// window respects it.
struct SupportPromptView: View {
    let model: AppModel
    let dismiss: () -> Void

    @State private var dontShowAgain = false

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.65)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 72, height: 72)
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
            }
            .padding(.top, 6)

            Text("Enjoying CleanDock?")
                .font(.title2.weight(.bold))

            Text("CleanDock is free and open source. Voluntary support keeps the project alive.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 310)

            SupportCoffeeButton()
                .padding(.top, 2)

            Button("⭐️ Star on GitHub") {
                NSWorkspace.shared.open(SupportLinks.gitHub)
            }
            .buttonStyle(.link)

            Divider()
                .padding(.top, 4)

            HStack {
                Toggle("Don’t show this again", isOn: $dontShowAgain)
                    .toggleStyle(.checkbox)
                    .font(.callout)
                    .onChange(of: dontShowAgain) { _, optOut in
                        model.setSupportPromptOptOut(optOut)
                    }
                Spacer()
                Button("Maybe Later") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
