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
# Nothing changed: run everything, as a plain "is main green?" check.
expect "" "$ALL"

[ $fail -eq 0 ] && echo "verify.sh plan: all cases pass"
exit $fail
