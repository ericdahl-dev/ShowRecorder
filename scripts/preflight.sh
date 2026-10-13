#!/bin/sh
# Checks what App Store Connect rejects a build for, before any upload: icon, privacy manifest,
# export compliance, usage strings and version numbers.
#   scripts/preflight.sh                  builds an unsigned iOS Release app, then checks it
#   PLATFORM=macos scripts/preflight.sh   the same for the Mac app
#   scripts/preflight.sh Some.xcarchive   checks an archive (or a .app) you already have, iOS or Mac
# BUILD_NUMBER sets CURRENT_PROJECT_VERSION for the build, so no file is edited.
set -eu
cd "$(dirname "$0")/.."

fail=0
bad() { echo "FAIL: $1"; fail=1; }
ok() { echo "ok:   $1"; }

target="${1:-}"
if [ -z "$target" ]; then
  DD="${DERIVED_DATA:-build/dd-preflight}"
  if [ "${PLATFORM:-ios}" = macos ]; then
    destination='generic/platform=macOS'; products=Release
  else
    destination='generic/platform=iOS'; products=Release-iphoneos
  fi
  echo "== Building $destination Release (unsigned)"
  xcodebuild -quiet -project ShowRecorder.xcodeproj -scheme ShowRecorder -configuration Release \
    -destination "$destination" -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO \
    ${BUILD_NUMBER:+CURRENT_PROJECT_VERSION="$BUILD_NUMBER"} build
  target="$DD/Build/Products/$products/ShowRecorder.app"
fi
case "$target" in
  *.xcarchive) app=$(ls -d "$target"/Products/Applications/*.app | head -n 1) ;;
  *) app="$target" ;;
esac
[ -d "$app" ] || { echo "No app found at $target"; exit 2; }
echo "== Checking $app"

# A Mac app keeps its Info.plist and resources under Contents/.
if [ -f "$app/Contents/Info.plist" ]; then
  mac=1; plist="$app/Contents/Info.plist"; resources="$app/Contents/Resources"
else
  mac=0; plist="$app/Info.plist"; resources="$app"
fi
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

manifest="$resources/PrivacyInfo.xcprivacy"
if [ -f "$manifest" ]; then
  plutil -lint "$manifest" >/dev/null && ok "privacy manifest is valid" || bad "privacy manifest is not a valid plist"
  [ "$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyAccessedAPITypes' "$manifest" 2>/dev/null | grep -c NSPrivacyAccessedAPIType)" -gt 0 ] \
    && ok "privacy manifest declares required-reason APIs" || bad "privacy manifest declares no required-reason APIs"
else
  bad "PrivacyInfo.xcprivacy is not in the app bundle"
fi

if [ $mac = 1 ]; then
  if [ -n "$(read_key CFBundleIconName)" ] && [ -f "$resources/Assets.car" ]; then
    ok "Mac app icon compiled into Assets.car"
  else
    bad "no compiled Mac app icon (CFBundleIconName or Assets.car missing)"
  fi
  # The Mac App Store refuses an upload without a category or without the App Sandbox.
  [ -n "$(read_key LSApplicationCategoryType)" ] && ok "LSApplicationCategoryType = $(read_key LSApplicationCategoryType)" \
    || bad "LSApplicationCategoryType is missing (the Mac App Store needs it)"
  # An unsigned build is still ad hoc (linker) signed on Apple silicon, with no entitlements.
  if codesign -dvv "$app" 2>&1 | grep -q '^Authority='; then
    codesign -d --entitlements - --xml "$app" 2>/dev/null | grep -q 'com.apple.security.app-sandbox</key><true/>' \
      && ok "signed with the App Sandbox" || bad "signed without com.apple.security.app-sandbox"
  else
    echo "skip: App Sandbox check (the app is not signed)"
  fi
elif /usr/libexec/PlistBuddy -c 'Print :CFBundleIcons:CFBundlePrimaryIcon' "$plist" >/dev/null 2>&1 && [ -f "$app/Assets.car" ]; then
  ok "app icon compiled into Assets.car"
else
  bad "no compiled app icon (CFBundleIcons or Assets.car missing)"
fi

# The iPhone app embeds the Live Activity extension (#136): App Store Connect refuses an extension whose
# version or build number differs from the app's, or one without its extension point.
if [ $mac = 0 ]; then
  appex="$app/PlugIns/ShowRecorderLiveActivity.appex"
  if [ -d "$appex" ]; then
    read_appex() { /usr/libexec/PlistBuddy -c "Print :$1" "$appex/Info.plist" 2>/dev/null || true; }
    [ "$(read_appex CFBundleShortVersionString)" = "$version" ] && [ "$(read_appex CFBundleVersion)" = "$build" ] \
      && ok "Live Activity extension version matches the app" \
      || bad "Live Activity extension is $(read_appex CFBundleShortVersionString) ($(read_appex CFBundleVersion)), the app $version ($build)"
    [ "$(read_appex NSExtension:NSExtensionPointIdentifier)" = com.apple.widgetkit-extension ] \
      && ok "Live Activity extension is a WidgetKit extension" || bad "Live Activity extension has no WidgetKit extension point"
    [ "$(read_key NSSupportsLiveActivities)" = true ] && ok "NSSupportsLiveActivities = true" || bad "NSSupportsLiveActivities is missing from Info.plist"
  else
    bad "the Live Activity extension is not in the app (PlugIns/ShowRecorderLiveActivity.appex)"
  fi
elif [ -d "$app/Contents/PlugIns/ShowRecorderLiveActivity.appex" ]; then
  bad "the Mac app embeds the Live Activity extension (it's iPhone only)"
fi

# The iPhone app embeds the Apple Watch remote (#100): App Store Connect refuses a watch app whose version or build
# differs from the app's, or one that doesn't name the iPhone app as its companion.
if [ $mac = 0 ]; then
  watch="$app/Watch/ShowRecorderWatch.app"
  if [ -d "$watch" ]; then
    read_watch() { /usr/libexec/PlistBuddy -c "Print :$1" "$watch/Info.plist" 2>/dev/null || true; }
    [ "$(read_watch CFBundleShortVersionString)" = "$version" ] && [ "$(read_watch CFBundleVersion)" = "$build" ] \
      && ok "watch app version matches the app" \
      || bad "watch app is $(read_watch CFBundleShortVersionString) ($(read_watch CFBundleVersion)), the app $version ($build)"
    [ "$(read_watch WKCompanionAppBundleIdentifier)" = "$(read_key CFBundleIdentifier)" ] \
      && ok "watch app's companion is this app" || bad "watch app's WKCompanionAppBundleIdentifier isn't $(read_key CFBundleIdentifier)"
    [ "$(read_watch WKApplication)" = true ] && ok "watch app is a single-target watch app (WKApplication)" \
      || bad "watch app has no WKApplication = true"
  else
    bad "the watch app is not in the app (Watch/ShowRecorderWatch.app)"
  fi
elif [ -d "$app/Contents/Watch" ]; then
  bad "the Mac app embeds a watch app (it's iPhone only)"
fi

# The 1024 px App Store icon must be square and have no transparency.
icon=App/Assets.xcassets/AppIcon.appiconset/icon-ios-1024.png
w=$(sips -g pixelWidth "$icon" | awk '/pixelWidth/ {print $2}')
h=$(sips -g pixelHeight "$icon" | awk '/pixelHeight/ {print $2}')
alpha=$(sips -g hasAlpha "$icon" | awk '/hasAlpha/ {print $2}')
[ "$w" = 1024 ] && [ "$h" = 1024 ] && ok "App Store icon is 1024x1024" || bad "App Store icon is ${w}x${h}, needs 1024x1024"
[ "$alpha" = "no" ] && ok "App Store icon has no transparency" || bad "App Store icon has an alpha channel"

[ "$fail" = 0 ] && echo "== Preflight passed" || { echo "== Preflight failed"; exit 1; }
