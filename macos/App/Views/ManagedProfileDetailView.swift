//
//  ManagedProfileDetailView.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import CleanDockCore
import SwiftUI

/// Read-only detail view for a managed (MDM-deployed) profile.
/// It can be applied, but never edited.
struct ManagedProfileDetailView: View {
    let managedProfile: ManagedProfile

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List {
                FixedDockRowView(kind: .finder)
                ForEach(managedProfile.profile.apps) { app in
                    AppRowView(app: app, onRemove: nil)
                }
                if managedProfile.profile.apps.isEmpty {
                    VStack(spacing: 6) {
                        Text("Empty Profile")
                            .font(.headline)
                        Text("Applying this profile clears the left side of the Dock.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
                FixedDockRowView(kind: .trash)
            }
            .listStyle(.inset)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CleanupFooterView(profile: managedProfile.profile, isManaged: true)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ProfileSymbolBadge(symbol: managedProfile.profile.symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(managedProfile.profile.name)
                        .font(.largeTitle.weight(.bold))
                    Text("\(managedProfile.profile.apps.count) apps")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Label {
                Text("Managed profile - deployed by your administrator, read-only.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
            }
            Text(managedProfile.fileURL.path)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
