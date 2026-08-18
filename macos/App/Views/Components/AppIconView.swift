//
//  AppIconView.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The real app icon via NSWorkspace; grayed out when the app is missing.
struct AppIconView: View {
    let path: String?
    let isInstalled: Bool

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .grayscale(isInstalled ? 0 : 1)
            .opacity(isInstalled ? 1 : 0.5)
    }

    private var icon: NSImage {
        if let path, FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}
