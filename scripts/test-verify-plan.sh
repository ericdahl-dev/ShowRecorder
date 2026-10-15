#!/bin/sh
# Checks which steps verify.sh picks for a set of changed files, without running any of them.
set -eu
cd "$(dirname "$0")/.."

fail=0
expect() {
  files=$1; want=$2
  got=$(VERIFY_QUICK=0 VERIFY_ALL=0 VERIFY_FILES="$files" VERIFY_PLAN_ONLY=1 ./scripts/verify.sh | sed -n 's/^== Plan: //p')
  if [ "$got" != "$want" ]; then
    printf 'FAIL for files:\n%s\n  want: %s\n  got:  %s\n' "$files" "$want" "$got"
    fail=1
  fi
}

ALL="spelling vocab package app site"
expect "website/app/page.tsx" "spelling site"
expect "docs/app-store/listing.md" "spelling"
expect "README.md
design/notes.md
LICENSE.md" "spelling"
expect "App/RecordView.swift" "spelling vocab app"
expect "project.yml" "spelling app"
expect "ShowRecorder.xcodeproj/project.pbxproj" "spelling app"
expect "AppTests/MeterGridTests.swift" "spelling app"
expect "Packages/ShowRecorderKit/Sources/Kit/Take.swift" "spelling vocab package app"
expect "Packages/ShowRecorderKit/Package.swift" "spelling package app"
expect "scripts/vocab-avoid.txt" "spelling vocab"
expect "CONTEXT.md" "spelling vocab"
expect "App/RecordView.swift
website/lib/site.ts" "spelling vocab app site"
expect "scripts/verify.sh" "$ALL"
expect ".github/workflows/ci.yml" "$ALL"
expect "something/new.txt" "$ALL"
# The site's changelog test reads the release notes, so they pick the site check (#466 turned main red).
expect "docs/release-notes/v1.1.2.md" "spelling site"
# Nothing changed: run everything, as a plain "is main green?" check.
expect "" "$ALL"

# VERIFY_QUICK=1 leaves the macOS and iOS app builds to CI: everything else as usual, and it says so only when it
# skipped them.
expect_quick() {
  files=$1; want=$2; says=$3
  out=$(VERIFY_QUICK=1 VERIFY_ALL=0 VERIFY_FILES="$files" VERIFY_PLAN_ONLY=1 ./scripts/verify.sh)
  got=$(printf '%s\n' "$out" | sed -n 's/^== Plan: //p')
  if [ "$got" != "$want" ]; then
    printf 'FAIL (quick) for files:\n%s\n  want: %s\n  got:  %s\n' "$files" "$want" "$got"
    fail=1
  fi
  if printf '%s\n' "$out" | grep -q "CI runs the macOS and iOS app builds"; then said=yes; else said=no; fi
  [ "$said" = "$says" ] || { echo "FAIL (quick): says CI runs the app builds: $said, want $says, for: $files"; fail=1; }
}
expect_quick "App/RecordView.swift" "spelling vocab" yes
expect_quick "project.yml" "spelling" yes
expect_quick "ShowRecorder.xcodeproj/project.pbxproj" "spelling" yes
expect_quick "Packages/ShowRecorderKit/Sources/Kit/Take.swift" "spelling vocab package" yes
expect_quick "website/app/page.tsx" "spelling site" no
expect_quick "docs/notes.md" "spelling" no
expect_quick "scripts/verify.sh" "spelling vocab package site" yes
expect_quick "" "spelling vocab package site" yes
# With a device to build for, quick says that build is skipped too: CI doesn't run it.
out=$(DEVICE_ID=abc VERIFY_QUICK=1 VERIFY_ALL=0 VERIFY_FILES="App/RecordView.swift" VERIFY_PLAN_ONLY=1 ./scripts/verify.sh)
printf '%s\n' "$out" | grep -q "signed device build for abc is skipped" ||
  { echo "FAIL (quick): doesn't say the device build is skipped: $out"; fail=1; }

# CI picks its site job with its own pattern (.github/workflows/ci.yml); it must agree for the release notes.
site_pattern=$(grep "site=true; fi" .github/workflows/ci.yml | sed -n "s/.*grep -qE '\([^']*\)'.*/\1/p")
if [ "$(grep -c "site=true; fi" .github/workflows/ci.yml)" != 1 ] || [ -z "$site_pattern" ]; then
  echo "FAIL: expected exactly one site pattern line in .github/workflows/ci.yml"
  fail=1
else
  for f in website/app/page.tsx docs/release-notes/v1.1.2.md .github/workflows/ci.yml; do
    printf '%s\n' "$f" | grep -qE "$site_pattern" || { echo "FAIL: CI doesn't run the site job for $f"; fail=1; }
  done
  for f in docs/adr/0001-x.md App/RecordView.swift; do
    printf '%s\n' "$f" | grep -qE "$site_pattern" && { echo "FAIL: CI runs the site job for $f"; fail=1; }
  done
fi

[ $fail -eq 0 ] && echo "verify.sh plan: all cases pass"
exit $fail
