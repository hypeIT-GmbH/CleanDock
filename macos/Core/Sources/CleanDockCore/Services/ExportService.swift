//
//  ExportService.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import CryptoKit
import Foundation

/// Generates the MDM postinstall script and plain JSON exports for a profile,
/// and decodes profile JSON for import.
public struct ExportService: Sendable {
    public init() {}

    // MARK: - Slug

    /// Profile name → lowercase slug limited to `a-z0-9-`.
    /// "Standard Büro" → "standard-buro".
    public static func slug(for name: String) -> String {
        var text = name
            .replacingOccurrences(of: "ß", with: "ss")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        text = text.map { character -> Character in
            if character.isASCII && (character.isLetter || character.isNumber) {
                return character
            }
            return "-"
        }.reduce(into: "") { partial, character in
            // Collapse runs of "-".
            if character == "-" && partial.hasSuffix("-") { return }
            partial.append(character)
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return text.isEmpty ? "profile" : text
    }

    // MARK: - JSON exports

    /// Plain profile JSON (the export "Profile (JSON)").
    public func profileJSON(for profile: Profile) throws -> Data {
        try JSONEncoder.cleanDock().encode(profile)
    }

    /// Profile JSON with the `autoApply` marker, as embedded in the MDM
    /// script. `autoApply: false` deploys the profile without the LaunchAgent
    /// or `apply --managed` ever applying it automatically.
    public func managedProfileJSON(for profile: Profile, autoApply: Bool = true) throws -> Data {
        struct ManagedExport: Encodable {
            let profile: Profile
            let autoApply: Bool

            enum ExtraKeys: String, CodingKey {
                case autoApply
            }

            func encode(to encoder: Encoder) throws {
                try profile.encode(to: encoder)
                var container = encoder.container(keyedBy: ExtraKeys.self)
                try container.encode(autoApply, forKey: .autoApply)
            }
        }
        return try JSONEncoder.cleanDock().encode(ManagedExport(profile: profile, autoApply: autoApply))
    }

    // MARK: - MDM postinstall script

    /// Generates the postinstall script that deploys the profile as a managed
    /// profile. With `autoApply` the script also cleans up the Dock right
    /// after installation (immediately for a logged-in user, otherwise via
    /// the LaunchAgent at the next login); without it the profile is only
    /// deployed and waits in CleanDock's "Managed" section.
    public func mdmScript(
        for profile: Profile,
        appVersion: String = CleanDockInfo.version,
        date: Date = Date(),
        autoApply: Bool = true
    ) throws -> String {
        let json = try managedProfileJSON(for: profile, autoApply: autoApply)
        guard let jsonString = String(data: json, encoding: .utf8) else {
            throw CleanDockError.invalidProfileJSON("could not encode profile as UTF-8")
        }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return Self.expand(Self.scriptTemplate, values: [
            "APPLY_SECTION": autoApply ? Self.autoApplySection : Self.deployOnlySection,
            "PROFILE_NAME": Self.singleLine(profile.name),
            "VERSION": Self.singleLine(appVersion),
            "DATE": dateFormatter.string(from: date),
            "SLUG": Self.managedFileSlug(for: profile.name),
            "LEGACY_SLUG": Self.slug(for: profile.name),
            "PROFILE_JSON": jsonString
        ])
    }

    /// The filename slug used inside the managed directory. The readable
    /// slug alone is not collision-free - different names can slugify to
    /// the same string (non-Latin names all become "profile", umlauts fold
    /// together), and two colliding files would silently overwrite each
    /// other on the target Macs. A short hash of the exact name makes the
    /// filename unique per profile name while staying deterministic across
    /// re-exports.
    static func managedFileSlug(for name: String) -> String {
        let suffix = SHA256.hash(data: Data(name.utf8)).hexString.prefix(6)
        return "\(slug(for: name))-\(suffix)"
    }

    /// Single-pass `{{TOKEN}}` template expansion. The template is walked
    /// exactly once and values are appended verbatim - substituted output is
    /// never re-scanned, so a value that itself contains a literal placeholder
    /// token (e.g. a profile named "x {{PROFILE_JSON}}") cannot trigger a
    /// second expansion and smuggle newlines past the `singleLine` guard into
    /// a script that runs as root. Unknown or unterminated tokens are kept
    /// verbatim.
    static func expand(_ template: String, values: [String: String]) -> String {
        var result = ""
        var rest = template[...]
        while let open = rest.range(of: "{{") {
            result += rest[..<open.lowerBound]
            guard let close = rest.range(of: "}}", range: open.upperBound..<rest.endIndex) else {
                rest = rest[open.lowerBound...]
                break
            }
            let token = String(rest[open.upperBound..<close.lowerBound])
            if let value = values[token] {
                result += value
            } else {
                result += rest[open.lowerBound..<close.upperBound]
            }
            rest = rest[close.upperBound...]
        }
        result += rest
        return result
    }

    /// Values substituted into `#`-comment lines of the script must never
    /// contain newlines or other control characters - a name with an embedded
    /// newline would otherwise break out of the comment and become an
    /// executable line in a script that runs as root.
    static func singleLine(_ value: String) -> String {
        String(value.map { character in
            if character.isNewline { return " " }
            if let scalar = character.unicodeScalars.first,
               character.unicodeScalars.count == 1,
               scalar.properties.generalCategory == .control {
                return " "
            }
            return character
        })
    }

    /// The script's comments are German on purpose - they address the Mac
    /// admins deploying it, matching the product specification.
    static let scriptTemplate = """
    #!/bin/bash
    # CleanDock - Managed Profile: {{PROFILE_NAME}}
    # Generiert von CleanDock {{VERSION}} am {{DATE}}
    # Als Postinstall-Skript nach dem CleanDock-PKG ausrollen (läuft als root).
    set -euo pipefail

    CONFIG_DIR="/Library/Application Support/CleanDock/managed"
    CONFIG_FILE="$CONFIG_DIR/{{SLUG}}.json"

    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<'DOCKPROFILE'
    {{PROFILE_JSON}}
    DOCKPROFILE
    chmod 0644 "$CONFIG_FILE"

    # Migrate away the pre-1.0 filename of THIS profile (same slug without
    # the content-hash suffix) - a leftover would coexist with the new file
    # and, sorting after it, win the login-time apply with stale content.
    # Legacy slugs are NOT unique per profile (that is why the hash suffix
    # exists), so only delete when the file's profile name matches ours;
    # plutil keeps the comparison free of shell-quoting pitfalls.
    LEGACY_FILE="$CONFIG_DIR/{{LEGACY_SLUG}}.json"
    if [ -f "$LEGACY_FILE" ]; then
      LEGACY_NAME="$(plutil -extract name raw -o - "$LEGACY_FILE" 2>/dev/null || true)"
      NEW_NAME="$(plutil -extract name raw -o - "$CONFIG_FILE" 2>/dev/null || true)"
      if [ -n "$NEW_NAME" ] && [ "$LEGACY_NAME" = "$NEW_NAME" ]; then
        rm -f "$LEGACY_FILE"
      fi
    fi

    {{APPLY_SECTION}}

    exit 0
    """

    static let autoApplySection = """
    # Sofort anwenden, falls gerade ein Benutzer angemeldet ist.
    # Sonst übernimmt der LaunchAgent die Anwendung beim nächsten Login.
    APP_CLI="/Applications/CleanDock.app/Contents/Helpers/cleandock"
    consoleUser=$(stat -f%Su /dev/console 2>/dev/null || true)
    if [[ -x "$APP_CLI" && -n "$consoleUser" && "$consoleUser" != "root" && "$consoleUser" != "loginwindow" ]]; then
      uid=$(id -u "$consoleUser")
      launchctl asuser "$uid" sudo -u "$consoleUser" "$APP_CLI" apply --managed || true
    fi
    """

    static let deployOnlySection = """
    # Dieses Profil wird nicht automatisch angewendet (autoApply: false).
    # Es erscheint in CleanDock unter „Verwaltet“ und kann dort jederzeit
    # manuell angewendet werden.
    """

    // MARK: - Import

    /// Decodes profile JSON for import. Accepts a single profile object
    /// (with or without `autoApply`) as well as a full `profiles.json`
    /// wrapper, in which case all contained profiles are returned.
    public static func decodeProfiles(from data: Data) throws -> [Profile] {
        let decoder = JSONDecoder.cleanDock()
        struct Wrapper: Decodable {
            var profiles: [Profile]
        }
        // Decode by the shape the input actually has, so errors are reported
        // for that shape: only input with a top-level "profiles" key is
        // wrapper-shaped - everything else must surface the single-profile
        // decode error, not a misleading missing-"profiles" message.
        let topLevel = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        // A wrapper written by a newer format must not be silently read as
        // v1 - mirror the forward-version guard the ProfileStore applies.
        if let version = topLevel?["version"] as? Int, version > ProfileFileFormat.version {
            throw CleanDockError.invalidProfileJSON(
                "written by a newer format (version \(version)) - please update CleanDock"
            )
        }
        do {
            if topLevel?["profiles"] != nil {
                return try decoder.decode(Wrapper.self, from: data).profiles
            }
            return [try decoder.decode(Profile.self, from: data)]
        } catch {
            throw CleanDockError.invalidProfileJSON(error.localizedDescription)
        }
    }
}
