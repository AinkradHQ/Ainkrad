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
# Publishing REQUIRES notarization. `--publish` refuses an un-notarized build
# unless ALLOW_UNNOTARIZED names the exact version and ALLOW_UNNOTARIZED_REASON
# says why; the reason is written into the release notes so a warned build is
# never mistaken for a clean one. Store credentials once with:
#
#   xcrun notarytool store-credentials AinkradNotary \
#     --apple-id <you@example.com> --team-id RT9AA68C38
#
# Signing / notarization (all optional for a LOCAL build — omit to build unsigned):
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

# --- release gates (run BEFORE the multi-minute build) ---------------------
BUILD_NUMBER="$(grep -m1 'CURRENT_PROJECT_VERSION:' project.yml | sed -E 's/.*"([^"]+)".*/\1/')"

# The app-icon bundle stamp uses CFBundleVersion to tell one install from the
# next (see `BundleAppIcon`): the bookkeeping lives in UserDefaults, which
# survives app replacement, while the stamp lives in the .app, which does not.
# Ship two releases with the same build number and the second silently stops
# applying the user's chosen icon. Nothing auto-bumps it, so assert it moved.
# Fetch tags first. `gh release create` tags on the REMOTE, so a local-only tag
# list can be a release or more behind -- and a guard that compares against a
# stale baseline reports "safe" while letting the exact defect through. That is
# how this check first shipped: it passed by comparing v0.20.0 against v0.18.0
# because v0.19.0 existed only on the remote.
if ! git fetch --tags --quiet origin 2>/dev/null; then
  echo "warning: could not fetch tags from origin — the build-number check below" >&2
  echo "         is comparing against local tags only and may be stale." >&2
fi
PREV_TAG="$(git tag --list 'v*' --sort=-v:refname | grep -v "^${TAG}$" | head -1 || true)"
if [[ -n "$PREV_TAG" ]]; then
  PREV_BUILD="$(git show "${PREV_TAG}:project.yml" 2>/dev/null \
    | grep -m1 'CURRENT_PROJECT_VERSION:' | sed -E 's/.*"([^"]+)".*/\1/' || true)"
  echo "  build number: ${BUILD_NUMBER} (previous release ${PREV_TAG}: ${PREV_BUILD:-unknown})"
  if [[ -n "$PREV_BUILD" && "$PREV_BUILD" == "$BUILD_NUMBER" ]]; then
    echo "error: CURRENT_PROJECT_VERSION is still ${BUILD_NUMBER} — same as ${PREV_TAG}." >&2
    echo "       The app-icon bundle stamp uses it to detect a new install; reusing" >&2
    echo "       it makes the user's chosen icon silently revert after updating." >&2
    echo "       Bump CURRENT_PROJECT_VERSION in project.yml and retry." >&2
    exit 1
  fi
fi

# Resolve notary credentials NOW rather than after the build, so a missing
# profile costs a second instead of five minutes.
HAVE_NOTARY_CREDS=false
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  HAVE_NOTARY_CREDS=true
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
  HAVE_NOTARY_CREDS=true
fi

if [[ "$PUBLISH" == true ]]; then
  # The escape hatch is scoped to ONE version on purpose. A bare boolean gets
  # exported into a shell once and then quietly un-notarizes every release
  # after it -- which is exactly how v0.19.0 shipped un-notarized while v0.18.0
  # had been fine. A stale value is now inert.
  HATCH_OPEN=false
  if [[ "${ALLOW_UNNOTARIZED:-}" == "$VERSION" ]]; then
    if [[ -z "${ALLOW_UNNOTARIZED_REASON:-}" ]]; then
      echo "error: ALLOW_UNNOTARIZED=${VERSION} also needs ALLOW_UNNOTARIZED_REASON=\"...\"." >&2
      echo "       The reason goes into the release notes so nobody downloads a" >&2
      echo "       warned build thinking it is a clean one." >&2
      exit 1
    fi
    HATCH_OPEN=true
  elif [[ -n "${ALLOW_UNNOTARIZED:-}" ]]; then
    echo "error: ALLOW_UNNOTARIZED=${ALLOW_UNNOTARIZED} does not match the version" >&2
    echo "       being published (${VERSION}). It is scoped to one version so it" >&2
    echo "       cannot linger from a previous release. Unset it, or set it to ${VERSION}." >&2
    exit 1
  fi

  if [[ "$HAVE_NOTARY_CREDS" != true && "$HATCH_OPEN" != true ]]; then
    echo "error: --publish requires notarization, and no notary credentials are set." >&2
    echo "       Without it macOS blocks the download and users must allow the app" >&2
    echo "       in System Settings > Privacy & Security." >&2
    echo >&2
    echo "       Store them once (needs a paid Apple Developer membership):" >&2
    echo "         xcrun notarytool store-credentials AinkradNotary \\" >&2
    echo "           --apple-id <you@example.com> --team-id ${APPLE_TEAM_ID:-<TEAMID>}" >&2
    echo "       then re-run with NOTARY_PROFILE=AinkradNotary." >&2
    echo >&2
    echo "       To ship un-notarized anyway, deliberately, for THIS version only:" >&2
    echo "         ALLOW_UNNOTARIZED=${VERSION} ALLOW_UNNOTARIZED_REASON=\"why\"" >&2
    exit 1
  fi
  if [[ -z "${SIGN_IDENTITY:-}" && "$HATCH_OPEN" != true ]]; then
    echo "error: --publish needs SIGN_IDENTITY (or the ALLOW_UNNOTARIZED hatch)." >&2
    exit 1
  fi
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
    SUBMIT_LOG="${DIST}/notarytool-submit.log"
    xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" --wait 2>&1 | tee "$SUBMIT_LOG"
    # `notarytool submit --wait` exits 0 even when the submission comes back
    # Invalid, so the exit code proves nothing -- read the status it printed.
    if ! grep -qE '^[[:space:]]*status: Accepted' "$SUBMIT_LOG"; then
      echo "error: notarization did not return Accepted. See ${SUBMIT_LOG}." >&2
      echo "       Fetch the detail with: xcrun notarytool log <submission-id>" >&2
      exit 1
    fi
    echo "▸ Stapling ticket…"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    # Gatekeeper's verdict is the only one a user experiences, so ask it
    # directly rather than inferring success from the steps above. This is the
    # exact check that distinguished a good v0.18.0 from a bad v0.19.0.
    if ! spctl -a -vvv -t open --context context:primary-signature "$DMG" 2>&1 \
         | grep -q 'source=Notarized Developer ID'; then
      echo "error: the dmg does not evaluate as 'Notarized Developer ID'." >&2
      echo "       Stapling appeared to succeed but Gatekeeper disagrees." >&2
      spctl -a -vvv -t open --context context:primary-signature "$DMG" 2>&1 | sed 's/^/       /' >&2
      exit 1
    fi
    NOTARIZED=true
  else
    echo "▸ NOT NOTARIZED: signed, but no notary credentials are configured."
    echo "  A local build is fine. Publishing this would make macOS block the"
    echo "  download — see the --publish gate for how to fix or override."
  fi
fi

echo "✓ Built: ${DMG}"
$SIGNED     && echo "  signed:     yes" || echo "  signed:     NO (unsigned)"
$NOTARIZED  && echo "  notarized:  yes" || echo "  notarized:  no"

# --- publish ---------------------------------------------------------------
if [[ "$PUBLISH" == true ]]; then
  # The gates that decide WHETHER to publish already ran before the build, so
  # by here the only job left is to warn loudly and label the artifact.
  if [[ "$NOTARIZED" != true ]]; then
    echo
    echo "  ⚠ PUBLISHING WITHOUT NOTARIZATION (signed, not notarized)."
    echo "    Reason: ${ALLOW_UNNOTARIZED_REASON}"
    echo "    macOS will block the download; users must allow the app in"
    echo "    System Settings > Privacy & Security. Plugin signatures will also"
    echo "    NOT be verified at runtime (see PluginTrust)."
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
  # An un-notarized build must be visibly labelled on the release page, or it
  # looks identical to a clean one to whoever downloads it. Generated notes are
  # kept and the warning is prepended.
  if [[ "$NOTARIZED" != true ]]; then
    echo "▸ Labelling ${TAG} as not notarized…"
    EXISTING_NOTES="$(gh release view "$TAG" --json body --jq .body || true)"
    WARNING="> ⚠ **This build is NOT notarized** (${ALLOW_UNNOTARIZED_REASON}).
> macOS will warn on first launch — allow it in
> System Settings → Privacy & Security. Plugin signatures are not
> verified at runtime in this build."
    gh release edit "$TAG" --notes "${WARNING}

${EXISTING_NOTES}"
  fi
  echo "✓ Published ${TAG}"
  $NOTARIZED && echo "  notarized:  yes" || echo "  notarized:  NO — release page is labelled"
fi
