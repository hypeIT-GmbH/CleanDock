//
//  FixedDockRowView.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import AppKit
import SwiftUI

/// Display-only rows for Finder and Trash - they are always part of the Dock
/// (not part of `persistent-apps`), shown so a profile reads as the complete
/// Dock: Finder first, Trash last.
struct FixedDockRowView: View {
    enum Kind {
        case finder
        case trash
    }

    let kind: Kind

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                name
                Text("Always in the Dock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Image(systemName: "pin.fill")
                .font(.caption)
                .foregroundStyle(.quaternary)
                .help("Finder and Trash are fixed parts of the Dock and are never changed by CleanDock.")
        }
        .padding(.vertical, 4)
        .opacity(0.75)
        .selectionDisabled()
    }

    private var name: Text {
        switch kind {
        case .finder: Text("Finder")
        case .trash: Text("Trash")
        }
    }

    private var icon: NSImage {
        switch kind {
        case .finder:
            return NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")
        case .trash:
            let trashIconPath =
                "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/TrashIcon.icns"
            if let image = NSImage(contentsOfFile: trashIconPath) {
                return image
            }
            return NSWorkspace.shared.icon(for: .folder)
        }
    }
}
