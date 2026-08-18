# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-08-18

### Added

- **Profiles**: create, rename (inline), duplicate, delete; drag & drop
  reordering (profile order = Dock order); per-profile SF Symbol and
  "hide recent apps" switch; JSON import/export; "Adopt Current Dock"
- **Three ways to add apps**: searchable picker of installed apps,
  Finder drag & drop into position, file dialog
- **Loading with a safety net**: automatic Dock backup before every load
  (up to 10 kept), one-click undo, confirmation with app count
- **Not installed? Not a problem**: missing apps are skipped - never an
  error - with a one-line note and a cleanup log explaining per app why
  it could not be resolved
- **Menu bar switching**: every profile one click away; optional menu bar
  icon; Dock presence follows the icon (menu-bar-only while no window is
  open); ⌘Q asks quit-vs-keep-running, rememberable and configurable
- **MDM support**: postinstall script export with a per-script auto-apply
  choice; read-only "Managed" section (duplicable into own profiles);
  LaunchAgent applies pending managed profiles at login, exactly once per
  user and again on every content change
- **Embedded CLI** (`Contents/Helpers/cleandock`): `list`,
  `apply --profile/--file/--managed`, `capture`; exit 0 on skips
- **Opt-in update check** (off by default) against the GitHub releases
  API; "Check for Updates…" reports the result directly
- **Occasional in-app support hint** after successful cleanups (never
  steals focus, permanent opt-out via checkbox) and an optional success
  notification for menu bar cleanups
- **Settings**: launch at login, menu bar icon, ⌘Q behavior, updates,
  backup management, managed-profiles location, support links, provider
  imprint and open-source notes
- Fixed Finder/Trash rows so a profile reads as the complete Dock;
  `persistent-others` (right Dock side) is never touched
- Localization: English (base) and German (100%)
- Code-generated app icon as an Icon Composer document with all macOS 26
  appearance variants (default/dark/clear/tinted) and a classic fallback
  for older systems
- PKG build with disabled bundle relocation; optional Developer ID
  signing and notarization scripts

[1.0.0]: https://github.com/hypeIT-GmbH/CleanDock/releases/tag/v1.0.0
