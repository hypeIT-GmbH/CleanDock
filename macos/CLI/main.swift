//
//  main.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import CleanDockCore
import Foundation
import os

/// Unified-log channel for headless runs (LaunchAgent): stdout is discarded
/// there, so the result of a login-time apply must be diagnosable via
/// `log show`.
let cliLogger = Logger(subsystem: CleanDockInfo.appBundleID, category: "cli")

// cleandock - command line interface embedded in
// "CleanDock.app/Contents/Helpers/cleandock".
//
// Exit codes: 0 on success - including when apps were skipped because they
// are not installed. 64 for usage errors. Non-zero otherwise only for real
// errors (profile not found, invalid JSON, no user context).

let helpText = """
cleandock \(CleanDockInfo.version) - set the macOS Dock from profiles

USAGE:
  cleandock list [--json]
  cleandock apply --profile "<name>"
  cleandock apply --file <path.json>
  cleandock apply --managed
  cleandock capture --name "<name>"
  cleandock --version
  cleandock --help

COMMANDS:
  list       List user profiles and managed profiles. --json for JSON output.
  apply      Apply a profile to the Dock.
               --profile <name>  Apply the named profile (user profiles are
                                 searched first, then managed profiles).
               --file <path>     Apply a profile JSON file directly. A file
                                 with several profiles (a profiles.json
                                 export) applies all of them in order.
               --managed         Apply all managed profiles that have not been
                                 applied for this user yet (content-hash based,
                                 each managed profile applies exactly once per
                                 user and again whenever its content changes).
  capture    Save the current Dock as a new profile.
               --name <name>     Name for the new profile.

NOTES:
  Apps that are not installed are skipped and reported in the output; this is
  not an error and the exit code stays 0. This tool must run in a user
  context - the Dock is configured per user. Running it as root is an error.
"""

func fail(_ message: String, code: Int32 = 1) -> Never {
    // Also into the unified log: under the LaunchAgent stderr is discarded,
    // and failures must be as diagnosable as the success summary.
    cliLogger.error("\(message, privacy: .public)")
    FileHandle.standardError.write(Data("cleandock: error: \(message)\n".utf8))
    exit(code)
}

func requireUserContext() {
    if getuid() == 0 {
        fail(CleanDockError.mustRunAsUser.localizedDescription)
    }
}

/// Parses a command's arguments into options. Unknown arguments, stray
/// positionals and options without their value are usage errors (exit 64).
/// Flags map to an empty string so presence checks read as `!= nil`.
func parseOptions(
    _ arguments: [String],
    command: String,
    flags: Set<String> = [],
    valued: Set<String> = []
) -> [String: String] {
    var options: [String: String] = [:]
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        if flags.contains(argument) {
            options[argument] = ""
        } else if valued.contains(argument) {
            guard index + 1 < arguments.count else {
                fail("\(argument) requires a value (see --help)", code: 64)
            }
            index += 1
            options[argument] = arguments[index]
        } else {
            fail("unknown argument \"\(argument)\" for \(command) (see --help)", code: 64)
        }
        index += 1
    }
    return options
}

struct ProfileListItem: Encodable {
    let name: String
    let symbol: String
    let appCount: Int
    let hideRecents: Bool
    let managed: Bool
    let autoApply: Bool?
    let source: String?
}

func printApplyResult(_ result: ApplyResult, profileName: String) {
    print("Applied profile \"\(profileName)\": \(result.applied.count) app(s) in the Dock.")
    if !result.skipped.isEmpty {
        let names = result.skipped.map(\.name).joined(separator: ", ")
        print("Skipped (not installed): \(names)")
    }
}

/// Applies the profile and prints the result; any error is fatal.
/// `afterApply` runs between the apply and the report (e.g. marker writes).
func applyOrExit(
    _ profile: Profile,
    using dockService: DockService,
    backingUp: Bool = true,
    afterApply: () throws -> Void = {}
) {
    do {
        let result = try dockService.apply(profile, backingUp: backingUp)
        try afterApply()
        printApplyResult(result, profileName: profile.name)
    } catch {
        fail(error.localizedDescription)
    }
}

@MainActor
func runList(arguments: [String]) {
    let options = parseOptions(arguments, command: "list", flags: ["--json"])
    let store = ProfileStore()
    let managed = ManagedProfileService().list()

    if options["--json"] != nil {
        let items = store.profiles.map {
            ProfileListItem(
                name: $0.name, symbol: $0.symbol, appCount: $0.apps.count,
                hideRecents: $0.hideRecents, managed: false, autoApply: nil, source: nil
            )
        } + managed.map {
            ProfileListItem(
                name: $0.profile.name, symbol: $0.profile.symbol, appCount: $0.profile.apps.count,
                hideRecents: $0.profile.hideRecents, managed: true, autoApply: $0.autoApply,
                source: $0.fileURL.path
            )
        }
        let encoder = JSONEncoder.cleanDock()
        guard let data = try? encoder.encode(items), let text = String(data: data, encoding: .utf8) else {
            fail("could not encode profile list as JSON")
        }
        print(text)
        return
    }

    if store.profiles.isEmpty && managed.isEmpty {
        print("No profiles.")
        return
    }
    if !store.profiles.isEmpty {
        print("User profiles:")
        for profile in store.profiles {
            print("  \(profile.name) (\(profile.apps.count) apps)")
        }
    }
    if !managed.isEmpty {
        print("Managed profiles:")
        for item in managed {
            let suffix = item.autoApply ? "" : ", manual"
            print("  \(item.profile.name) (\(item.profile.apps.count) apps\(suffix)) - \(item.fileURL.path)")
        }
    }
}

@MainActor
func runApply(arguments: [String]) {
    requireUserContext()
    let options = parseOptions(
        arguments, command: "apply",
        flags: ["--managed"], valued: ["--file", "--profile"]
    )
    let modes = ["--profile", "--file", "--managed"].filter { options[$0] != nil }
    if modes.count > 1 {
        fail("\(modes.joined(separator: " and ")) cannot be combined (see --help)", code: 64)
    }
    let dockService = DockService()

    if options["--managed"] != nil {
        let managedService = ManagedProfileService()
        let pending = managedService.pending()
        if pending.isEmpty {
            print("No pending managed profiles.")
            // .notice, not .info: `log show` without --info must cover all
            // three outcomes (applied / nothing pending / failure).
            cliLogger.notice("apply --managed: no pending managed profiles")
            return
        }
        // One backup per run: per-apply backups would rotate the run's real
        // starting state out of the 10-slot backup list.
        for (index, item) in pending.enumerated() {
            applyOrExit(item.profile, using: dockService, backingUp: index == 0) {
                try managedService.markApplied(item)
            }
        }
        // The LaunchAgent discards stdout - the unified log is the channel
        // admins can actually reach (log show --predicate 'subsystem == …').
        cliLogger.notice("apply --managed: applied \(pending.count, privacy: .public) pending profile(s)")
        return
    }

    if let path = options["--file"] {
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            fail("could not read \(path): \(error.localizedDescription)")
        }
        let profiles: [Profile]
        do {
            profiles = try ExportService.decodeProfiles(from: data)
        } catch {
            fail(error.localizedDescription)
        }
        if profiles.isEmpty {
            fail("no profile found in \(path)")
        }
        // A profiles.json wrapper applies all contained profiles in order,
        // mirroring apply --managed - with a single backup for the run.
        for (index, profile) in profiles.enumerated() {
            applyOrExit(profile, using: dockService, backingUp: index == 0)
        }
        return
    }

    if let name = options["--profile"] {
        let store = ProfileStore()
        // User profiles first, then managed profiles.
        let profile = store.profile(named: name)
            ?? ManagedProfileService().list()
                .first { $0.profile.name.localizedCaseInsensitiveCompare(name) == .orderedSame }?
                .profile
        guard let profile else {
            fail(CleanDockError.profileNotFound(name).localizedDescription)
        }
        applyOrExit(profile, using: dockService)
        return
    }

    fail("apply requires --profile <name>, --file <path> or --managed (see --help)", code: 64)
}

@MainActor
func runCapture(arguments: [String]) {
    requireUserContext()
    let options = parseOptions(arguments, command: "capture", valued: ["--name"])
    guard let rawName = options["--name"] else {
        fail("capture requires --name \"<name>\" (see --help)", code: 64)
    }
    let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    if name.isEmpty {
        fail("capture requires a non-empty --name (see --help)", code: 64)
    }
    let store = ProfileStore()
    let captured = DockService().captureDock()
    let profile = store.add(Profile(
        name: name,
        apps: captured.apps,
        hideRecents: captured.hideRecents
    ))
    if let error = store.lastSaveError {
        fail("could not save profile: \(error.localizedDescription)")
    }
    print("Captured the current Dock as profile \"\(profile.name)\" (\(captured.apps.count) apps).")
}

let arguments = Array(CommandLine.arguments.dropFirst())

CleanDockPaths.migrateLegacySupportDirectoryIfNeeded()

guard let command = arguments.first else {
    // Usage error: stdout and exit 0 stay reserved for explicit --help.
    fail("a command is required (see --help)", code: 64)
}

switch command {
case "--version", "-v", "version":
    print(CleanDockInfo.version)
case "--help", "-h", "help":
    print(helpText)
case "list":
    runList(arguments: Array(arguments.dropFirst()))
case "apply":
    runApply(arguments: Array(arguments.dropFirst()))
case "capture":
    runCapture(arguments: Array(arguments.dropFirst()))
default:
    fail("unknown command \"\(command)\" (see --help)", code: 64)
}
