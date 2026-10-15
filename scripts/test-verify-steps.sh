#!/bin/sh
# Checks how verify.sh runs its steps side by side (scripts/verify-steps.sh), with stand-in steps instead of real
# builds: every step runs, a failing step's log is printed and fails the run, a passing step's log is not, and each
# step's duration is printed.
set -eu
cd "$(dirname "$0")/.."

fail=0
check() {
  if ! printf '%s\n' "$out" | grep -q -- "$1"; then
    printf 'FAIL: %s\n  output was:\n%s\n' "$2" "$out"
    fail=1
  fi
}
check_not() {
  if printf '%s\n' "$out" | grep -q -- "$1"; then
    printf 'FAIL: %s\n  output was:\n%s\n' "$2" "$out"
    fail=1
  fi
}

# Two steps, one failing: the run fails, but only after both ran.
status=0
out=$(sh -c '
  . ./scripts/verify-steps.sh
  steps_start
  run_step "Good step" sh -c "echo good-output; sleep 1"
  run_step "Bad step" sh -c "echo bad-output; exit 3"
  steps_finish
' 2>&1) || status=$?
[ "$status" -ne 0 ] || { echo "FAIL: a failing step must fail the run"; fail=1; }
check "bad-output" "a failing step's log is printed"
check_not "good-output" "a passing step's log is not printed"
check "Good step: passed in [0-9]*s" "a passing step reports its duration"
check "Bad step: FAILED (exit 3) in [0-9]*s" "a failing step reports its exit code and duration"

# Side by side: two 3-second steps take about 3 seconds, not 6.
started=$(date +%s)
out=$(sh -c '
  . ./scripts/verify-steps.sh
  steps_start
  run_step "A" sleep 3
  run_step "B" sleep 3
  steps_finish
' 2>&1) || { echo "FAIL: passing steps must pass the run"; fail=1; }
elapsed=$(( $(date +%s) - started ))
[ "$elapsed" -lt 6 ] || { echo "FAIL: steps ran one after another (${elapsed}s)"; fail=1; }
check "A: passed" "every passing step is reported"
check "B: passed" "every passing step is reported"

# Stopping the run (Ctrl-C, or TERM) stops the steps it started and everything they started, even a command behind
# a wrapper shell (as the package and website steps run). Only TERM can be checked here: a run started in the
# background, as this one is, ignores Ctrl-C from the start, and a shell can't trap a signal it began ignoring.
for signal in TERM; do
  direct="47.$$1"
  wrapped="47.$$2"
  sh -c "
    . ./scripts/verify-steps.sh
    steps_start
    run_step Direct sleep $direct
    run_step Wrapped sh -c 'cd . && sleep $wrapped'
    steps_finish
  " > /dev/null 2>&1 &
  runner=$!
  sleep 1
  kill -"$signal" "$runner"
  status=0
  wait "$runner" || status=$?
  want=143
  [ "$status" -eq "$want" ] || { echo "FAIL: a run stopped with $signal exits $want, got $status"; fail=1; }
  for left in "$direct" "$wrapped"; do
    if pgrep -f "sleep $left" > /dev/null; then
      echo "FAIL: a run stopped with $signal left 'sleep $left' running"
      pkill -f "sleep $left"
      fail=1
    fi
  done
done

[ $fail -eq 0 ] && echo "verify.sh steps: all cases pass"
exit $fail
