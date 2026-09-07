#!/usr/bin/env bash
#
# Ainkrad release builder.
#
# Builds a Release Ainkrad.app, packages it as a .dmg, and — when Developer ID
# signing credentials are present — code-signs (hardened runtime), notarizes,
# and staples it so it opens without the Gatekeeper warning. Degrades
# gracefully: with no cert it still produces an installable (unsigned) .dmg.
#
# The same script runs locally and in CI (.github/workflows/release.yml just
# sets the env vars below from repo secrets and calls this with --publish).
#
# Usage:
#   scripts/release.sh                 # build (+sign/notarize if configured)
#   scripts/release.sh --publish       # also create/update the GitHub release
#   VERSION=0.2.0 scripts/release.sh   # override the version (default: project.yml)
#
# Signing / notarization (all optional — omit to build unsigned):
#   SIGN_IDENTITY      "Developer ID Application: Name (TEAMID)" — the codesign identity.
#   NOTARY_PROFILE     Name of a stored `notarytool store-credentials` profile.
#     …or, instead of a profile:
#   APPLE_ID           Apple ID email used for notarization.
#   APPLE_TEAM_ID      10-char Apple Developer Team ID.
#   APPLE_APP_PASSWORD App-specific password (appleid.apple.com → Sign-In & Security).
#
# Toolchain:
#   DEVELOPER_DIR      Overrides the Xcode used. Defaults to Xcode-beta if present
#                      (this project currently needs the macOS 27 beta SDK).
#
# Release checklist:
#   Before cutting a release, verify every first-party plugin's `AinkradAPIVersion`
#   ∈ [GenerationSupport.minSupported … GenerationSupport.current] and its
#   project.yml SDK `revision:` == the host's `revision:`.
#   On any AinkradAppKit revision bump, do a CLEAN build (wipe DerivedData) — the
#   resilient ABI makes stale gen-N DerivedData produce spurious
#   `unsafeMutableAddressor`/witness-table link errors.
#
set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

# --- toolchain -------------------------------------------------------------
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

PUBLISH=false
[[ "${1:-}" == "--publish" ]] && PUBLISH=true

# --- version ---------------------------------------------------------------
if [[ -z "${VERSION:-}" ]]; then
  VERSION="$(grep -m1 'MARKETING_VERSION:' project.yml | sed -E 's/.*"([^"]+)".*/\1/')"
fi
if [[ -z "${VERSION:-}" ]]; then
  echo "error: could not determine VERSION (set MARKETING_VERSION in project.yml or pass VERSION=)" >&2
  exit 1
fi
TAG="v${VERSION}"
DIST="${REPO_ROOT}/dist"
BUILD="${DIST}/build"
APP_PATH="${BUILD}/Build/Products/Release/Ainkrad.app"
DMG="${DIST}/Ainkrad-${VERSION}.dmg"

echo "▸ Ainkrad ${VERSION} (${TAG})"
echo "  Xcode: ${DEVELOPER_DIR:-$(xcode-select -p)}"

# --- preflight -------------------------------------------------------------
# The cross-repo invariants in the checklist above are no longer prose: they run
# here. `--fast` skips the family-wide test sweep (minutes) but still asserts
# SDK pin equality, the ABI baseline, and every plugin's API version — the three
# things that make plugins silently vanish. Set SKIP_PREFLIGHT=1 to bypass.
if [[ "${SKIP_PREFLIGHT:-}" != "1" ]]; then
  "${REPO_ROOT}/scripts/preflight.sh" --fast || {
    echo "error: preflight failed — refusing to build a release. (SKIP_PREFLIGHT=1 to override)" >&2
    exit 1
  }
fi

# --- build -----------------------------------------------------------------
command -v xcodegen >/dev/null 2>&1 && { echo "▸ xcodegen generate"; xcodegen generate >/dev/null; }

rm -rf "$DIST"; mkdir -p "$DIST"
echo "▸ Building Release…"
xcodebuild -scheme Ainkrad -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$BUILD" build >/dev/null
[[ -d "$APP_PATH" ]] || { echo "error: build produced no app at $APP_PATH" >&2; exit 1; }

BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
[[ "$BUILT_VERSION" == "$VERSION" ]] || echo "  warning: built version ${BUILT_VERSION} != ${VERSION}"

# --- sign ------------------------------------------------------------------
SIGNED=false
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "▸ Signing with: ${SIGN_IDENTITY}"
  # Inside-out: sign every nested dylib/framework first, then the app bundle,
  # each with the hardened runtime + a secure timestamp (both required for
  # notarization). --deep is intentionally avoided (Apple discourages it).
  while IFS= read -r -d '' item; do
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$item"
  done < <(find "$APP_PATH/Contents/Frameworks" \( -name '*.dylib' -o -name '*.framework' \) -print0 2>/dev/null)
  codesign --force --options runtime --timestamp \
    --entitlements config/Ainkrad.entitlements \
    --sign "$SIGN_IDENTITY" "$APP_PATH"
  codesign --verify --strict --verbose=2 "$APP_PATH"

  # The hardened runtime enables dyld LIBRARY VALIDATION, which refuses to load
  # any Mach-O not signed by the host's Team ID — i.e. every plugin. Ainkrad
  # replaces that check with an in-process Developer-ID check
  # (`DeveloperIDSignaturePolicy`) and disables the dyld one via the entitlement
  # above. If that entitlement is ever dropped from the signature, the app ships
  # loading ZERO plugins and looks like it simply has no apps — so verify it is
  # actually present rather than trusting the file was passed.
  if ! codesign -d --entitlements :- "$APP_PATH" 2>/dev/null \
       | grep -q 'com.apple.security.cs.disable-library-validation'; then
    echo "error: signed app is missing com.apple.security.cs.disable-library-validation." >&2
    echo "       Under the hardened runtime NO plugin would load. Refusing to continue." >&2
    exit 1
  fi
  SIGNED=true
else
  echo "▸ No SIGN_IDENTITY — building UNSIGNED (users right-click → Open on first launch)."
fi

# --- package dmg -----------------------------------------------------------
echo "▸ Packaging ${DMG##*/}…"
STAGE="${DIST}/dmg-stage"; rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Ainkrad ${VERSION}" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

# Sign the DISK IMAGE itself, not just the app inside it. Notarizing and
# stapling a DMG is enough for Gatekeeper to let a download through, but an
# unsigned container has no signature for `spctl` (or a cautious user running
# `codesign -dv`) to evaluate at all -- it reports "code object is not signed
# at all". Apple recommends signing the image; doing so costs one command and
# removes the ambiguity from the artifact people actually download.
#
# Must happen BEFORE notarization: the notary service hashes what it is given,
# and signing afterwards would invalidate the stapled ticket.
if [[ "$SIGNED" == true ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
  codesign --verify --strict --verbose=2 "$DMG"
fi

# --- notarize + staple -----------------------------------------------------
NOTARIZED=false
if [[ "$SIGNED" == true ]]; then
  NOTARY_ARGS=()
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
  elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
    NOTARY_ARGS=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
  fi
  if [[ ${#NOTARY_ARGS[@]} -gt 0 ]]; then
    echo "▸ Notarizing (this can take a few minutes)…"
    xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" --wait
    echo "▸ Stapling ticket…"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    NOTARIZED=true
  else
    echo "▸ Signed but no notary credentials — skipping notarization."
  fi
fi

echo "✓ Built: ${DMG}"
$SIGNED     && echo "  signed:     yes" || echo "  signed:     NO (unsigned)"
$NOTARIZED  && echo "  notarized:  yes" || echo "  notarized:  no"

# --- publish ---------------------------------------------------------------
if [[ "$PUBLISH" == true ]]; then
  # Fail CLOSED on an ACCIDENTALLY unsigned release; allow a DELIBERATE one.
  #
  # Publishing an un-notarized dmg has a real cost: Gatekeeper blocks it, and
  # the user has to go to System Settings > Privacy & Security to run it. That
  # trains exactly the habit that makes malware easy, so it must never happen
  # by accident.
  #
  # But notarization requires a PAID Apple Developer Program membership, and
  # until that exists an unsigned release is the only release possible. Refusing
  # outright would mean shipping nothing at all. So it is permitted, loudly, and
  # only when asked for by name: UNSIGNED_RELEASE=1 states the intent, whereas a
  # generic "force" flag would get set once and never removed.
  if [[ "$NOTARIZED" != true ]]; then
    if [[ "${UNSIGNED_RELEASE:-}" != "1" ]]; then
      echo "error: refusing to publish a build that is not signed AND notarized." >&2
      echo "       signed=${SIGNED} notarized=${NOTARIZED}" >&2
      echo "       With a Developer ID: set SIGN_IDENTITY + NOTARY_PROFILE." >&2
      echo "       Without one: UNSIGNED_RELEASE=1 to publish deliberately unsigned." >&2
      exit 1
    fi
    echo
    echo "  ⚠ PUBLISHING UNSIGNED. Users will hit a Gatekeeper block and must"
    echo "    allow the app in System Settings > Privacy & Security."
    echo "    Plugin signatures will also NOT be verified at runtime: an"
    echo "    unsigned host cannot demand a Developer-ID signature it has no"
    echo "    way to produce (see PluginTrust). The App Store surface says so."
    echo
  fi
  command -v gh >/dev/null 2>&1 || { echo "error: --publish needs the gh CLI" >&2; exit 1; }
  ASSET="${DMG}#Ainkrad ${VERSION} (Apple Silicon).dmg"
  if gh release view "$TAG" >/dev/null 2>&1; then
    echo "▸ Release ${TAG} exists — uploading asset (clobber)…"
    gh release upload "$TAG" "$ASSET" --clobber
  else
    echo "▸ Creating release ${TAG}…"
    # `--target` is NOT optional. Without it `gh release create` tags the
    # repository's DEFAULT BRANCH head, not the commit this bundle was built
    # from -- so the uploaded zip and its sha256 can come from code the tag does
    # not contain. That shipped: the host's v0.17.1 tag landed on the previous
    # release's commit while its asset held 79 newer commits.
    gh release create "$TAG" "$ASSET" \
      --target "$(git rev-parse HEAD)" \
      --title "Ainkrad ${VERSION}" \
      --generate-notes
  fi
  echo "✓ Published ${TAG}"
fi
