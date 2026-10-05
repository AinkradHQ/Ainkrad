#!/usr/bin/env bash
# Seeds a deterministic fixture root for Debug-host parity captures (task 5A.00).
#
#   scripts/parity-fixture.sh <fixture-dir>
#   open -n build/Build/Products/Debug/Ainkrad.app --args -AinkradFixtureRoot <fixture-dir>
#
# Idempotent: wipes and reseeds <fixture-dir>, so every capture sees identical content.
# Layout matches DebugFixtureRoots (Pointer/ Cache/ Vault/) plus the files a fixture launch
# reads from the root itself (signal.sqlite, signal-preferences.json, catalog.json).
# The on-disk formats are decoded by Tests/AinkradTests/ParityFixtureScriptTests.swift.
#
# Never touches ~/Library/Application Support/com.ainkrad.app; refuses ~/Ainkrad and $HOME.
set -euo pipefail

[[ $# -eq 1 && -n "$1" ]] || { echo "usage: $0 <fixture-dir>" >&2; exit 2; }
command -v sqlite3 >/dev/null || { echo "sqlite3 not found" >&2; exit 2; }

MARKER=.parity-fixture
case "$1" in /*) FIX="$1" ;; *) FIX="$PWD/$1" ;; esac
FIX="${FIX%/}"
# Physical path of the nearest existing ancestor + the not-yet-existing tail.
phys() {
  local p="$1" tail=""
  while [[ ! -d "$p" ]]; do tail="/$(basename "$p")$tail"; p="$(dirname "$p")"; done
  echo "$(cd "$p" && pwd -P)$tail"
}
FIX="$(phys "$FIX")"

REAL_HOME="$(cd "$HOME" && pwd -P)"
refuse() { echo "refusing fixture dir '$FIX': $1" >&2; exit 1; }
[[ "$FIX" != "/" ]] || refuse "is /"
[[ "$FIX" != "$REAL_HOME" ]] || refuse "is the real Home"
case "$FIX/" in
  "$REAL_HOME/Ainkrad/"*) refuse "is inside ~/Ainkrad (the vault)" ;;
  "$REAL_HOME/Library/Application Support/"*) refuse "is inside ~/Library/Application Support" ;;
  "$REAL_HOME/"*) : ;;
esac
# Only ever wipe an empty dir or a previous fixture.
if [[ -e "$FIX" ]]; then
  [[ -d "$FIX" ]] || refuse "exists and is not a directory"
  if [[ -n "$(ls -A "$FIX")" && ! -f "$FIX/$MARKER" ]]; then
    refuse "is not empty and not a previous parity fixture (no $MARKER)"
  fi
fi

rm -rf "$FIX"
mkdir -p "$FIX/Pointer" "$FIX/Cache" "$FIX/Vault/Config" "$FIX/Hoard"
echo "Ainkrad parity fixture; safe to delete and reseed." > "$FIX/$MARKER"

# ---- fixed clock -----------------------------------------------------------------------
# Every timestamp derives from this instant. The files never depend on the wall clock.
BASE_ISO="2026-10-01T12:00:00Z"
BASE_UNIX=1790856000   # 2026-10-01T12:00:00Z
REF_OFFSET=978307200   # Unix epoch -> Foundation reference date (2001-01-01)
[[ "$(date -u -r "$BASE_UNIX" +%Y-%m-%dT%H:%M:%SZ)" == "$BASE_ISO" ]] || { echo "BASE_UNIX drifted" >&2; exit 1; }
ref() { echo $(( BASE_UNIX - REF_OFFSET - $1 )); }   # reference-date seconds, $1 s before BASE

# FileDocumentStore envelope: {schemaVersion, updatedAt, payload}. Home: Vault/Config.
doc() { # <documentID> <payload-json>
  printf '{"payload":%s,"schemaVersion":1,"updatedAt":"%s"}\n' "$2" "$BASE_ISO" > "$FIX/Vault/Config/$1.json"
}

# ---- Home ------------------------------------------------------------------------------
# Marker present => AinkradHome.validate accepts the non-empty Vault; the pointer stays unset,
# so a fixture launch adopts Vault/ (LaunchHomeResolver) and keeps this content.
cat > "$FIX/Vault/.ainkrad-home" <<E
{
  "createdAt" : "$BASE_ISO",
  "homeID" : "00000000-0000-4000-8000-00000000F170",
  "schemaVersion" : 1
}
E

doc setup "{\"completedAt\":\"$BASE_ISO\",\"deferredSteps\":[],\"setupVersion\":1}"
# Sky motion off (removes the ambient moving layers); layout restore on so panes survive launch.
doc global-settings '{"restoreLayoutOnLaunch":true,"skyMotionEnabled":false}'

# ---- Workspaces and panes --------------------------------------------------------------
# main (the home island) stays empty by design; "Fixture" holds 3 panes: Sage | (Hoard / Scry).
doc workspace-layout '{
 "activeWorkspaceIndex":0,
 "workspaces":[
  {"isMain":true,"name":"Home","viewMode":"split"},
  {"isMain":false,"name":"Fixture","viewMode":"split","root":{
    "axis":"h","fractions":[0.5,0.5],"children":[
      {"appID":"sage"},
      {"axis":"v","fractions":[0.5,0.5],"children":[{"appID":"hoard"},{"appID":"scry"}]}
    ]}}
 ]}'

# ---- Hoard: one pinned root inside the fixture, ~20 files -------------------------------
HOARD="$FIX/Hoard"
mkdir -p "$HOARD/Projects" "$HOARD/Notes" "$HOARD/Media"
i=1
for f in Projects/roadmap.md Projects/budget.csv Projects/main.swift Projects/Package.swift \
         Projects/README.md Notes/ideas.txt Notes/meeting-1.md Notes/meeting-2.md \
         Notes/todo.txt Notes/journal.md Media/cover.png Media/clip.mov Media/track.wav \
         Media/poster.jpg report-q3.pdf invoice-0042.pdf archive.zip scratch.json \
         .hidden-config LICENSE; do
  # deterministic size and mtime
  head -c $(( i * 731 )) /dev/zero | tr '\0' 'x' > "$HOARD/$f"
  touch -t 202610011200 "$HOARD/$f"
  i=$(( i + 1 ))
done
touch -t 202610011200 "$HOARD/Projects" "$HOARD/Notes" "$HOARD/Media"
doc files-pinned-roots "{\"paths\":[\"$HOARD\"]}"
doc files-pane "{\"activeTabIndex\":0,\"showHidden\":false,\"sortAscending\":true,\"sortKey\":\"name\",\"tabPaths\":[\"$HOARD\"]}"

# ---- App Store: local catalog (no network) ---------------------------------------------
# Fixture launches read <root>/catalog.json (defaultHostCatalogURL, #if DEBUG). No screenshots
# and no remote links, so nothing is fetched. downloadURL is never reached unless Install is pressed.
cat > "$FIX/catalog.json" <<E
{
  "schemaVersion": 1,
  "apps": [
    {"appID":"fixture-notes","displayName":"Fixture Notes","icon":"note.text",
     "description":"A small notes app for parity captures.","version":"v1.0.0","apiVersion":11,
     "downloadURL":"https://example.invalid/fixture-notes.bundle.zip",
     "sha256":"0000000000000000000000000000000000000000000000000000000000000001",
     "sourceRepo":"fixture/notes","author":"Fixture Author",
     "longDescription":"Fixture Notes exists only so the App Store has stable content.\n\nNothing here is downloaded.",
     "screenshots":[],"links":[]},
    {"appID":"fixture-metrics","displayName":"Fixture Metrics","icon":"chart.bar",
     "description":"Charts for parity captures.","version":"v2.3.1","apiVersion":11,
     "downloadURL":"https://example.invalid/fixture-metrics.bundle.zip",
     "sha256":"0000000000000000000000000000000000000000000000000000000000000002",
     "sourceRepo":"fixture/metrics","author":"Fixture Author","screenshots":[],"links":[]},
    {"appID":"fixture-clock","displayName":"Fixture Clock","icon":"clock",
     "description":"A clock for parity captures.","version":"v0.4.0","apiVersion":11,
     "downloadURL":"https://example.invalid/fixture-clock.bundle.zip",
     "sha256":"0000000000000000000000000000000000000000000000000000000000000003",
     "sourceRepo":"fixture/clock","screenshots":[],"links":[]}
  ]
}
E

# ---- Signals: 12 events, 3 sources, one grouped repeat ----------------------------------
# <fixture>/signal.sqlite (the host puts it beside Cache/). Schema v2, as AinkradSignal.SignalStore
# creates it; the host's own migration only runs forward from here.
# Retention: the host sweeps rows older than maxAgeDays at launch, so the fixture widens it,
# otherwise these fixed (by then old) timestamps would be deleted on launch.
echo '{"retention":{"maxAgeDays":36500,"maxEvents":10000}}' > "$FIX/signal-preferences.json"

DB="$FIX/signal.sqlite"
{
cat <<'SQL'
CREATE TABLE schema_meta (version INTEGER NOT NULL);
INSERT INTO schema_meta (version) VALUES (2);
CREATE TABLE events (
  id TEXT PRIMARY KEY, timestamp REAL NOT NULL, source_kind TEXT NOT NULL, source_app_id TEXT,
  kind TEXT NOT NULL, severity TEXT NOT NULL, title TEXT NOT NULL, body TEXT,
  importance TEXT NOT NULL, deep_link BLOB, actions BLOB, dedupe_key TEXT,
  dedupe_count INTEGER NOT NULL DEFAULT 1, read_at REAL, pinned INTEGER NOT NULL DEFAULT 0);
CREATE INDEX idx_events_ts ON events(timestamp DESC);
CREATE INDEX idx_events_source ON events(source_kind, source_app_id, timestamp DESC);
CREATE INDEX idx_events_unread ON events(read_at) WHERE read_at IS NULL;
CREATE INDEX idx_events_dedupe ON events(source_kind, source_app_id, dedupe_key, timestamp DESC)
  WHERE dedupe_key IS NOT NULL;
CREATE VIRTUAL TABLE events_fts USING fts5(title, body, kind, content='events', content_rowid='rowid');
SQL
n=0
ev() { # <secs-before-base> <source_kind> <app|-> <kind> <severity> <importance> <title> <body> <dedupe_key|-> <count> <read(0/1)> <pinned>
  n=$(( n + 1 ))
  local id; id=$(printf '00000000-0000-4000-8000-%012d' "$n")
  local app="NULL" key="NULL" read="NULL"
  [[ "$3" != "-" ]] && app="'$3'"
  [[ "$9" != "-" ]] && key="'$9'"
  [[ "${11}" == 1 ]] && read="$(ref $(( $1 - 30 )))"
  echo "INSERT INTO events (id,timestamp,source_kind,source_app_id,kind,severity,title,body,importance,dedupe_key,dedupe_count,read_at,pinned) VALUES ('$id',$(ref "$1"),'$2',$app,'$4','$5','$7','$8','$6',$key,${10},$read,${12});"
}
ev   3600 host - install.complete   success normal     "Fixture Notes installed"       "Version 1.0.0 is ready."          -                     1 1 0
ev   7200 host - update.completed   success normal     "Fixture Metrics updated"       "Now on 2.3.1."                    -                     1 1 0
ev  10800 host - install.failed     failure urgent     "Fixture Clock failed to install" "The download was interrupted."     -                     1 0 0
ev  14400 host - signal.test        info    background "Fixture heads-up"              "Nothing to do."                   -                     1 0 0
ev  18000 sage - sage.run.finished  success normal     "Refactor finished"             "12 files changed, tests green."   -                     1 1 0
ev  21600 sage - sage.run.failed    failure urgent     "Build step failed"             "exit status 65 in make build"     -                     1 0 0
ev  25200 sage - sage.approval      warning normal     "Approval needed"               "Run rm -rf build?"                -                     1 0 0
ev  28800 app hoard hoard.copy.done success normal     "Copied 20 items"               "Projects to Archive."             -                     1 1 0
ev  32400 app hoard hoard.copy.done success normal     "Copied 3 items"                "Notes to Archive."                -                     1 1 0
ev  36000 app hoard hoard.sync.repeat warning background "Folder changed on disk"       "Fixture/Hoard was modified."      hoard:folder-changed  5 0 0
ev  39600 app hoard hoard.trash     info    background "Moved 2 items to Trash"        "scratch.json, archive.zip."       -                     1 1 0
ev  43200 app hoard hoard.pinned    info    normal     "Pinned folder added"           "Hoard fixture root."              -                     1 0 1
cat <<'SQL'
INSERT INTO events_fts (rowid, title, body, kind) SELECT rowid, title, body, kind FROM events;
SQL
} | sqlite3 "$DB"

# Subscription approvals (screen N7): needs a built plugin bundle that DECLARES a signal
# subscription; the approvals file alone cannot create the "unapproved" state. See report.
echo "parity fixture ready: $FIX"
