//
//  AppPickerView.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import CleanDockCore
import SwiftUI

/// Searchable grid of all applications found in the standard folders.
/// Supports multi-selection; apps already in the profile are marked.
struct AppPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let profileID: UUID

    @State private var apps: [InstalledApp] = []
    @State private var searchText = ""
    @State private var selectedPaths: Set<String> = []
    @State private var isLoading = true

    /// Paths AND bundle IDs already in the profile - imported profiles may
    /// carry foreign paths or path-less, bundle-ID-only entries, so a path
    /// comparison alone would miss them.
    private struct ExistingApps {
        let paths: Set<String>
        let bundleIDs: Set<String>

        func contains(_ app: InstalledApp) -> Bool {
            paths.contains(app.url.path)
                || (app.bundleID.map(bundleIDs.contains) ?? false)
        }
    }

    private var existingApps: ExistingApps {
        let profileApps = model.store.profile(withID: profileID)?.apps ?? []
        return ExistingApps(
            paths: Set(profileApps.compactMap(\.path)),
            bundleIDs: Set(profileApps.compactMap(\.bundleID))
        )
    }

    private var filteredApps: [InstalledApp] {
        guard !searchText.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            grid
            Divider()
            footer
        }
        .frame(width: 640, height: 480)
        .task {
            let resolver = model.resolver
            // Deliberately detached from the .task lifecycle: the scan is a
            // short, side-effect-free directory read - cancelling it on
            // dismiss would buy nothing, it just runs to its harmless end.
            let installed = await Task.detached(priority: .userInitiated) {
                resolver.installedApplications()
            }.value
            apps = installed
            isLoading = false
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search apps", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(12)
    }

    @ViewBuilder
    private var grid: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredApps.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Computed once per grid evaluation - the sets would otherwise be
            // rebuilt from the profile's apps for every single cell.
            let existing = existingApps
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(filteredApps) { app in
                        AppPickerCell(
                            app: app,
                            isSelected: selectedPaths.contains(app.url.path),
                            isAlreadyInProfile: existing.contains(app)
                        ) {
                            toggle(app)
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("\(selectedPaths.count) selected")
                .font(.callout)
                .foregroundStyle(.secondary)
                .opacity(selectedPaths.isEmpty ? 0 : 1)
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button("Add") {
                let selected = apps.filter { selectedPaths.contains($0.url.path) }
                model.addApps(selected, to: profileID)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(selectedPaths.isEmpty)
        }
        .padding(12)
    }

    private func toggle(_ app: InstalledApp) {
        if selectedPaths.contains(app.url.path) {
            selectedPaths.remove(app.url.path)
        } else {
            selectedPaths.insert(app.url.path)
        }
    }
}

private struct AppPickerCell: View {
    let app: InstalledApp
    let isSelected: Bool
    let isAlreadyInProfile: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onToggle) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    AppIconView(path: app.url.path, isInstalled: true)
                        .frame(width: 48, height: 48)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white, Color.accentColor)
                            .background(Circle().fill(.background))
                            .offset(x: 6, y: -4)
                    }
                }
                Text(app.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                // Rendered invisibly when absent so all cells keep the same
                // height and the grid rows stay aligned.
                Text("In profile")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .opacity(isAlreadyInProfile ? 1 : 0)
                    .accessibilityHidden(!isAlreadyInProfile)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundStyle)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isAlreadyInProfile ? 0.55 : 1)
        .onHover { isHovered = $0 }
        .help(app.url.path)
        // The checkmark overlay is visual only - VoiceOver needs the state
        // as a trait to announce toggles.
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var backgroundStyle: AnyShapeStyle {
        if isSelected {
            AnyShapeStyle(Color.accentColor.opacity(0.18))
        } else if isHovered {
            AnyShapeStyle(.quaternary.opacity(0.5))
        } else {
            AnyShapeStyle(.clear)
        }
    }
}
