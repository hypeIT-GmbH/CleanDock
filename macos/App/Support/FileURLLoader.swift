//
//  FileURLLoader.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import Foundation
import UniformTypeIdentifiers

/// Loads file URLs from drag & drop item providers.
@MainActor
enum FileURLLoader {
    /// Loads file URLs from item providers, preserving order.
    static func urls(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            if let url = await url(from: provider) {
                urls.append(url)
            }
        }
        return urls
    }

    private static func url(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                if let data = item as? Data {
                    continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
