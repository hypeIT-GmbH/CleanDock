# Security Policy

CleanDock writes the user's Dock preferences (`com.apple.dock`) and is
deployed to company Macs via MDM. We take security reports seriously.

## Reporting a Vulnerability

Please report vulnerabilities **confidentially** via
[GitHub Security Advisories](https://github.com/hypeIT-GmbH/CleanDock/security/advisories/new).
Do **not** open public issues for security problems.

- We aim to respond within **14 days**.
- Fixes are released **before** public disclosure.

## Scope

Particularly relevant areas:

- The generated MDM postinstall script and its handling of profile JSON
- The LaunchAgent and the CLI (`apply --managed`) running at login
- Parsing of managed profile files from `/Library/Application Support/CleanDock/managed/`

## Supported Versions

Only the latest release receives security fixes.
