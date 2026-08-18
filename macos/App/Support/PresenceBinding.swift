//
//  PresenceBinding.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import SwiftUI

extension Binding where Value == Bool {
    /// Presence of an optional as a Bool: `true` while the optional holds a
    /// value; setting `false` clears it (setting `true` is a no-op).
    init<Wrapped>(presence source: Binding<Wrapped?>) {
        self.init(
            get: { source.wrappedValue != nil },
            set: { if !$0 { source.wrappedValue = nil } }
        )
    }
}
