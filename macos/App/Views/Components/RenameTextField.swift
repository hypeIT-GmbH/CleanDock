//
//  RenameTextField.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import SwiftUI

/// Inline profile-rename field: edits a local draft seeded from the current
/// name and commits on ⏎ and on focus loss. Used by the sidebar row and the
/// editor header title.
struct RenameTextField: View {
    /// Current canonical profile name.
    let name: String
    /// Focus is controlled by the caller (the header focuses the field from
    /// its pencil button, the sidebar row on appear).
    @FocusState.Binding var focused: Bool
    /// Commits the draft and returns the canonical name to display - the
    /// store may trim, reject or de-duplicate the draft.
    let onCommit: (String) -> String
    /// Invoked on ⎋ without committing.
    var onExit: (() -> Void)?

    @State private var draft = ""

    init(
        name: String,
        focused: FocusState<Bool>.Binding,
        onCommit: @escaping (String) -> String,
        onExit: (() -> Void)? = nil
    ) {
        self.name = name
        self._focused = focused
        self.onCommit = onCommit
        self.onExit = onExit
    }

    var body: some View {
        TextField("Profile Name", text: $draft)
            .textFieldStyle(.plain)
            .focused($focused)
            .onSubmit { draft = onCommit(draft) }
            .onExitCommand {
                // ⎋ cancels the edit: reset the draft BEFORE the focus
                // loss, otherwise the focus-change commit below would
                // persist the half-typed draft anyway.
                draft = name
                focused = false
                onExit?()
            }
            .onAppear { draft = name }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { draft = onCommit(draft) }
            }
            .onChange(of: name) { _, newName in
                // External renames only overwrite the draft while the user
                // is not editing it.
                if !focused { draft = newName }
            }
    }
}
