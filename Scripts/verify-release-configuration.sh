#!/bin/zsh
set -euo pipefail

repository_root=${0:A:h:h}
project="$repository_root/Tildone.xcodeproj"
schemes_directory="$project/xcshareddata/xcschemes"
scratch=$(/usr/bin/mktemp -d /tmp/TildoneReleaseConfiguration.XXXXXX)
trap 'rm -rf "$scratch"' EXIT

assert_scheme() {
  local scheme_file="$schemes_directory/$1.xcscheme"
  [[ -f "$scheme_file" ]] || { echo "missing shared scheme: $scheme_file" >&2; exit 1; }
  /usr/bin/grep -A2 '<LaunchAction' "$scheme_file" | /usr/bin/grep -q 'buildConfiguration = "Debug"' || {
    echo "$1 launch action is not Debug" >&2
    exit 1
  }
  /usr/bin/grep -A2 '<ArchiveAction' "$scheme_file" | /usr/bin/grep -q 'buildConfiguration = "Release"' || {
    echo "$1 archive action is not Release" >&2
    exit 1
  }
  if /usr/bin/grep -q 'language =' "$scheme_file"; then
    echo "$1 forces a launch language" >&2
    exit 1
  fi
}

assert_setting() {
  local settings_file=$1
  local expected=$2
  /usr/bin/grep -q "^[[:space:]]*$expected$" "$settings_file" || {
    echo "missing build setting: $expected" >&2
    exit 1
  }
}

assert_scheme "Tildone"
assert_scheme "Tildone iOS"

cd "$repository_root"
CLANG_MODULE_CACHE_PATH="$scratch/clang" \
SWIFT_MODULECACHE_PATH="$scratch/swift" \
/usr/bin/xcodebuild -project "$project" -scheme Tildone -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$scratch/mac" \
  CODE_SIGNING_ALLOWED=NO -showBuildSettings > "$scratch/mac-settings.txt"

CLANG_MODULE_CACHE_PATH="$scratch/clang" \
SWIFT_MODULECACHE_PATH="$scratch/swift" \
/usr/bin/xcodebuild -project "$project" -scheme 'Tildone iOS' -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$scratch/ios" \
  CODE_SIGNING_ALLOWED=NO -showBuildSettings > "$scratch/ios-settings.txt"

assert_setting "$scratch/mac-settings.txt" 'CONFIGURATION = Release'
assert_setting "$scratch/mac-settings.txt" 'PRODUCT_BUNDLE_IDENTIFIER = studio.cuatro.tildone'
assert_setting "$scratch/mac-settings.txt" 'CODE_SIGN_ENTITLEMENTS = Tildone/Tildone.entitlements'
assert_setting "$scratch/mac-settings.txt" 'MACOSX_DEPLOYMENT_TARGET = 14.0'
assert_setting "$scratch/ios-settings.txt" 'CONFIGURATION = Release'
assert_setting "$scratch/ios-settings.txt" 'PRODUCT_BUNDLE_IDENTIFIER = studio.cuatro.tildone.ios'
assert_setting "$scratch/ios-settings.txt" 'CODE_SIGN_ENTITLEMENTS = TildoneiOS/TildoneiOS.entitlements'
assert_setting "$scratch/ios-settings.txt" 'IPHONEOS_DEPLOYMENT_TARGET = 17.0'

if /usr/bin/grep -Eq '^[[:space:]]*SWIFT_ACTIVE_COMPILATION_CONDITIONS = .*DEBUG' \
  "$scratch/mac-settings.txt" "$scratch/ios-settings.txt"; then
  echo "a Release app target defines DEBUG" >&2
  exit 1
fi

echo "Release scheme and build-setting assertions passed."
