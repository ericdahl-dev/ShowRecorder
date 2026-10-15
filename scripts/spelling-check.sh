#!/bin/sh
# The American spelling check CI runs (the org's "American spelling" workflow, ericdahl-dev/spelling-dialect@v1):
# the same spelling_dialect.py, kept for a day in the repo's git folder so verify.sh stays fast and works offline.
# With no copy and no network it says so and passes: CI still checks.
set -eu
cd "$(dirname "$0")/.."
cache="$(git rev-parse --git-common-dir)/spelling-dialect-v1.py"
if [ ! -s "$cache" ] || [ -n "$(find "$cache" -mtime +0 2>/dev/null)" ]; then
  if gh api -H "Accept: application/vnd.github.raw" "repos/ericdahl-dev/spelling-dialect/contents/spelling_dialect.py?ref=v1" > "$cache.new" 2>/dev/null \
     && [ -s "$cache.new" ]; then
    mv "$cache.new" "$cache"
  else
    rm -f "$cache.new"
    [ -s "$cache" ] || { echo "== Spelling: couldn't fetch spelling_dialect.py (offline?); skipped, CI still checks"; exit 0; }
  fi
fi
python3 "$cache" .
