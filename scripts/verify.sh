#!/bin/sh
# Runs the checks CI runs, but only the ones the changed files need:
#   spelling scripts/spelling-check.sh   every plan: CI's American spelling check, on the whole repo
#   vocab    scripts/vocab-check.sh      App/, package Sources/, CONTEXT.md, scripts/vocab-*
#   package  swift test                  Packages/
#   app      macOS and iOS Simulator     App/, Packages/, project.yml, ShowRecorder.xcodeproj/
#   site     website lint, tests, build  website/, docs/release-notes/
# The package tests, the two app builds and the website run side by side, each into its own log; when all have
# finished each one's result and time is printed, with the log of any that failed (scripts/verify-steps.sh).
# Docs, design notes and other Markdown need none. A change to verify.sh, CI or any path not listed
# here runs everything, and so does a branch with no changes (a plain "is main green?" check).
#
# Changed files are those since the branch left origin/main, plus uncommitted and untracked ones.
#   VERIFY_ALL=1        run every check
#   VERIFY_BASE=<ref>   compare against another ref instead of origin/main
#   VERIFY_FILES=...    use this newline-separated list instead of git (scripts/test-verify-plan.sh)
#   VERIFY_PLAN_ONLY=1  print the plan and stop
#   VERIFY_QUICK=1      skip the macOS and iOS app builds (CI runs them): spelling, vocabulary, package tests and the
#                       site, as the changes need
#   DERIVED_DATA=<dir>  Xcode build folders' prefix (default build/dd: build/dd-mac, build/dd-ios, build/dd-device)
#
# One heavy build at a time on this Mac (scripts/build-lock.sh): a second verify.sh, or a swift build/test or
# xcodebuild through scripts/bin, waits for the first to finish, and says so. verify.sh runs at low priority with
# SHOWRECORDER_BUILD_LOCK_HELD=1, so its own side-by-side builds don't wait for it. A queued run can take longer than
# an agent's 10-minute command limit: run it as a background task. VERIFY_PLAN_ONLY=1 never waits. Builds are capped
# at SHOWRECORDER_BUILD_JOBS compile jobs (default: cores less 4), split between the builds that run at once.
# A run that holds the lock longer than SHOWRECORDER_VERIFY_TIMEOUT minutes (default 45) is stopped, its whole process
# group, and the lock freed for the next build (#578); its own builds share that limit.
#   VERIFY_LOCK_PROBE=<sh>  once the lock is held, run this instead of the checks (scripts/test-verify-lock.sh)
# With DEVICE_ID set (an iOS device id from `xcodebuild -showdestinations`) and DEVELOPMENT_TEAM,
# the app step also builds a signed app for that device.
set -eu
cd "$(dirname "$0")/.."
if [ "${VERIFY_PLAN_ONLY:-0}" != 1 ] && [ "${SHOWRECORDER_BUILD_LOCK_HELD:-0}" != 1 ]; then
  . ./scripts/build-lock.sh
  # A whole run may hold the lock for SHOWRECORDER_VERIFY_TIMEOUT minutes (default 45: a full run takes about 4 here,
  # and the wait for the lock doesn't count); past that it's stopped and the lock freed (#578).
  export SHOWRECORDER_BUILD_TIMEOUT="${SHOWRECORDER_VERIFY_TIMEOUT:-45}"
  build_lock_exec ./scripts/verify.sh
fi
if [ -n "${VERIFY_LOCK_PROBE:-}" ]; then
  sh -c "$VERIFY_LOCK_PROBE"
  exit
fi
. ./scripts/verify-steps.sh
DD="${DERIVED_DATA:-build/dd}"
started=$(date +%s)

changed_files() {
  if [ -n "${VERIFY_FILES+x}" ]; then
    printf '%s\n' "$VERIFY_FILES"
    return
  fi
  base=$(git merge-base HEAD "${VERIFY_BASE:-origin/main}" 2>/dev/null) || { echo "*no-base*"; return; }
  git diff --name-only "$base"
  git ls-files --others --exclude-standard
}

vocab=0 package=0 app=0 site=0 everything=0
all() { vocab=1 package=1 app=1 site=1 everything=1; }

files=$(changed_files | sed '/^$/d' | sort -u)
if [ "${VERIFY_ALL:-0}" = 1 ] || [ -z "$files" ]; then
  all
else
  # One path per line, so a path with a space stays whole.
  old_ifs=$IFS
  IFS='
'
  for f in $files; do
    case "$f" in
      App/*) vocab=1 app=1 ;;
      Packages/*/Sources/*) vocab=1 package=1 app=1 ;;
      Packages/*) package=1 app=1 ;;
      project.yml | ShowRecorder.xcodeproj/*) app=1 ;;
      CONTEXT.md | scripts/vocab-*) vocab=1 ;;
      website/*) site=1 ;;
      # The site's changelog test reads the release notes.
      docs/release-notes/*) site=1 ;;
      docs/* | design/* | *.md) ;;
      *) all ;;
    esac
  done
  IFS=$old_ifs
fi

# Quick mode leaves the two app builds, the slowest step, to CI.
skipped_app=0
if [ "${VERIFY_QUICK:-0}" = 1 ] && [ $app = 1 ]; then
  app=0 skipped_app=1
fi

plan="spelling"
[ $vocab = 1 ] && plan="$plan vocab"
[ $package = 1 ] && plan="$plan package"
[ $app = 1 ] && plan="$plan app"
[ $site = 1 ] && plan="$plan site"
echo "== Plan: $plan"
if [ $skipped_app = 1 ]; then
  echo "== Quick: CI runs the macOS and iOS app builds"
  [ -n "${DEVICE_ID:-}" ] && echo "== Quick: the signed device build for $DEVICE_ID is skipped too, and CI doesn't run it"
fi
[ "${VERIFY_PLAN_ONLY:-0}" = 1 ] && exit 0

if [ $everything = 1 ]; then
  echo "== verify.sh plan, steps and build lock"
  ./scripts/test-verify-plan.sh
  ./scripts/test-verify-steps.sh
  ./scripts/test-verify-lock.sh
  ./scripts/test-build-lock.sh
  python3 scripts/test_testflight.py
fi

echo "== American spelling (CI's check)"
./scripts/spelling-check.sh

if [ $vocab = 1 ]; then
  echo "== Vocabulary (CONTEXT.md)"
  ./scripts/vocab-check.sh
fi

# A signed device build needs a team; say so now rather than after the other steps.
[ $app = 1 ] && [ -n "${DEVICE_ID:-}" ] && : "${DEVELOPMENT_TEAM:?set DEVELOPMENT_TEAM}"

# The builds go through the shims (scripts/bin), so each is capped at its share of the compile jobs even when
# scripts/bin isn't on PATH: the package tests and the app builds run at once, so they split SHOWRECORDER_BUILD_JOBS
# (by default this Mac's cores less 4) between them.
. ./scripts/build-lock.sh
swift="$(pwd)/scripts/bin/swift"
xcodebuild="$(pwd)/scripts/bin/xcodebuild"
heavy=$((package + app * 2))
[ $app = 1 ] && [ -n "${DEVICE_ID:-}" ] && heavy=$((heavy + 1))
if [ $heavy -gt 1 ]; then
  share=$(( $(build_jobs) / heavy ))
  [ $share -ge 1 ] || share=1
  export SHOWRECORDER_BUILD_JOBS=$share
fi

# Each xcodebuild has its own build folder, so they don't wait on each other's locks.
steps_start
[ $package = 1 ] && run_step "Package tests" sh -c 'cd Packages/ShowRecorderKit && "$1" test --parallel' sh "$swift"
if [ $app = 1 ]; then
  run_step "macOS build" "$xcodebuild" -quiet -project ShowRecorder.xcodeproj -scheme ShowRecorder -destination 'platform=macOS' \
    -derivedDataPath "$DD-mac" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
  run_step "iOS Simulator build" "$xcodebuild" -quiet -project ShowRecorder.xcodeproj -scheme ShowRecorder \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DD-ios" CODE_SIGNING_ALLOWED=NO build
  if [ -n "${DEVICE_ID:-}" ]; then
    run_step "Signed device build for $DEVICE_ID" "$xcodebuild" -quiet -project ShowRecorder.xcodeproj -scheme ShowRecorder \
      -destination "platform=iOS,id=$DEVICE_ID" -derivedDataPath "$DD-device" -allowProvisioningUpdates \
      DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" build
  fi
fi
[ $site = 1 ] && run_step "Website lint, tests and build" sh -c \
  'cd website && { corepack enable >/dev/null 2>&1 || true; } && yarn install --immutable && yarn lint && yarn test:run && yarn build'
if ! steps_finish; then
  echo "== Failed after $(( $(date +%s) - started ))s ($plan)"
  exit 1
fi

quick=""
[ $skipped_app = 1 ] && quick="; quick: app builds left to CI"
echo "== All checks passed in $(( $(date +%s) - started ))s ($plan$quick)"
