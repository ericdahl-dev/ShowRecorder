#!/bin/sh
# Checks which steps verify.sh picks for a set of changed files, without running any of them.
set -eu
cd "$(dirname "$0")/.."

fail=0
expect() {
  files=$1; want=$2
  got=$(VERIFY_ALL=0 VERIFY_FILES="$files" VERIFY_PLAN_ONLY=1 ./scripts/verify.sh | sed -n 's/^== Plan: //p')
  if [ "$got" != "$want" ]; then
    printf 'FAIL for files:\n%s\n  want: %s\n  got:  %s\n' "$files" "$want" "$got"
    fail=1
  fi
}

ALL="vocab package app site"
expect "website/app/page.tsx" "site"
expect "docs/app-store/listing.md" "none"
expect "README.md
design/notes.md
LICENSE.md" "none"
expect "App/RecordView.swift" "vocab app"
expect "project.yml" "app"
expect "ShowRecorder.xcodeproj/project.pbxproj" "app"
expect "Packages/ShowRecorderKit/Sources/Kit/Take.swift" "vocab package app"
expect "Packages/ShowRecorderKit/Package.swift" "package app"
expect "scripts/vocab-avoid.txt" "vocab"
expect "CONTEXT.md" "vocab"
expect "App/RecordView.swift
website/lib/site.ts" "vocab app site"
expect "scripts/verify.sh" "$ALL"
expect ".github/workflows/ci.yml" "$ALL"
expect "something/new.txt" "$ALL"
# The site's changelog test reads the release notes, so they pick the site check (#466 turned main red).
expect "docs/release-notes/v1.1.2.md" "site"
# Nothing changed: run everything, as a plain "is main green?" check.
expect "" "$ALL"

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
