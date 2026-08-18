//
//  JSONCoding.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import Foundation

// Shared coder configuration for the profile wire format. Every site that
// reads or writes profile JSON (app, CLI, MDM path) must use these factories
// so dates stay ISO 8601 and output stays deterministic across tools.

/// Version of the profiles.json wrapper format, shared by the store (write
/// and forward-version guard) and the import path. Lives outside the
/// MainActor-isolated ProfileStore so nonisolated code can check it.
public enum ProfileFileFormat {
    public static let version = 1
}

extension JSONEncoder {
    /// An encoder configured for the CleanDock profile wire format.
    public static func cleanDock() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

/// ISO 8601 parsers/formatters. `ISO8601DateFormatter` is documented
/// thread-safe, hence the unchecked nonisolated access. The fractional
/// variant is shared with the backup timestamps ($date values, filenames).
private nonisolated(unsafe) let isoPlain = ISO8601DateFormatter()
nonisolated(unsafe) let iso8601Fractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

extension JSONDecoder {
    /// A decoder configured for the CleanDock profile wire format.
    public static func cleanDock() -> JSONDecoder {
        let decoder = JSONDecoder()
        // Lenient in what we accept: our own encoder writes plain ISO 8601,
        // but third-party exporters (MDM tooling, Python scripts) commonly
        // emit fractional seconds - both forms must import.
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = isoPlain.date(from: string) ?? iso8601Fractional.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO 8601 date: \(string)"
                )
            }
            return date
        }
        return decoder
    }
}
