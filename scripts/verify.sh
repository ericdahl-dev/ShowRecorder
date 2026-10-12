#!/bin/sh
# Runs the checks CI runs, but only the ones the changed files need:
#   vocab    scripts/vocab-check.sh      App/, package Sources/, CONTEXT.md, scripts/vocab-*
#   package  swift test                  Packages/
#   app      macOS and iOS Simulator     App/, Packages/, project.yml, ShowRecorder.xcodeproj/
#   site     website lint, tests, build  website/
# Docs, design notes and other Markdown need none. A change to verify.sh, CI or any path not listed
# here runs everything, and so does a branch with no changes (a plain "is main green?" check).
#
# Changed files are those since the branch left origin/main, plus uncommitted and untracked ones.
#   VERIFY_ALL=1        run every check
#   VERIFY_BASE=<ref>   compare against another ref instead of origin/main
#   VERIFY_FILES=...    use this newline-separated list instead of git (scripts/test-verify-plan.sh)
#   VERIFY_PLAN_ONLY=1  print the plan and stop
#   DERIVED_DATA=<dir>  Xcode build folder (default build/dd)
# With DEVICE_ID set (an iOS device id from `xcodebuild -showdestinations`) and DEVELOPMENT_TEAM,
# the app step also builds a signed app for that device.
set -eu
cd "$(dirname "$0")/.."
DD="${DERIVED_DATA:-build/dd}"

changed_files() {
  if [ -n "${VERIFY_FILES+x}" ]; then
    printf '%s\n' "$VERIFY_FILES"
    return
  fi
  base=$(git merge-base HEAD "${VERIFY_BASE:-origin/main}" 2>/dev/null) || { echo "*no-base*"; return; }
  git diff --name-only "$base"
  git ls-files --others --exclude-standard
}

vocab=0 package=0 app=0 site=0
all() { vocab=1 package=1 app=1 site=1; }

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
      docs/* | design/* | *.md) ;;
      *) all ;;
    esac
  done
  IFS=$old_ifs
fi

plan=""
[ $vocab = 1 ] && plan="$plan vocab"
[ $package = 1 ] && plan="$plan package"
[ $app = 1 ] && plan="$plan app"
[ $site = 1 ] && plan="$plan site"
plan=${plan# }
echo "== Plan: ${plan:-none}"
[ "${VERIFY_PLAN_ONLY:-0}" = 1 ] && exit 0
if [ -z "$plan" ]; then
  echo "== Nothing to check for these changes (VERIFY_ALL=1 runs everything)"
  exit 0
fi

if [ "$plan" = "vocab package app site" ]; then
  echo "== verify.sh plan"
  ./scripts/test-verify-plan.sh
fi

if [ $vocab = 1 ]; then
  echo "== Vocabulary (CONTEXT.md)"
  ./scripts/vocab-check.sh
fi

if [ $package = 1 ]; then
  echo "== Package tests"
  (cd Packages/ShowRecorderKit && swift test)
fi

if [ $app = 1 ]; then
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
fi

if [ $site = 1 ]; then
  echo "== Website lint, tests and build"
  (cd website && corepack enable >/dev/null 2>&1 || true; yarn install --immutable && yarn lint && yarn test:run && yarn build)
fi

echo "== All checks passed ($plan)"
