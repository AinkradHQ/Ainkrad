#!/usr/bin/env bash
#
# Family-wide preflight: run every repo's tests and assert the cross-repo
# invariants that were previously only prose.
#
# ## Why this exists
#
# The audit's root cause RC-6: "cross-repo invariants exist as prose, and
# nothing executes them." One CI workflow across eight repos, tag-only, never
# running tests; AinkradAppKit — the ABI-critical repo — had no CI at all. So
# every one of these held only by memory:
#
#   • every repo's tests pass
#   • every repo pins the SAME AinkradAppKit revision as the host
#   • every first-party plugin's AinkradAPIVersion is in the supported range
#   • the SDK's ABI baseline is current
#
# Each is a check that could be a script. This is that script. `release.sh`
# invokes it, so cutting a release cannot skip it.
#
# Usage:
#   scripts/preflight.sh            # everything
#   scripts/preflight.sh --fast     # invariants only, no test runs (~seconds)
#
# Repos are located as siblings of this one; a missing sibling is reported and
# skipped rather than silently passing.
set -uo pipefail

cd "$(dirname "$0")/.."
HOST_ROOT="$(pwd)"
SIBLINGS="$(cd .. && pwd)"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

FAST=false
[[ "${1:-}" == "--fast" ]] && FAST=true

FAILURES=0
fail() { echo "  ✗ $*"; FAILURES=$((FAILURES + 1)); }
ok()   { echo "  ✓ $*"; }

# Plugin repos and the scheme their TESTS hang off. Note these are the
# `*Plugin` schemes, not `*Feature` — the test action is configured on the
# plugin scheme, which is not guessable from the repo name.
PLUGIN_REPOS=(
  "AinkradRune:RunePlugin"
  "GitMage:GitMagePlugin"
  "AinkradLore:LorePlugin"
  "AinkradLeyline:LeylinePlugin"
)

echo "▸ Preflight (siblings: $SIBLINGS)"

# --- 1. SDK pin equality ----------------------------------------------------
echo
echo "▸ AinkradAppKit pin equality"
# A LOCAL PATH dependency is a development-only state: it means the consumer
# builds whatever is in the working tree next door, so "pin equality" is
# meaningless and a release would ship against an unpinned, uncommitted SDK.
# Fail loudly rather than skipping — this is exactly the kind of temporary
# arrangement that gets forgotten.
path_deps=0
for repo in Ainkrad AinkradKit AinkradPluginTemplate AinkradRune GitMage AinkradLore AinkradLeyline AinkradQuest AinkradRaven; do
  dir="$SIBLINGS/$repo"; [[ "$repo" == "Ainkrad" ]] && dir="$HOST_ROOT"
  [[ -d "$dir" ]] || continue
  for manifest in "$dir/project.yml" "$dir/Package.swift"; do
    [[ -f "$manifest" ]] || continue
    if grep -qE 'path: *\.\./AinkradAppKit|\.package\(path: *"\.\./AinkradAppKit"\)' "$manifest"; then
      fail "$repo depends on AinkradAppKit by local PATH — repin to a released revision before shipping"
      path_deps=$((path_deps + 1))
    fi
  done
done

# Extract the `revision:` belonging to the AinkradAppKit package entry.
#
# This was `grep -A5 'AinkradAppKit:' | grep revision:`, and a 10-line
# explanatory comment added between the key and its revision pushed the pin
# past the 5-line window. The check then read an EMPTY pin and — because the
# empty-pin branch only fails when no local path dependency exists — the
# lockstep invariant went unverified while still printing a green-looking run.
# A guard that silently stops guarding is worse than no guard, so scan the
# whole YAML block: from the key until the next line indented no deeper,
# skipping comments and blanks.
appkit_pin() {
  awk '
    /AinkradAppKit:[[:space:]]*$/ && !inblock {
      match($0, /[^ ]/); keyindent = RSTART; inblock = 1; next
    }
    inblock {
      if ($0 ~ /^[[:space:]]*($|#)/) next
      match($0, /[^ ]/)
      if (RSTART <= keyindent) { inblock = 0; next }
      if ($0 ~ /^[[:space:]]*revision:/) { gsub(/^[[:space:]]*revision:[[:space:]]*/, ""); gsub(/["'"'"'].*$/, ""); print; exit }
    }
  ' "$1"
}
host_pin="$(appkit_pin "$HOST_ROOT/project.yml")"
if [[ -z "$host_pin" ]]; then
  if [[ "$path_deps" -gt 0 ]]; then
    echo "  – pin equality not checkable while local path dependencies are in use"
  else
    fail "could not read the host's AinkradAppKit revision from project.yml"
  fi
else
  echo "  host: $host_pin"
  for repo in AinkradKit AinkradPluginTemplate AinkradRune GitMage AinkradLore AinkradLeyline AinkradQuest AinkradRaven; do
    dir="$SIBLINGS/$repo"
    [[ -d "$dir" ]] || { echo "  – $repo (not present, skipped)"; continue; }
    pin=""
    if [[ -f "$dir/project.yml" ]]; then
      pin="$(appkit_pin "$dir/project.yml")"
    fi
    if [[ -z "$pin" && -f "$dir/Package.swift" ]]; then
      pin="$(grep -oE 'revision: "[a-f0-9]{40}"' "$dir/Package.swift" | head -1 | grep -oE '[a-f0-9]{40}')"
    fi
    if [[ -z "$pin" ]]; then
      echo "  – $repo (no AinkradAppKit dependency found, skipped)"
    elif [[ "$pin" == "$host_pin" ]]; then
      ok "$repo"
    else
      # This is the lockstep invariant. It is latent, not active, only for as
      # long as the drift stays purely additive — one added protocol
      # requirement and every drifted plugin fails to load.
      fail "$repo pins $pin, host pins $host_pin"
    fi
  done

  # The CLI's EMBEDDED scaffold template is a second pin site inside a repo
  # whose own manifest already passed. `ainkrad new` copies this file verbatim,
  # so a stale revision here ships a generation-N plugin against a
  # generation-N+1 host — it validates on the developer's machine and then
  # fails `dlopen` in the real one. That is not hypothetical: this pin sat at
  # 293f049 (generation 7) from 2026-07-23 to 2026-08-02 against a
  # generation-8 host, invisible because only AinkradKit/Package.swift was
  # ever checked.
  template="$SIBLINGS/AinkradKit/Sources/ainkrad/Resources/Template/project.yml"
  if [[ -f "$template" ]]; then
    tpin="$(appkit_pin "$template")"
    if [[ -z "$tpin" ]]; then
      fail "could not read the embedded scaffold template's AinkradAppKit revision"
    elif [[ "$tpin" == "$host_pin" ]]; then
      ok "AinkradKit embedded template"
    else
      fail "AinkradKit embedded template pins $tpin, host pins $host_pin — 'ainkrad new' would scaffold against the wrong SDK"
    fi
  fi
fi

# --- 2. SDK ABI baseline is current ----------------------------------------
echo
echo "▸ AinkradAppKit ABI baseline"
if [[ -d "$SIBLINGS/AinkradAppKit" ]]; then
  # ABI_CHECK_FORCE=1 forces AinkradAppKit's abi-check to actually run the
  # real digester rather than silently skip-and-pass when the beta toolchain
  # (the only compiler build that can read the baseline .swiftmodule) is
  # absent. Preflight gates a release, so a missing toolchain here must fail
  # loudly, not sail through as a false pass.
  if (cd "$SIBLINGS/AinkradAppKit" && make abi-check ABI_CHECK_FORCE=1 >/tmp/preflight-abi.log 2>&1); then
    ok "no unreviewed API/ABI changes"
  else
    fail "abi-check failed — see /tmp/preflight-abi.log (either the ABI actually changed, or this machine is missing the Xcode-beta toolchain the digester requires — check the log for which)"
    tail -20 /tmp/preflight-abi.log | sed 's/^/    /'
  fi
else
  fail "AinkradAppKit not found at $SIBLINGS/AinkradAppKit"
fi

# --- 3. Plugin API versions ------------------------------------------------
echo
echo "▸ Plugin AinkradAPIVersion"

# Read the range from the SDK, not from a hand-typed constant. `GenerationSupport`
# now derives both ends from `AinkradAppKit`, so there is no number here to grep.
sdk_api=""
for candidate in \
  "$SIBLINGS/AinkradAppKit/Sources/AinkradAppKitContract/AinkradAPI.swift" \
  "$SIBLINGS/AinkradAppKit/Sources/AinkradAppKit/AinkradAPI.swift"
do
  [[ -f "$candidate" ]] || continue
  sdk_api="$(grep -oE 'apiVersion[[:space:]]*=[[:space:]]*[0-9]+' "$candidate" | grep -oE '[0-9]+$' | head -1)"
  break
done

if [[ -z "$sdk_api" ]]; then
  fail "could not read apiVersion from the AinkradAppKit sources"
else
  # Read the FLOOR from the SDK too, rather than assuming `apiVersion - 1`.
  # That assumption encodes the intended one-generation deprecation window,
  # but generation 8 is a HARD break (the module split renamed every symbol),
  # so the SDK sets `minSupportedAPIVersion = apiVersion`. Computing the floor
  # here made preflight PASS a generation-7 plugin that the host then refuses
  # to load — a false negative in the one check whose whole purpose is to stop
  # plugins from silently vanishing. Derive it, don't guess it.
  min_supported="$(grep -oE 'minSupportedAPIVersion[[:space:]]*=[[:space:]]*apiVersion[[:space:]]*-[[:space:]]*[0-9]+' "$candidate" | grep -oE '[0-9]+$' | head -1)"
  if [[ -n "$min_supported" ]]; then
    min_supported=$((sdk_api - min_supported))
  elif grep -qE 'minSupportedAPIVersion[[:space:]]*=[[:space:]]*apiVersion[[:space:]]*$' "$candidate"; then
    min_supported="$sdk_api"
  else
    min_supported="$(grep -oE 'minSupportedAPIVersion[[:space:]]*=[[:space:]]*[0-9]+' "$candidate" | grep -oE '[0-9]+$' | head -1)"
  fi
  [[ -n "$min_supported" ]] || fail "could not read minSupportedAPIVersion from the AinkradAppKit sources"
  echo "  host supports [$min_supported … $sdk_api]"
  for entry in "${PLUGIN_REPOS[@]}"; do
    repo="${entry%%:*}"
    dir="$SIBLINGS/$repo"
    [[ -d "$dir" ]] || { echo "  – $repo (not present, skipped)"; continue; }

    # The value is GENERATED into the built bundle by scripts/stamp-api-version.sh
    # (wired as a post-build script). Where that is in place, the value checked
    # into Info.plist is documentation, not the authority — so verify the
    # generator is wired rather than the stale source number.
    if grep -q 'stamp-api-version' "$dir/project.yml" 2>/dev/null; then
      ok "$repo (generated from the linked SDK)"
      continue
    fi

    # No generator: the checked-in value IS what ships, so it must be in range.
    while IFS= read -r plist; do
      version="$(/usr/libexec/PlistBuddy -c 'Print AinkradAPIVersion' "$plist" 2>/dev/null || true)"
      [[ -n "$version" ]] || continue
      if [[ "$version" -ge "$min_supported" && "$version" -le "$sdk_api" ]]; then
        ok "$repo ($version, hand-typed)"
      else
        fail "$repo declares AinkradAPIVersion $version, outside [$min_supported … $sdk_api] — the host will refuse to load it"
      fi
    done < <(find "$dir/Sources" -name 'Info.plist' 2>/dev/null)
  done
fi

# --- 3b. Package pins actually resolve --------------------------------------
echo
echo "▸ Package resolution"
# Verify each pinned revision EXISTS UPSTREAM, not merely that a stale
# DerivedData checkout still has it.
#
# A bad pin is invisible while SwiftPM has the old revision cached: the build
# reuses it and everything looks green. That happened — a repin regex clobbered
# Terminal's SwiftTerm revision with the AinkradAppKit SHA, and this script
# reported a pass because the previously-resolved checkout was still on disk.
#
# `git ls-remote <url> <sha>` does NOT work here: it filters by ref NAME, so a
# pinned non-tip commit always looks missing. Fetching the commit is the only
# honest test.
PIN_CACHE="$(mktemp -d)"
git init -q "$PIN_CACHE"
while read -r repo name url rev; do
  [[ -n "$rev" ]] || continue
  if git -C "$PIN_CACHE" fetch -q --depth=1 "$url" "$rev" 2>/dev/null; then
    ok "$repo → $name @ ${rev:0:8}"
  else
    fail "$repo pins $name @ ${rev:0:8}, which does not exist in $url"
  fi
done < <(
  for repo in Ainkrad AinkradKit AinkradPluginTemplate AinkradRune GitMage AinkradLore AinkradLeyline AinkradQuest AinkradRaven; do
    dir="$SIBLINGS/$repo"; [[ "$repo" == "Ainkrad" ]] && dir="$HOST_ROOT"
    [[ -d "$dir" ]] || continue
    for manifest in "$dir/project.yml" "$dir/Package.swift"; do
      [[ -f "$manifest" ]] || continue
      python3 -c "
import re, sys
text = open(sys.argv[1]).read()
pairs  = re.findall(r'url:\s*\"?([^\s\"]+)\"?[^\n]*\n\s*revision:\s*\"?([a-f0-9]{40})\"?', text)
pairs += re.findall(r'\.package\(url:\s*\"([^\"]+)\"\s*,\s*revision:\s*\"([a-f0-9]{40})\"', text)
for url, rev in pairs:
    print(sys.argv[2], url.rstrip('/').split('/')[-1].replace('.git',''), url, rev)
" "$manifest" "$repo"
    done
  done
)
rm -rf "$PIN_CACHE"

# --- 4. Tests ---------------------------------------------------------------
if [[ "$FAST" == true ]]; then
  echo
  echo "▸ Tests skipped (--fast)"
else
  echo
  echo "▸ Tests"
  if xcodebuild -scheme Ainkrad -destination 'platform=macOS' test >/tmp/preflight-host.log 2>&1; then
    ok "Ainkrad (host)"
  else
    fail "Ainkrad (host) — see /tmp/preflight-host.log"
  fi

  for repo in AinkradAppKit AinkradKit; do
    dir="$SIBLINGS/$repo"
    [[ -d "$dir" ]] || { echo "  – $repo (not present, skipped)"; continue; }
    if (cd "$dir" && swift test) >"/tmp/preflight-$repo.log" 2>&1; then
      ok "$repo"
    else
      fail "$repo — see /tmp/preflight-$repo.log"
    fi
  done

  for entry in "${PLUGIN_REPOS[@]}"; do
    repo="${entry%%:*}"; scheme="${entry##*:}"
    dir="$SIBLINGS/$repo"
    [[ -d "$dir" ]] || { echo "  – $repo (not present, skipped)"; continue; }
    if (cd "$dir" && xcodebuild -scheme "$scheme" -destination 'platform=macOS' test) \
        >"/tmp/preflight-$repo.log" 2>&1; then
      ok "$repo ($scheme)"
    else
      fail "$repo ($scheme) — see /tmp/preflight-$repo.log"
    fi
  done
fi

echo
if [[ "$FAILURES" -gt 0 ]]; then
  echo "✗ Preflight FAILED — $FAILURES problem(s)."
  exit 1
fi
echo "✓ Preflight passed."
