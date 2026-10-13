#!/bin/sh
# Checks that only one verify.sh runs at a time: a second one waits its turn, saying so, and a plan-only run doesn't
# queue. Uses its own lock file and a stub step (VERIFY_LOCK_PROBE), so it runs nothing else and never waits on a real run.
set -eu
cd "$(dirname "$0")/.."
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
export VERIFY_LOCK_FILE="$dir/verify.lock"
unset VERIFY_LOCKED || true

fail=0
VERIFY_LOCK_PROBE="echo A-start >> $dir/log; sleep 2; echo A-end >> $dir/log" ./scripts/verify.sh > "$dir/a.out" 2>&1 &
first=$!
sleep 0.5
VERIFY_LOCK_PROBE="echo B-start >> $dir/log" ./scripts/verify.sh > "$dir/b.out" 2>&1
wait $first
order=$(tr '\n' ' ' < "$dir/log")
[ "$order" = "A-start A-end B-start " ] || { echo "FAIL: the second run didn't wait: $order"; fail=1; }
grep -q "Waiting for another verify.sh" "$dir/b.out" || { echo "FAIL: the second run didn't say it was waiting"; fail=1; }
grep -q "Waiting" "$dir/a.out" && { echo "FAIL: the first run said it was waiting"; fail=1; }

# A plan-only run doesn't queue behind a running one.
VERIFY_LOCK_PROBE="sleep 3" ./scripts/verify.sh > /dev/null 2>&1 &
holder=$!
sleep 0.5
start=$(date +%s)
VERIFY_PLAN_ONLY=1 VERIFY_FILES="README.md" VERIFY_ALL=0 ./scripts/verify.sh > /dev/null
[ $(( $(date +%s) - start )) -lt 2 ] || { echo "FAIL: a plan-only run waited for the lock"; fail=1; }
wait $holder

[ $fail = 0 ] && echo "verify.sh lock: all cases pass"
exit $fail
