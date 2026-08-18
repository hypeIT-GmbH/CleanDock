//
//  AppRowView.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import CleanDockCore
import SwiftUI

/// One app row in a profile list (editable and managed detail views).
/// Resolves the entry against the local machine to show the real icon and a
/// "Not installed" badge where needed.
struct AppRowView: View {
    /// Task identity for the row resolution: the app plus the model's
    /// resolution epoch, so refresh() re-resolves already-visible rows.
    private struct ResolutionKey: Equatable {
        let app: DockApp
        let epoch: Int
    }

    /// Result of resolving the profile entry on this Mac.
    private enum Resolution: Equatable {
        case pending
        case installed(URL)
        case notInstalled
    }

    @Environment(AppModel.self) private var model
    let app: DockApp
    var onRemove: (() -> Void)?

    @State private var resolution: Resolution = .pending
    @State private var isHovered = false
    @FocusState private var removeFocused: Bool

    private var isInstalled: Bool {
        if case .installed = resolution { return true }
        return false
    }

    private var resolvedPath: String? {
        if case .installed(let url) = resolution { return url.path }
        return nil
    }

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(path: resolvedPath ?? app.path, isInstalled: isInstalled)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .lineLimit(1)
                    if resolution == .notInstalled {
                        Text("Not installed")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.quaternary))
                            .foregroundStyle(.secondary)
                            .help("This app is currently not installed on this Mac. It will be skipped - that is not an error.")
                    }
                }
                Text(resolvedPath ?? app.path ?? app.bundleID ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .opacity(resolution == .notInstalled ? 0.6 : 1)

            Spacer(minLength: 8)

            if let onRemove {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .focused($removeFocused)
                .help("Remove from profile")
                .accessibilityLabel("Remove from profile")
                // Faded, not conditionally removed: an `if isHovered` button
                // would not exist for VoiceOver and Full Keyboard Access -
                // and keyboard focus must reveal it just like hover does.
                .opacity(isHovered || removeFocused ? 1 : 0)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        // Named rotor action as the reliable assistive path: whether
        // VoiceOver exposes the faded (opacity 0) remove button is not
        // guaranteed across releases - this action always is.
        .accessibilityActions {
            if let onRemove {
                Button("Remove from profile", action: onRemove)
            }
        }
        .task(id: ResolutionKey(app: app, epoch: model.resolutionEpoch)) {
            // Cached in the model (first resolution runs off the main
            // actor); the epoch in the key re-runs this task after
            // refresh(), so visible badges pick up installs/uninstalls.
            let url = await model.resolvedURL(for: app)
            // A newer task (epoch bump) may already have written a fresh
            // result - a cancelled task must not overwrite it.
            guard !Task.isCancelled else { return }
            if let url {
                resolution = .installed(url)
            } else {
                resolution = .notInstalled
            }
        }
    }
}
