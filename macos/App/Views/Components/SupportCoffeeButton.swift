//
//  SupportCoffeeButton.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import AppKit
import SwiftUI

/// The prominent Buy-me-a-coffee button shared by the About window and the
/// Support settings tab.
struct SupportCoffeeButton: View {
    var body: some View {
        Button {
            NSWorkspace.shared.open(SupportLinks.buyMeACoffee)
        } label: {
            Label("Buy me a coffee", systemImage: "cup.and.saucer.fill")
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
        }
        .controlSize(.large)
        .prominentButtonStyle()
    }
}
