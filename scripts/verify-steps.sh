# Runs verify.sh's slow steps side by side (sourced, POSIX sh). Each step writes to its own log; when all have
# finished, each one's result and duration is printed, and only a failing step's log, so outputs never interleave.
#   steps_start                  begin a set of steps
#   run_step "Name" command...   start one in the background
#   steps_finish                 wait for all; non-zero if any failed
# Ctrl-C stops every step it started, and only those.

steps_start() {
  STEPS_DIR=$(mktemp -d "${TMPDIR:-/tmp}/verify.XXXXXX")
  STEPS_COUNT=0
  STEPS_PIDS=""
  # A script's background steps ignore Ctrl-C, so stop them here.
  trap 'trap - INT TERM; [ -n "$STEPS_PIDS" ] && kill -TERM $STEPS_PIDS 2>/dev/null; wait; rm -rf "$STEPS_DIR"; exit 130' INT TERM
}

run_step() {
  STEPS_COUNT=$((STEPS_COUNT + 1))
  step_file="$STEPS_DIR/$STEPS_COUNT"
  printf '%s\n' "$1" > "$step_file.name"
  shift
  echo "== Started: $(cat "$step_file.name")"
  (
    child=""
    trap '[ -n "$child" ] && kill -TERM "$child" 2>/dev/null' TERM
    started=$(date +%s)
    "$@" > "$step_file.log" 2>&1 &
    child=$!
    if wait "$child"; then rc=0; else rc=$?; fi
    echo "$rc $(( $(date +%s) - started ))" > "$step_file.status"
  ) &
  STEPS_PIDS="$STEPS_PIDS $!"
}

steps_finish() {
  wait
  steps_failed=0
  step=1
  while [ "$step" -le "$STEPS_COUNT" ]; do
    step_file="$STEPS_DIR/$step"
    name=$(cat "$step_file.name")
    rc=1 seconds=0
    [ -f "$step_file.status" ] && read -r rc seconds < "$step_file.status"
    if [ "$rc" = 0 ]; then
      echo "== $name: passed in ${seconds}s"
    else
      echo "== $name: FAILED (exit $rc) in ${seconds}s. Its output:"
      cat "$step_file.log"
      echo "== End of $name output"
      steps_failed=1
    fi
    step=$((step + 1))
  done
  rm -rf "$STEPS_DIR"
  trap - INT TERM
  return $steps_failed
}
