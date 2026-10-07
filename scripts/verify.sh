#!/bin/sh
# Runs what CI runs, locally: package tests, then app builds for macOS and the iOS Simulator.
# With DEVICE_ID set (an iOS device id from `xcodebuild -showdestinations`) and DEVELOPMENT_TEAM,
# also builds a signed app for that device.
set -eu
cd "$(dirname "$0")/.."
DD="${DERIVED_DATA:-build/dd}"

echo "== Package tests"
(cd Packages/ShowRecorderKit && swift test)

echo "== macOS build"
xcodebuild -quiet -project ShowRecorder.xcodeproj -scheme ShowRecorder -destination 'platform=macOS' \
  -derivedDataPath "$DD" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build

echo "== iOS Simulator build"
xcodebuild -quiet -project ShowRecorder.xcodeproj -scheme ShowRecorder -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO build

if [ -n "${DEVICE_ID:-}" ]; then
  echo "== Signed device build for $DEVICE_ID"
  xcodebuild -quiet -project ShowRecorder.xcodeproj -scheme ShowRecorder -destination "platform=iOS,id=$DEVICE_ID" \
    -derivedDataPath "$DD-device" -allowProvisioningUpdates DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:?set DEVELOPMENT_TEAM}" build
fi

echo "== All checks passed"
