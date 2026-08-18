//
//  ProfileSymbolBadge.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import SwiftUI

/// The 44×44 accent-tinted symbol badge shown in profile headers.
/// The editable and the managed profile header must look identical.
struct ProfileSymbolBadge: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 24, weight: .medium))
            .foregroundStyle(Color.accentColor)
            .frame(width: 44, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            )
    }
}
