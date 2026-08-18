//
//  InfoBadge.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import SwiftUI

/// Info icon that explains a setting: click opens the text instantly as a
/// popover; hovering still shows it as a tooltip (with the app-wide reduced
/// delay set in AppDelegate).
struct InfoBadge: View {
    let text: LocalizedStringKey

    @State private var showingPopover = false

    var body: some View {
        Button {
            showingPopover = true
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(text)
        // Without a label VoiceOver announces only the SF Symbol's generic
        // name; the popover text itself is the best description available.
        .accessibilityLabel(Text(text))
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            Text(text)
                .font(.callout)
                .multilineTextAlignment(.leading)
                .frame(width: 300, alignment: .leading)
                .padding(12)
        }
    }
}
