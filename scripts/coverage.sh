#!/usr/bin/env bash
# Kit code coverage (#576): merges what every test bundle recorded and prints a Markdown table, per module and the
# files with the least. Run after `swift test --enable-code-coverage` in Packages/ShowRecorderKit (a clean build, so no
# earlier run's profiles count). Report only: no floor, nothing fails on a low number, nothing is uploaded.
# With COVERAGE_JSON=<path>, also writes llvm-cov's per-file summary there (CI keeps it as the run's coverage artifact).
# `swift test --show-codecov-path` covers only the last bundle, so this takes only the folder from it and merges every
# profile there. Toolchains differ (#576): one bundle beside that folder on CI's Xcode, one per test target locally.
set -euo pipefail
scripts=$(cd "$(dirname "$0")" && pwd)
cd "$scripts/../Packages/ShowRecorderKit"

json=$(swift test --show-codecov-path)
profiles=$(python3 -B "$scripts/coverage_table.py" --profiles "$json")
if [ -z "$profiles" ]; then
  echo "No coverage profiles in $(dirname "$json"): run swift test --enable-code-coverage first." >&2
  exit 1
fi
merged=$(mktemp -t showrecorder-coverage).profdata
trap 'rm -f "$merged"' EXIT
# Profile names have spaces ("Swift Testing…profraw"): one per line into llvm-profdata.
printf '%s\n' "$profiles" | xcrun llvm-profdata merge -sparse -f /dev/stdin -o "$merged"

# Every test bundle's binary: the first is positional, the rest `-object`.
binaries=()
while IFS= read -r binary; do binaries+=("$binary"); done <<EOF
$(python3 -B "$scripts/coverage_table.py" --binaries "$json")
EOF
args=("${binaries[0]}")
for binary in "${binaries[@]:1}"; do args+=(-object "$binary"); done

xcrun llvm-cov export -summary-only -instr-profile="$merged" -ignore-filename-regex='(\.build|/Tests/)' "${args[@]}" \
  | tee "${COVERAGE_JSON:-/dev/null}" | python3 -B "$scripts/coverage_table.py"
# With COVERAGE_LCOV=<path>, also the line-by-line lcov file (CI uploads it to Codecov).
if [ -n "${COVERAGE_LCOV:-}" ]; then
  xcrun llvm-cov export -format=lcov -instr-profile="$merged" -ignore-filename-regex='(\.build|/Tests/)' "${args[@]}" \
    > "$COVERAGE_LCOV"
fi
