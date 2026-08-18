//
//  ProminentButtonStyle.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import SwiftUI

/// Availability-gated prominent button styling: Liquid Glass on macOS 26,
/// the classic prominent style on earlier systems.
private struct ProminentButtonStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

extension View {
    /// Applies `.glassProminent` where available, `.borderedProminent` otherwise.
    func prominentButtonStyle() -> some View {
        modifier(ProminentButtonStyleModifier())
    }
}
