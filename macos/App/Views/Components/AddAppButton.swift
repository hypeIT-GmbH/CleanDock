//
//  AddAppButton.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import SwiftUI

/// Toolbar/placeholder button that opens the app picker. Deliberately a
/// plain button: a split button (Menu with primaryAction) in the toolbar
/// briefly renders as a bare chevron segment during sidebar show/hide
/// re-layout. The NSOpenPanel fallback lives in the editor's "More" menu.
struct AddAppButton: View {
    let profileID: UUID
    var prominent = false

    @State private var showingPicker = false

    var body: some View {
        Button {
            showingPicker = true
        } label: {
            Label("Add App", systemImage: "plus")
        }
        .modifier(AddAppButtonStyle(prominent: prominent))
        .help("Add apps to this profile")
        .sheet(isPresented: $showingPicker) {
            AppPickerView(profileID: profileID)
        }
    }
}

private struct AddAppButtonStyle: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if prominent {
            // Same treatment as every other primary CTA (see
            // ProminentButtonStyle.swift).
            content.prominentButtonStyle()
        } else {
            content
        }
    }
}
