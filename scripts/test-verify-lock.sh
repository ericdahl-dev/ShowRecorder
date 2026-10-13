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

# A verify.sh that holds the lock past its time limit (#578) is stopped, says why, and frees the lock.
# SHOWRECORDER_VERIFY_TIMEOUT is minutes; 0.05 is 3 s. This test gives up waiting after 20 s itself.
hang=$((600 + $$ % 1000))  # a length only this run uses, matched exactly, so runs at once never stop each other's
VERIFY_LOCK_PROBE="echo hung >> $dir/hung; sleep $hang" SHOWRECORDER_VERIFY_TIMEOUT=0.05 ./scripts/verify.sh > "$dir/hung.out" 2>&1 &
hung=$!
i=0
while kill -0 "$hung" 2>/dev/null && [ $i -lt 200 ]; do i=$((i + 1)); sleep 0.1; done
if kill -0 "$hung" 2>/dev/null; then
  echo "FAIL: a verify.sh past its time limit wasn't stopped"; fail=1
  pkill -f "^sleep $hang\$" 2>/dev/null || true
fi
wait "$hung" 2>/dev/null || true
grep -q "held the build lock for more than" "$dir/hung.out" || { echo "FAIL: the stopped verify.sh didn't say why"; fail=1; }
lockf -k -t 0 "$SHOWRECORDER_BUILD_LOCK" true || { echo "FAIL: the lock wasn't freed"; fail=1; }

[ $fail = 0 ] && echo "verify.sh lock: all cases pass"
exit $fail
