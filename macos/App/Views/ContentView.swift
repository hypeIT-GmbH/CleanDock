//
//  ContentView.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import CleanDockCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
                // The system toggle migrates between the toolbar's sidebar and
                // detail sections while the columns animate - that re-layout
                // briefly flashes the overflow chevron ("»"). A custom toggle
                // pinned to the detail section avoids the migration.
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(reduceMotion ? nil : .default) {
                        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                    }
                } label: {
                    Label("Toggle Sidebar", systemImage: "sidebar.leading")
                }
                .keyboardShortcut("s", modifiers: [.control, .command])
                .help("Show or hide the sidebar")
            }
        }
        .onAppear {
            model.refresh()
        }
        .alert(
            "An Error Occurred",
            isPresented: Binding(presence: $model.errorMessage)
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selection {
        case .profile(let id):
            if model.store.profile(withID: id) != nil {
                // .id resets editor state (name draft, selection) per profile.
                ProfileEditorView(profileID: id)
                    .id(id)
            } else {
                noSelectionPlaceholder
            }
        case .managed(let managedID):
            if let managed = model.managedProfiles.first(where: { $0.id == managedID }) {
                ManagedProfileDetailView(managedProfile: managed)
                    .id(managedID)
            } else {
                noSelectionPlaceholder
            }
        case nil:
            noSelectionPlaceholder
        }
    }

    private var noSelectionPlaceholder: some View {
        ContentUnavailableView {
            Label("No Profile Selected", systemImage: "dock.rectangle")
        } description: {
            Text("Select a profile in the sidebar or create a new one.")
        } actions: {
            Button {
                model.createAndSelectProfile()
            } label: {
                Label("New Profile", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
