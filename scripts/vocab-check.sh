#!/bin/bash
# Fails when a string the app shows uses a word CONTEXT.md says to avoid (#248).
# It reads string literals in App/ and the package sources, skipping comments, log lines and keys.
set -u
cd "$(dirname "$0")/.."

AVOIDED=$(grep -v '^#' scripts/vocab-avoid.txt)

strings() {
  rg -n --no-heading -o '"[^"\n]*"' App Packages/ShowRecorderKit/Sources -g '*.swift' \
    | rg -v '^\S+:\d+:\s*$' \
    | while IFS= read -r hit; do
        file=${hit%%:*}; rest=${hit#*:}; line=${rest%%:*}
        text=$(sed -n "${line}p" "$file")
        # Comments, logs and keys are not shown to the operator.
        [[ $text =~ ^[[:space:]]*// ]] && continue
        [[ $text =~ (Log|log|Logger|\.notice|\.debug|\.error\(|forKey|launchFlag|systemName|AppStorage|identifier) ]] && continue
        echo "$hit"
      done
}

found=0
all=$(strings)
while IFS= read -r entry; do
  [ -z "$entry" ] && continue
  pattern=${entry%% => *}; instead=${entry#* => }
  # Each hit is "file:line<tab>string"; a pattern anchored with ^ starts at the string.
  if [ "${pattern:0:1}" = "^" ]; then search="\t${pattern:1}"; else search="\t.*$pattern"; fi
  matches=$(printf '%s\n' "$all" | awk -F: '{ s = $0; sub(/^[^:]*:[^:]*:/, "", s); print $1 ":" $2 "\t" s }' | rg -P "$search" || true)
  if [ -n "$matches" ]; then
    echo "Avoid /$pattern/ — use $instead:"
    printf '%s\n' "$matches" | sed 's/^/  /'
    found=1
  fi
done <<< "$AVOIDED"

if [ $found -ne 0 ]; then
  echo "Vocabulary check failed: see CONTEXT.md."
  exit 1
fi
echo "Vocabulary check passed."
