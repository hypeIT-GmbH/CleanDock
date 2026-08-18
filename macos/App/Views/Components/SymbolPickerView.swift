//
//  SymbolPickerView.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import CleanDockCore
import SwiftUI

/// Curated grid of SF Symbols that fit Dock profiles.
struct SymbolPickerView: View {
    let selectedSymbol: String
    let onSelect: (String) -> Void

    /// Leads with the symbol every new profile is created with, so the grid
    /// always contains the current selection of a fresh profile.
    private static let symbols: [String] = [
        Profile.defaultSymbol, "briefcase.fill", "house.fill", "desktopcomputer",
        "laptopcomputer", "gearshape.fill", "hammer.fill", "wrench.and.screwdriver.fill",
        "paintbrush.fill", "pencil.and.ruler.fill", "graduationcap.fill", "book.fill",
        "gamecontroller.fill", "music.note", "camera.fill", "film.fill",
        "globe", "network", "shield.fill", "star.fill"
    ]

    private let columns = Array(repeating: GridItem(.fixed(40), spacing: 8), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Self.symbols, id: \.self) { symbol in
                let isSelected = symbol == selectedSymbol
                Button {
                    onSelect(symbol)
                } label: {
                    Image(systemName: symbol)
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 17))
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected
                                      ? AnyShapeStyle(Color.accentColor.opacity(0.2))
                                      : AnyShapeStyle(.clear))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(
                                    isSelected ? Color.accentColor : .clear,
                                    lineWidth: 1.5
                                )
                        )
                        // Second, non-color selection marker: the accent
                        // fill and border alone are hard to spot with
                        // impaired color vision.
                        .overlay(alignment: .topTrailing) {
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white, Color.accentColor)
                                    .background(Circle().fill(.background))
                                    .offset(x: 4, y: -4)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // The selection state is otherwise visual only - VoiceOver
                // needs it as a trait to announce the current choice.
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(12)
    }
}
