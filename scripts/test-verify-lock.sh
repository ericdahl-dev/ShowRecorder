#!/bin/sh
# Checks that only one verify.sh runs at a time: a second one waits its turn, saying so, and a plan-only run doesn't
# queue. Uses its own lock file and a stub step (VERIFY_LOCK_PROBE), so it runs nothing else and never waits on a real run.
set -eu
cd "$(dirname "$0")/.."
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
export SHOWRECORDER_BUILD_LOCK="$dir/verify.lock"
unset SHOWRECORDER_BUILD_LOCK_HELD || true

fail=0
# Waits until FILE has PATTERN (up to 60 s): a run has started its step, so it holds the lock. A fixed sleep isn't
# enough on a busy Mac.
wait_for() {
  i=0
  until grep -q -- "$2" "$1" 2>/dev/null; do
    i=$((i + 1)); [ $i -lt 600 ] || { echo "FAIL: gave up waiting for $2"; fail=1; return; }
    sleep 0.1
  done
}
VERIFY_LOCK_PROBE="echo A-start >> $dir/log; sleep 2; echo A-end >> $dir/log" ./scripts/verify.sh > "$dir/a.out" 2>&1 &
first=$!
wait_for "$dir/log" A-start
VERIFY_LOCK_PROBE="echo B-start >> $dir/log" ./scripts/verify.sh > "$dir/b.out" 2>&1
wait $first
order=$(tr '\n' ' ' < "$dir/log")
[ "$order" = "A-start A-end B-start " ] || { echo "FAIL: the second run didn't wait: $order"; fail=1; }
grep -q "Waiting for another build" "$dir/b.out" || { echo "FAIL: the second run didn't say it was waiting"; fail=1; }
grep -q "Waiting" "$dir/a.out" && { echo "FAIL: the first run said it was waiting"; fail=1; }

# A plan-only run doesn't queue behind a running one.
VERIFY_LOCK_PROBE="echo held >> $dir/held; sleep 8" ./scripts/verify.sh > /dev/null 2>&1 &
holder=$!
wait_for "$dir/held" held
start=$(date +%s)
VERIFY_PLAN_ONLY=1 VERIFY_FILES="README.md" VERIFY_ALL=0 ./scripts/verify.sh > /dev/null
[ $(( $(date +%s) - start )) -lt 6 ] || { echo "FAIL: a plan-only run waited for the lock"; fail=1; }
wait $holder

[ $fail = 0 ] && echo "verify.sh lock: all cases pass"
exit $fail
