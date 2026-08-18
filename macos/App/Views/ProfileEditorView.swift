//
//  ProfileEditorView.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import CleanDockCore
import SwiftUI
import UniformTypeIdentifiers

struct ProfileEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let profileID: UUID

    @State private var selectedAppIDs: Set<UUID> = []
    @State private var profilePendingDeletion: Profile?

    private var profile: Profile? {
        model.store.profile(withID: profileID)
    }

    var body: some View {
        if let profile {
            VStack(spacing: 0) {
                ProfileHeaderView(profile: profile)
                Divider()
                appList(for: profile)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                CleanupFooterView(profile: profile, isManaged: false)
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    AddAppButton(profileID: profile.id)
                    Menu {
                        Button("Choose from File Dialog…") {
                            model.addAppsViaOpenPanel(to: profile.id)
                        }
                        Divider()
                        Button("Delete Profile…", role: .destructive) {
                            profilePendingDeletion = profile
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .help("More actions")
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.3), value: profile.apps.map(\.id))
            .deleteProfileConfirmation($profilePendingDeletion) { profile in
                model.deleteProfile(profile)
            }
        }
    }

    // MARK: - App list

    private func appList(for profile: Profile) -> some View {
        // Finder and Trash are always part of the Dock - shown as fixed,
        // non-editable rows so the profile reads as the complete Dock.
        List(selection: $selectedAppIDs) {
            FixedDockRowView(kind: .finder)
            ForEach(profile.apps) { app in
                AppRowView(
                    app: app,
                    onRemove: { removeApps(ids: [app.id]) }
                )
                .tag(app.id)
                .contextMenu {
                    Button("Remove", role: .destructive) {
                        if selectedAppIDs.contains(app.id), selectedAppIDs.count > 1 {
                            removeApps(ids: selectedAppIDs)
                        } else {
                            removeApps(ids: [app.id])
                        }
                    }
                }
            }
            .onMove { source, destination in
                model.updateProfile(id: profile.id) {
                    $0.apps.move(fromOffsets: source, toOffset: destination)
                }
            }
            .onInsert(of: [UTType.fileURL]) { index, providers in
                insertDroppedApps(at: index, providers: providers)
            }
            if profile.apps.isEmpty {
                emptyAppsPlaceholder(for: profile)
            }
            FixedDockRowView(kind: .trash)
        }
        .listStyle(.inset)
        .onDeleteCommand {
            removeApps(ids: selectedAppIDs)
        }
    }

    private func emptyAppsPlaceholder(for profile: Profile) -> some View {
        VStack(spacing: 10) {
            Text("No Apps in This Profile")
                .font(.headline)
            Text("Add apps from the picker, drag them in from the Finder, or choose them from a file dialog.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            AddAppButton(profileID: profile.id, prominent: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .selectionDisabled()
        .dropDestination(for: URL.self) { urls, _ in
            model.addApps(urls: urls, to: profile.id) > 0
        }
    }

    // MARK: - Actions

    private func removeApps(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        model.updateProfile(id: profileID) {
            $0.apps.removeAll { ids.contains($0.id) }
        }
        selectedAppIDs.subtract(ids)
    }

    private func insertDroppedApps(at index: Int, providers: [NSItemProvider]) {
        Task {
            let urls = await FileURLLoader.urls(from: providers)
            model.addApps(urls: urls, to: profileID, at: index)
        }
    }
}

// MARK: - Header

private struct ProfileHeaderView: View {
    @Environment(AppModel.self) private var model
    let profile: Profile

    @State private var showingSymbolPicker = false
    @State private var isHoveringName = false
    @FocusState private var nameFocused: Bool
    @FocusState private var pencilFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    showingSymbolPicker = true
                } label: {
                    ProfileSymbolBadge(symbol: profile.symbol)
                }
                .buttonStyle(.plain)
                .help("Choose a symbol")
                // Without a label VoiceOver announces the currently chosen
                // SF Symbol's name, which misdescribes the button's purpose.
                .accessibilityLabel("Choose a symbol")
                .popover(isPresented: $showingSymbolPicker, arrowEdge: .bottom) {
                    SymbolPickerView(selectedSymbol: profile.symbol) { symbol in
                        model.updateProfile(id: profile.id) { $0.symbol = symbol }
                        showingSymbolPicker = false
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    // Hover affordance (background + pencil), the standard
                    // pattern for inline-editable titles on macOS.
                    HStack(spacing: 6) {
                        RenameTextField(
                            name: profile.name,
                            focused: $nameFocused,
                            onCommit: { draft in
                                model.renameProfile(id: profile.id, to: draft)
                                return model.store.profile(withID: profile.id)?.name ?? draft
                            }
                        )
                        .font(.largeTitle.weight(.bold))
                        if !nameFocused {
                            Button {
                                nameFocused = true
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .focused($pencilFocused)
                            .help("Rename profile")
                            .accessibilityLabel("Rename profile")
                            // Faded, not conditionally removed: a hover-only
                            // button would not exist for VoiceOver and Full
                            // Keyboard Access - and keyboard focus must
                            // reveal it just like hover does.
                            .opacity(isHoveringName || pencilFocused ? 1 : 0)
                        }
                    }
                    .padding(.horizontal, 6)
                    // Named rotor action as the reliable assistive path to
                    // start renaming, independent of the faded pencil.
                    .accessibilityAction(named: Text("Rename profile")) {
                        nameFocused = true
                    }
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill((isHoveringName || nameFocused)
                                  ? AnyShapeStyle(.quaternary.opacity(0.6))
                                  : AnyShapeStyle(.clear))
                    )
                    .onHover { isHoveringName = $0 }
                    Text("\(profile.apps.count) apps")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                }
            }

            Toggle("Hide “Recent Applications” in the Dock", isOn: Binding(
                get: { profile.hideRecents },
                set: { newValue in
                    model.updateProfile(id: profile.id) { $0.hideRecents = newValue }
                }
            ))
            .toggleStyle(.checkbox)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
