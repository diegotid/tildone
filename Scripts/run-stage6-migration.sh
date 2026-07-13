#!/bin/zsh
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "usage: $0 /absolute/path/to/default.store /absolute/path/to/new-shared.sqlite [--allow-live-source]" >&2
  exit 64
fi

if [[ "$1" != /* || "$2" != /* ]]; then
  echo "source and destination must both be explicit absolute paths" >&2
  exit 64
fi

if [[ $# -eq 3 && "$3" != "--allow-live-source" ]]; then
  echo "unknown option: $3" >&2
  exit 64
fi

configuration=/tmp/TildoneStage6MigrationTool.plist
lock=/tmp/TildoneStage6MigrationTool.lock
if ! mkdir "$lock"; then
  echo "another Stage 6 migration tool is already running" >&2
  exit 75
fi
snapshot_root=$(/usr/bin/mktemp -d /tmp/TildoneStage6ToolSnapshots.XXXXXX)
trap 'rm -f "$configuration"; rm -rf "$snapshot_root"; rmdir "$lock"' EXIT

/usr/bin/plutil -create xml1 "$configuration"
/usr/bin/plutil -insert source -string "$1" "$configuration"
/usr/bin/plutil -insert destination -string "$2" "$configuration"
/usr/bin/plutil -insert allowLiveSource -bool "$([[ $# -eq 3 ]] && echo true || echo false)" "$configuration"
/usr/bin/plutil -insert snapshotRoot -string "$snapshot_root" "$configuration"

CLANG_MODULE_CACHE_PATH=/tmp/TildoneStage6ToolClang \
SWIFT_MODULECACHE_PATH=/tmp/TildoneStage6ToolSwift \
xcodebuild -project Tildone.xcodeproj \
  -scheme 'Stage6 Migration Tool' \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/TildoneStage6Tool \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:TildoneTests/LegacyMigrationTests/testDeveloperToolRequiresExplicitPathsAndNeverDefaultsToProduction \
  test
