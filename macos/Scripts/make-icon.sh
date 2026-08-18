#!/bin/bash
# Regenerates the glyph layers of the Icon Composer document
# (App/Resources/AppIcon.icon). Xcode compiles that document into the
# macOS 26 appearance variants (default/dark/clear/tinted) plus the classic
# fallback icon for older systems.
set -euo pipefail
cd "$(dirname "$0")/.."
swift Scripts/generate-icon.swift "App/Resources/AppIcon.icon/Assets"
