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

assert_entitlement() {
  local file=$1
  local key=$2
  local expected=$3
  local actual
  actual=$(/usr/libexec/PlistBuddy -c "Print :$key" "$repository_root/$file")
  [[ "$actual" = "$expected" ]] || {
    echo "incorrect entitlement $key in $file" >&2
    exit 1
  }
}

assert_entitlement Tildone/Tildone.entitlements com.apple.developer.icloud-container-environment Development
assert_entitlement TildoneiOS/TildoneiOS.entitlements com.apple.developer.icloud-container-environment Development
assert_entitlement Tildone/Tildone.Release.entitlements com.apple.developer.icloud-container-environment Production
assert_entitlement TildoneiOS/TildoneiOS.Release.entitlements com.apple.developer.icloud-container-environment Production
assert_entitlement Tildone/Tildone.entitlements com.apple.developer.aps-environment development
assert_entitlement TildoneiOS/TildoneiOS.entitlements aps-environment development
assert_entitlement Tildone/Tildone.Release.entitlements com.apple.developer.aps-environment production
assert_entitlement TildoneiOS/TildoneiOS.Release.entitlements aps-environment production

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
assert_setting "$scratch/mac-settings.txt" 'CODE_SIGN_ENTITLEMENTS = Tildone/Tildone.Release.entitlements'
assert_setting "$scratch/mac-settings.txt" 'MACOSX_DEPLOYMENT_TARGET = 14.0'
assert_setting "$scratch/ios-settings.txt" 'CONFIGURATION = Release'
assert_setting "$scratch/ios-settings.txt" 'PRODUCT_BUNDLE_IDENTIFIER = studio.cuatro.tildone'
assert_setting "$scratch/ios-settings.txt" 'CODE_SIGN_ENTITLEMENTS = TildoneiOS/TildoneiOS.Release.entitlements'
assert_setting "$scratch/ios-settings.txt" 'IPHONEOS_DEPLOYMENT_TARGET = 17.0'

for platform in mac ios; do
  if [[ "$platform" = mac ]]; then
    scheme=Tildone
    destination='generic/platform=macOS'
    entitlement=Tildone/Tildone.entitlements
  else
    scheme='Tildone iOS'
    destination='generic/platform=iOS'
    entitlement=TildoneiOS/TildoneiOS.entitlements
  fi
  CLANG_MODULE_CACHE_PATH="$scratch/clang" \
  SWIFT_MODULECACHE_PATH="$scratch/swift" \
  /usr/bin/xcodebuild -project "$project" -scheme "$scheme" -configuration Debug \
    -destination "$destination" -derivedDataPath "$scratch/$platform" \
    CODE_SIGNING_ALLOWED=NO -showBuildSettings > "$scratch/$platform-debug-settings.txt"
  assert_setting "$scratch/$platform-debug-settings.txt" 'CONFIGURATION = Debug'
  assert_setting "$scratch/$platform-debug-settings.txt" "CODE_SIGN_ENTITLEMENTS = $entitlement"
  /usr/bin/grep -Eq '^[[:space:]]*SWIFT_ACTIVE_COMPILATION_CONDITIONS = .*DEBUG' \
    "$scratch/$platform-debug-settings.txt" || {
    echo "a Debug app target does not define DEBUG" >&2
    exit 1
  }
done

if /usr/bin/grep -Eq '^[[:space:]]*SWIFT_ACTIVE_COMPILATION_CONDITIONS = .*DEBUG' \
  "$scratch/mac-settings.txt" "$scratch/ios-settings.txt"; then
  echo "a Release app target defines DEBUG" >&2
  exit 1
fi

echo "Release scheme and build-setting assertions passed."
