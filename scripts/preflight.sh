#!/bin/sh
# Checks what App Store Connect rejects a build for, before any upload: icon, privacy manifest,
# export compliance, usage strings and version numbers.
#   scripts/preflight.sh                  builds an unsigned iOS Release app, then checks it
#   scripts/preflight.sh Some.xcarchive   checks an archive (or a .app) you already have
# BUILD_NUMBER sets CURRENT_PROJECT_VERSION for the build, so no file is edited.
set -eu
cd "$(dirname "$0")/.."

fail=0
bad() { echo "FAIL: $1"; fail=1; }
ok() { echo "ok:   $1"; }

target="${1:-}"
if [ -z "$target" ]; then
  DD="${DERIVED_DATA:-build/dd-preflight}"
  echo "== Building iOS Release (unsigned)"
  xcodebuild -quiet -project ShowRecorder.xcodeproj -scheme ShowRecorder -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO \
    ${BUILD_NUMBER:+CURRENT_PROJECT_VERSION="$BUILD_NUMBER"} build
  target="$DD/Build/Products/Release-iphoneos/ShowRecorder.app"
fi
case "$target" in
  *.xcarchive) app=$(ls -d "$target"/Products/Applications/*.app | head -n 1) ;;
  *) app="$target" ;;
esac
[ -d "$app" ] || { echo "No app found at $target"; exit 2; }
echo "== Checking $app"

plist="$app/Info.plist"
read_key() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist" 2>/dev/null || true; }

version=$(read_key CFBundleShortVersionString)
build=$(read_key CFBundleVersion)
case "$version" in ''|*'$('*) bad "CFBundleShortVersionString is '$version'" ;; *) ok "version $version" ;; esac
if echo "$build" | grep -Eq '^[0-9]+(\.[0-9]+){0,2}$'; then ok "build number $build"; else bad "CFBundleVersion is '$build' (must be 1 to 3 dot-separated whole numbers)"; fi

compliance=$(read_key ITSAppUsesNonExemptEncryption)
if [ "$compliance" = "false" ] || [ "$compliance" = "true" ]; then
  ok "ITSAppUsesNonExemptEncryption = $compliance"
else
  bad "ITSAppUsesNonExemptEncryption is missing from Info.plist"
fi

for key in NSMicrophoneUsageDescription NSLocalNetworkUsageDescription; do
  [ -n "$(read_key $key)" ] && ok "$key present" || bad "$key is missing"
done

manifest="$app/PrivacyInfo.xcprivacy"
if [ -f "$manifest" ]; then
  plutil -lint "$manifest" >/dev/null && ok "privacy manifest is valid" || bad "privacy manifest is not a valid plist"
  [ "$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyAccessedAPITypes' "$manifest" 2>/dev/null | grep -c NSPrivacyAccessedAPIType)" -gt 0 ] \
    && ok "privacy manifest declares required-reason APIs" || bad "privacy manifest declares no required-reason APIs"
else
  bad "PrivacyInfo.xcprivacy is not in the app bundle"
fi

if /usr/libexec/PlistBuddy -c 'Print :CFBundleIcons:CFBundlePrimaryIcon' "$plist" >/dev/null 2>&1 && [ -f "$app/Assets.car" ]; then
  ok "app icon compiled into Assets.car"
else
  bad "no compiled app icon (CFBundleIcons or Assets.car missing)"
fi

# The 1024 px App Store icon must be square and have no transparency.
icon=App/Assets.xcassets/AppIcon.appiconset/icon-ios-1024.png
w=$(sips -g pixelWidth "$icon" | awk '/pixelWidth/ {print $2}')
h=$(sips -g pixelHeight "$icon" | awk '/pixelHeight/ {print $2}')
alpha=$(sips -g hasAlpha "$icon" | awk '/hasAlpha/ {print $2}')
[ "$w" = 1024 ] && [ "$h" = 1024 ] && ok "App Store icon is 1024x1024" || bad "App Store icon is ${w}x${h}, needs 1024x1024"
[ "$alpha" = "no" ] && ok "App Store icon has no transparency" || bad "App Store icon has an alpha channel"

[ "$fail" = 0 ] && echo "== Preflight passed" || { echo "== Preflight failed"; exit 1; }
