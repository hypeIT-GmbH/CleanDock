#!/bin/bash
# Optional: notarize and staple a PKG built by Scripts/make-pkg.sh.
# Signing happens in make-pkg.sh (set DEVELOPER_ID_APP there) BEFORE the app
# enters the package payload; this script only verifies that the PKG and its
# contents are Developer-ID signed, then submits and staples. Skips cleanly when no
# notary profile is configured - unsigned local builds must always keep working.
#
# Environment:
#   NOTARY_PROFILE  notarytool keychain profile (required to notarize),
#                   created once via:
#                   xcrun notarytool store-credentials <profile> \
#                     --apple-id … --team-id … --password <app-specific>
#   PKG             package to notarize (default: this version's PKG from build/,
#                   the productsigned one preferred)
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${NOTARY_PROFILE:-}" ]]; then
  echo "NOTARY_PROFILE not set - skipping notarization."
  echo "Unsigned local builds keep working. For a release, run Scripts/make-pkg.sh"
  echo "with DEVELOPER_ID_APP set, then this script with NOTARY_PROFILE set."
  exit 0
fi

# Only the CURRENT project version is a valid candidate - a stale signed
# PKG from an earlier run must never win against a fresh build. Within the
# version, prefer the productsigned package.
VERSION="$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([0-9][0-9.]*\)"\{0,1\}.*/\1/p' project.yml | head -1)"
[[ -n "$VERSION" ]] || { echo "error: could not determine MARKETING_VERSION from project.yml" >&2; exit 1; }
if [[ -z "${PKG:-}" ]]; then
  for candidate in "build/CleanDock-$VERSION-signed.pkg" "build/CleanDock-$VERSION.pkg"; do
    [[ -f "$candidate" ]] && { PKG="$candidate"; break; }
  done
fi
if [[ -z "${PKG:-}" ]]; then
  echo "error: no CleanDock-$VERSION PKG found in build/. Run Scripts/make-pkg.sh first." >&2
  exit 1
fi

# Notarization requires Developer-ID-signed contents - verify the app inside
# the actual PKG before submitting.
EXPANDED="build/notarize-check"
rm -rf "$EXPANDED"
pkgutil --expand-full "$PKG" "$EXPANDED"
# Distribution PKGs nest the payload one level deeper than component PKGs -
# locate the app instead of hardcoding either layout.
APP_IN_PKG="$(find "$EXPANDED" -maxdepth 4 -type d -name "CleanDock.app" | head -1)"
if [[ -z "$APP_IN_PKG" ]]; then
  echo "error: CleanDock.app not found inside $PKG." >&2
  rm -rf "$EXPANDED"
  exit 1
fi
# codesign prints unbuffered on stderr; piping it straight into grep -q
# under pipefail can SIGPIPE codesign once grep has matched, turning a
# valid signature into a false negative. Capture first, then grep.
SIGN_INFO="$(codesign --display --verbose=2 "$APP_IN_PKG" 2>&1 || true)"
if ! grep -q "Authority=Developer ID Application" <<<"$SIGN_INFO"; then
  echo "error: the app inside $PKG is not Developer-ID signed." >&2
  echo "Re-run Scripts/make-pkg.sh with DEVELOPER_ID_APP set, then retry." >&2
  rm -rf "$EXPANDED"
  exit 1
fi
codesign --verify --deep --strict "$APP_IN_PKG"
rm -rf "$EXPANDED"
echo "PKG contents are Developer-ID signed."

# The PKG container itself must be productsigned (Developer ID Installer) -
# an unsigned container passes every local check but is rejected by notarytool.
CONTAINER_INFO="$(pkgutil --check-signature "$PKG" || true)"
grep -q "Developer ID Installer" <<<"$CONTAINER_INFO" || {
  echo "error: $PKG is not productsigned - pass the -signed.pkg or set INSTALLER_IDENTITY in make-pkg.sh." >&2
  exit 1
}
echo "PKG container is productsigned."

echo "Submitting $PKG for notarization …"
SUBMIT_FAILED=0
SUBMIT_OUTPUT="$(xcrun notarytool submit "$PKG" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)" || SUBMIT_FAILED=1
echo "$SUBMIT_OUTPUT"
if [[ "$SUBMIT_FAILED" == 1 ]] || ! grep -q "status: Accepted" <<<"$SUBMIT_OUTPUT"; then
  # Pull the rejection reasons right away - they live only in the log.
  SUBMISSION_ID="$(echo "$SUBMIT_OUTPUT" | sed -n 's/^ *id: \([0-9a-f-]*\)$/\1/p' | head -1)"
  if [[ -n "$SUBMISSION_ID" ]]; then
    echo "Notarization not accepted - fetching the log for $SUBMISSION_ID:" >&2
    xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
  fi
  exit 1
fi
xcrun stapler staple "$PKG"
echo "Notarized and stapled: $PKG"
