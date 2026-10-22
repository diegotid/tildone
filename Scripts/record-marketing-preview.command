#!/bin/bash
# Run from Finder/Terminal's GUI session when the agent cannot launch native apps.
set -euo pipefail
capture_app="${1:-/tmp/TildoneMarketingDerivedData/Build/Products/Debug/TildonePreviewStudio.app}"
if [[ ! -x "$capture_app/Contents/MacOS/Tildone" ]]; then
    echo "Build the private marketing preview app before recording."
    exit 1
fi
capture_runner=$(/usr/libexec/PlistBuddy -c "Print :MarketingRecordScript" "$capture_app/Contents/Info.plist")
/usr/bin/python3 "$capture_runner" --app "$capture_app"
