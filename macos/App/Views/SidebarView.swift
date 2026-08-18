//
//  SidebarView.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import AppKit
import CleanDockCore
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var renamingProfileID: UUID?
    @State private var profilePendingDeletion: Profile?
    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            Section("Profiles") {
                ForEach(model.store.profiles) { profile in
                    SidebarProfileRow(
                        profile: profile,
                        isRenaming: renamingProfileID == profile.id,
                        endRenaming: { renamingProfileID = nil }
                    )
                    .tag(SidebarItem.profile(profile.id))
                    .contextMenu {
                        Button("Rename") {
                            renamingProfileID = profile.id
                        }
                        Button("Duplicate") {
                            model.duplicateProfile(profile)
                        }
                        Menu("Export") {
                            Button("MDM Script (postinstall)…") {
                                model.exportMDMScript(for: profile)
                            }
                            Button("Profile (JSON)…") {
                                model.exportJSON(for: profile)
                            }
                        }
                        Divider()
                        Button("Delete…", role: .destructive) {
                            profilePendingDeletion = profile
                        }
                    }
                }
            }

            if !model.managedProfiles.isEmpty {
                Section("Managed") {
                    ForEach(model.managedProfiles) { managed in
                        Label {
                            Text(managed.profile.name)
                        } icon: {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                        }
                        .badge(managed.profile.apps.count)
                        .tag(SidebarItem.managed(managed.id))
                        .help("Managed profile - deployed by your administrator, read-only.")
                        .contextMenu {
                            Button("Duplicate as My Profile") {
                                model.duplicateManagedProfile(managed)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: model.pendingRenameProfileID) { _, id in
            // A freshly created profile starts in inline renaming right away.
            if let id {
                renamingProfileID = id
                model.pendingRenameProfileID = nil
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            addButton
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.importProfiles(from: urls) > 0
        } isTargeted: {
            isDropTargeted = $0
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(4)
            }
        }
        .deleteProfileConfirmation($profilePendingDeletion) { profile in
            model.deleteProfile(profile)
        }
    }

    private var addButton: some View {
        HStack {
            Menu {
                Button {
                    model.createAndSelectProfile()
                } label: {
                    Label("New Profile", systemImage: "plus")
                }
                Button {
                    model.adoptCurrentDock()
                } label: {
                    Label("Adopt Current Dock", systemImage: "square.and.arrow.down.on.square")
                }
                Divider()
                Button {
                    model.importViaOpenPanel()
                } label: {
                    Label("Import Profile…", systemImage: "square.and.arrow.down")
                }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .hoverHighlight()
            .help("Add a profile")
            .accessibilityLabel("Add a profile")
            Spacer()
            // Deliberately subtle support link - but recognizable as one.
            Button {
                NSWorkspace.shared.open(SupportLinks.buyMeACoffee)
            } label: {
                Label("Buy me a coffee", systemImage: "cup.and.saucer.fill")
                    .font(.subheadline)
            }
            .buttonStyle(.link)
            .pointerStyle(.link)
            .hoverHighlight()
            .help("Buy me a coffee")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

private struct SidebarProfileRow: View {
    @Environment(AppModel.self) private var model
    let profile: Profile
    let isRenaming: Bool
    let endRenaming: () -> Void

    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        Label {
            if isRenaming {
                RenameTextField(
                    name: profile.name,
                    focused: $nameFieldFocused,
                    onCommit: { draft in
                        model.renameProfile(id: profile.id, to: draft)
                        endRenaming()
                        return model.store.profile(withID: profile.id)?.name ?? draft
                    },
                    onExit: endRenaming
                )
                .onAppear {
                    nameFieldFocused = true
                }
            } else {
                Text(profile.name)
            }
        } icon: {
            Image(systemName: profile.symbol)
                .symbolRenderingMode(.hierarchical)
        }
        .badge(isRenaming ? 0 : profile.apps.count)
    }
}
