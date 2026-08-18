# Contributing to CleanDock

Thanks for your interest - contributions are welcome!

## Setup

- macOS with **Xcode 26**
- `brew install xcodegen`

```bash
cd macos
xcodegen
open "CleanDock.xcodeproj"
```

Run the unit tests with `cd macos/Core && swift test`.

## Workflow

1. Fork the repository and create a feature branch.
2. Make your changes.
3. Open a pull request against `main`. PRs without a green CI build are not
   merged.

## Guidelines

- **Language:** code, comments and commit messages are English. App UI strings
  live in the string catalog (English base, German must stay at 100%).
- **Style:** follow the
  [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
- **Dependencies:** none. The project is deliberately dependency-free
  (Apple frameworks only). New dependencies require maintainer approval
  beforehand - the default answer is no.
- **Tests:** changes to `CleanDockCore` require unit tests.
- **Commits:** [Conventional Commits](https://www.conventionalcommits.org/)
  are recommended (`feat:`, `fix:`, `docs:`, …).

## Non-negotiables (from the product spec)

- Never write `com.apple.dock.plist` directly - always CFPreferences.
- App Sandbox stays off; hardened runtime stays on.
- Skipped (not installed) apps are never an error: CLI exit 0, GUI shows a
  subtle hint at most.
- `persistent-others` (right Dock side) is never touched.
- Network access is limited to the opt-in update check (`UpdateChecker`,
  GitHub releases API only). Everything else stays offline; the only other
  online actions are user-initiated browser links.

## Questions?

Use [GitHub Discussions](https://github.com/hypeIT-GmbH/CleanDock/discussions)
for questions and ideas; Issues are for bugs and feature requests.
