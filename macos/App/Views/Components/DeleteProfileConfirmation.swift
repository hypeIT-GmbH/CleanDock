//
//  DeleteProfileConfirmation.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import CleanDockCore
import SwiftUI

extension View {
    /// The one shared "Delete profile" confirmation, used by the sidebar
    /// context menu and the editor toolbar. Presents while `profile` holds a
    /// value; dismissal clears it through the presence binding.
    func deleteProfileConfirmation(
        _ profile: Binding<Profile?>,
        onDelete: @escaping (Profile) -> Void
    ) -> some View {
        confirmationDialog(
            "Delete profile “\(profile.wrappedValue?.name ?? "")”?",
            isPresented: Binding(presence: profile),
            titleVisibility: .visible,
            presenting: profile.wrappedValue
        ) { profile in
            Button("Delete", role: .destructive) {
                onDelete(profile)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The profile will be removed permanently. Your Dock is not changed.")
        }
    }
}
