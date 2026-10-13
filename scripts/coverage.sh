#!/usr/bin/env bash
# Kit code coverage (#576): merges what every test bundle recorded and prints a Markdown table, per module and the
# files with the least. Run after `swift test --enable-code-coverage` in Packages/ShowRecorderKit (a clean build, so no
# earlier run's profiles count). Report only: no floor, nothing fails on a low number, nothing is uploaded.
# `swift test --show-codecov-path` covers only the last bundle, so this merges all of them.
set -euo pipefail
scripts=$(cd "$(dirname "$0")" && pwd)
cd "$scripts/../Packages/ShowRecorderKit"

products=.build/out/Products/Debug
[ -d "$products" ] || products=.build/debug   # an older SwiftPM's layout
profiles=$(find "$products" -path '*/codecov/*.profraw' 2>/dev/null)
if [ -z "$profiles" ]; then
  echo "No coverage profiles in $products/codecov: run swift test --enable-code-coverage first." >&2
  exit 1
fi
merged=$(mktemp -t showrecorder-coverage).profdata
trap 'rm -f "$merged"' EXIT
# Profile names have spaces ("Swift Testing…profraw"): one per line into llvm-profdata.
printf '%s\n' "$profiles" | xcrun llvm-profdata merge -sparse -f /dev/stdin -o "$merged"

# Every test bundle's binary: the first is positional, the rest `-object`.
binaries=()
for bundle in "$products"/*.xctest; do
  binaries+=("$bundle/Contents/MacOS/$(basename "$bundle" .xctest)")
done
args=("${binaries[0]}")
for binary in "${binaries[@]:1}"; do args+=(-object "$binary"); done

xcrun llvm-cov export -summary-only -instr-profile="$merged" -ignore-filename-regex='(\.build|/Tests/)' "${args[@]}" \
  | python3 -B "$scripts/coverage_table.py"
