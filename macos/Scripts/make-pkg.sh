#!/bin/bash
# Builds the distributable PKG:
#   build/pkgroot/Applications/CleanDock.app
#   build/pkgroot/Library/LaunchAgents/de.hypeit.cleandock.apply.plist
#   → build/CleanDock-<version>.pkg
#
# Environment:
#   VERSION             package version (default: MARKETING_VERSION from project.yml)
#   DEVELOPER_ID_APP    optional "Developer ID Application: …" identity; when set,
#                       the app is signed inside-out before it enters the payload
#   INSTALLER_IDENTITY  optional "Developer ID Installer: …" identity for productsign
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([0-9][0-9.]*\)"\{0,1\}.*/\1/p' project.yml | head -1)}"
[[ -n "$VERSION" ]] || { echo "error: could not determine MARKETING_VERSION from project.yml" >&2; exit 1; }

# The version is maintained in two constants; a locally built release PKG
# never passes the tag workflow's check, so enforce consistency here too.
CODE_VERSION="$(sed -n 's/.*public static let version = "\([0-9.]*\)".*/\1/p' Core/Sources/CleanDockCore/CleanDockInfo.swift | head -1)"
if [[ "$CODE_VERSION" != "$VERSION" ]]; then
  echo "error: CleanDockInfo.version ($CODE_VERSION) != MARKETING_VERSION ($VERSION)" >&2
  exit 1
fi
MIN_OS="$(sed -n 's/^ *macOS: *"\([0-9.]*\)".*/\1/p' project.yml | head -1)"
[[ -n "$MIN_OS" ]] || { echo "error: could not determine the macOS deployment target from project.yml" >&2; exit 1; }
HEAD_TAG="$(git tag --points-at HEAD 2>/dev/null | grep '^v' | head -1 || true)"
if [[ -n "$HEAD_TAG" && "$HEAD_TAG" != "v$VERSION" ]]; then
  echo "error: HEAD is tagged $HEAD_TAG but the version is $VERSION" >&2
  exit 1
fi

echo "Building CleanDock $VERSION …"
# Stale artifacts from earlier runs (any version, signed or not) must never
# survive into this run - notarize.sh picks from build/ and a leftover
# signed PKG would win against the fresh build.
rm -f build/CleanDock-*.pkg
# Release builds must not reuse derived data: stale outputs written by an
# earlier provenance-tracked session (e.g. an agent build) would re-enter
# the payload and trip the AppleDouble gate below.
if [[ -n "${DEVELOPER_ID_APP:-}" ]]; then
  rm -rf build/dd
fi
# Single source of truth for the release build invocation.
Scripts/build.sh

APP="build/dd/Build/Products/Release/CleanDock.app"
PKGROOT="build/pkgroot"

# Release signing must happen HERE, before the app is copied into the payload -
# signing after pkgbuild would leave the copy inside the PKG ad-hoc signed and
# notarization would reject it.
if [[ -n "${DEVELOPER_ID_APP:-}" ]]; then
  echo "Signing inside-out with: $DEVELOPER_ID_APP"
  # 1. The embedded CLI binary first …
  codesign --force --options runtime --timestamp \
    --sign "$DEVELOPER_ID_APP" "$APP/Contents/Helpers/cleandock"
  # 2. … then the app bundle.
  codesign --force --options runtime --timestamp \
    --sign "$DEVELOPER_ID_APP" "$APP"
  codesign --verify --deep --strict "$APP"
  echo "Signature OK."
else
  echo "DEVELOPER_ID_APP not set - app stays ad-hoc signed (fine for local testing)."
fi

rm -rf "$PKGROOT"
mkdir -p "$PKGROOT/Applications" "$PKGROOT/Library/LaunchAgents"
# Note on com.apple.provenance: current macOS stamps this SIP-protected xattr
# onto everything the (provenance-tracked) Xcode build writes, and the xattr
# also inherits onto files created below an already-stamped directory such as
# build/. It cannot be deleted or ditto'd away, so no build environment can
# produce a stamp-free pkgroot - the AppleDouble entries pkgbuild derives
# from it are stripped from the finished archives by the sanitizer below.
ditto --noextattr --norsrc "$APP" "$PKGROOT/Applications/CleanDock.app"
# Content-only copy: the repo file itself carries com.apple.provenance
# (written by an agent session; the xattr is system-protected and survives
# ditto). A shell redirect writes a brand-new file that inherits nothing.
cat "LaunchAgent/de.hypeit.cleandock.apply.plist" \
  > "$PKGROOT/Library/LaunchAgents/de.hypeit.cleandock.apply.plist"
chmod 644 "$PKGROOT/Library/LaunchAgents/de.hypeit.cleandock.apply.plist"
find "$PKGROOT" -name ".DS_Store" -delete

# Disable bundle relocation. Without this, Installer "updates" any existing
# copy of the app it finds via Spotlight (e.g. a local build directory)
# instead of installing to /Applications.
COMPONENT_PLIST="build/component.plist"
pkgbuild --analyze --root "$PKGROOT" "$COMPONENT_PLIST"
plutil -replace 0.BundleIsRelocatable -bool NO "$COMPONENT_PLIST"

# Component package in a subdirectory, so it can never be confused with
# the distribution PKGs notarize.sh selects by exact, version-pinned name
# (signed preferred, container signature verified before submitting).
COMPONENT_DIR="build/component"
rm -rf "$COMPONENT_DIR"
mkdir -p "$COMPONENT_DIR"

COMPONENT_PKG="$COMPONENT_DIR/CleanDock.pkg"
pkgbuild --root "$PKGROOT" \
  --component-plist "$COMPONENT_PLIST" \
  --scripts pkg/scripts \
  --identifier de.hypeit.cleandock \
  --version "$VERSION" \
  --install-location / \
  "$COMPONENT_PKG"

# Sanitize the component package: pkgbuild embeds one AppleDouble (._*)
# entry per payload object for the com.apple.provenance xattr (see above),
# which would ship this machine's provenance metadata to every target Mac.
# The xattr cannot be removed from the input files, so the finished archives
# are rebuilt without those entries instead:
#   Scripts  - materialized by pkgutil --expand, ._* deleted as plain files.
#   Payload  - the gzipped odc cpio is filtered byte-exact (dropping only
#              ._* entries), preserving pkgbuild's root:wheel ownership.
#   Bom      - regenerated from the original Bom's listing minus ._* lines,
#              keeping modes, owners and checksums identical.
SANITIZE_DIR="build/component-sanitize"
rm -rf "$SANITIZE_DIR"
pkgutil --expand "$COMPONENT_PKG" "$SANITIZE_DIR"
find "$SANITIZE_DIR" \( -name "._*" -o -name ".DS_Store" \) -delete

gzcat "$SANITIZE_DIR/Payload" | /usr/bin/python3 -c '
import sys
r, w = sys.stdin.buffer, sys.stdout.buffer
while True:
    h = r.read(76)
    if len(h) < 76:
        w.write(h); break
    if h[:6] != b"070707":
        sys.stderr.write("error: unexpected cpio magic in Payload\n"); sys.exit(1)
    namesize, filesize = int(h[59:65], 8), int(h[65:76], 8)
    name, data = r.read(namesize), r.read(filesize)
    base = name.rstrip(b"\x00").rsplit(b"/", 1)[-1]
    if base == b"TRAILER!!!":
        w.write(h + name + data); w.write(r.read()); break
    if not base.startswith(b"._"):
        w.write(h + name + data)
' | gzip -c > "$SANITIZE_DIR/Payload.clean"
mv "$SANITIZE_DIR/Payload.clean" "$SANITIZE_DIR/Payload"

lsbom "$SANITIZE_DIR/Bom" | awk -F'\t' '$1 !~ /(^|\/)\._/' > "$SANITIZE_DIR/bom.list"
mkbom -i "$SANITIZE_DIR/bom.list" "$SANITIZE_DIR/Bom.clean"
mv "$SANITIZE_DIR/Bom.clean" "$SANITIZE_DIR/Bom"

# PackageInfo carries the payload object count; keep it in sync and assert
# that Payload and Bom agree before flattening.
NFILES="$(gzcat "$SANITIZE_DIR/Payload" | cpio -it 2>/dev/null | wc -l | tr -d ' ')"
BOMLINES="$(wc -l < "$SANITIZE_DIR/bom.list" | tr -d ' ')"
rm -f "$SANITIZE_DIR/bom.list"
if [[ "$NFILES" -lt 2 || "$NFILES" != "$BOMLINES" ]]; then
  echo "error: payload/Bom sanitization mismatch (payload=$NFILES bom=$BOMLINES)" >&2
  exit 1
fi
sed -i '' -e "s/numberOfFiles=\"[0-9]*\"/numberOfFiles=\"$NFILES\"/" "$SANITIZE_DIR/PackageInfo"

# Hard gate: the payload must be free of AppleDouble entries after the
# sanitizer - if this fires, the sanitizer is broken and the build must not
# ship. ALLOW_DIRTY_PAYLOAD=1 skips the gate for local structure testing ONLY.
# grep -c consumes the whole stream (no early exit), so gzcat/cpio cannot
# be SIGPIPEd into a spurious pipefail failure the way grep -q allows.
APPLEDOUBLE_COUNT="$(gzcat "$SANITIZE_DIR/Payload" | cpio -it 2>/dev/null | grep -c '/\._' || true)"
if [[ "$APPLEDOUBLE_COUNT" -gt 0 ]]; then
  if [[ "${ALLOW_DIRTY_PAYLOAD:-0}" == "1" ]]; then
    echo "WARNING: payload contains AppleDouble entries - test build only, DO NOT SHIP." >&2
  else
    echo "error: the payload still contains AppleDouble (._*) entries after" >&2
    echo "sanitization - the sanitizer in make-pkg.sh is broken; do not ship." >&2
    rm -rf "$SANITIZE_DIR"
    exit 1
  fi
fi

rm -f "$COMPONENT_PKG"
pkgutil --flatten "$SANITIZE_DIR" "$COMPONENT_PKG"
rm -rf "$SANITIZE_DIR"

# Distribution wrapper: enforces the minimum macOS at INSTALL time - a bare
# component pkg would install on macOS < 15, where the app then refuses to
# launch and the user is left with a broken install.
DIST="build/distribution.xml"
productbuild --synthesize --package "$COMPONENT_PKG" "$DIST"
sed -i '' -e 's|<installer-gui-script[^>]*>|&<title>CleanDock</title><allowed-os-versions><os-version min="'"$MIN_OS"'"/></allowed-os-versions>|' "$DIST"
# A silently missed sed match would ship a PKG without the OS gate - assert it.
grep -q "<os-version min=\"$MIN_OS\"/>" "$DIST" || {
  echo "error: the minimum-OS gate is missing from $DIST - productbuild output format changed?" >&2
  exit 1
}

PKG_UNSIGNED="build/CleanDock-$VERSION.pkg"
productbuild --distribution "$DIST" --package-path "$COMPONENT_DIR" "$PKG_UNSIGNED"

if [[ -n "${INSTALLER_IDENTITY:-}" ]]; then
  PKG_SIGNED="build/CleanDock-$VERSION-signed.pkg"
  echo "Signing package with: $INSTALLER_IDENTITY"
  productsign --sign "$INSTALLER_IDENTITY" "$PKG_UNSIGNED" "$PKG_SIGNED"
  echo "Signed package: $PKG_SIGNED"
else
  echo "INSTALLER_IDENTITY not set - leaving the package unsigned (fine for local testing)."
fi

echo "Package: $PKG_UNSIGNED"
