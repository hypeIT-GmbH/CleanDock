//
//  AboutView.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import AppKit
import SwiftUI

/// Custom About window (replaces the standard panel) with a prominent
/// Buy-me-a-coffee button.
struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)

            VStack(spacing: 4) {
                Text("CleanDock")
                    .font(.title2.weight(.bold))
                Text("Version \(AppVersion.displayVersionWithBuild)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("Set the macOS Dock from profiles - locally with one click, or fleet-wide via MDM.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            HStack(spacing: 16) {
                Button("GitHub") {
                    NSWorkspace.shared.open(SupportLinks.gitHub)
                }
                .buttonStyle(.link)
                Button("License") {
                    NSWorkspace.shared.open(SupportLinks.license)
                }
                .buttonStyle(.link)
            }

            SupportCoffeeButton()

            Text(verbatim: "© \(Calendar.current.component(.year, from: .now)) hypeit GmbH · MIT License")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 320)
    }
}
