# Runs verify.sh's slow steps side by side (sourced, POSIX sh). Each step writes to its own log; when all have
# finished, each one's result and duration is printed, and only a failing step's log, so outputs never interleave.
#   steps_start                  begin a set of steps
#   run_step "Name" command...   start one in the background
#   steps_finish                 wait for all; non-zero if any failed
# Ctrl-C (exit 130) or TERM (exit 143) stops every step it started and everything those started, and only those.

steps_start() {
  STEPS_DIR=$(mktemp -d "${TMPDIR:-/tmp}/verify.XXXXXX")
  STEPS_COUNT=0
  STEPS_PIDS=""
  # A script's background steps ignore Ctrl-C, so stop them here.
  trap 'steps_stop 130' INT
  trap 'steps_stop 143' TERM
}

# Every process below `pid`, deepest last, so a build's own children are found before they can be orphaned.
steps_descendants() {
  for steps_child in $(pgrep -P "$1" 2>/dev/null); do
    echo "$steps_child"
    steps_descendants "$steps_child"
  done
}

steps_stop() {
  trap - INT TERM
  steps_victims=""
  for steps_pid in $STEPS_PIDS; do
    steps_victims="$steps_victims $steps_pid $(steps_descendants "$steps_pid")"
  done
  # shellcheck disable=SC2086
  [ -n "${steps_victims# }" ] && kill -TERM $steps_victims 2>/dev/null
  wait
  rm -rf "$STEPS_DIR"
  exit "$1"
}

run_step() {
  STEPS_COUNT=$((STEPS_COUNT + 1))
  step_file="$STEPS_DIR/$STEPS_COUNT"
  printf '%s\n' "$1" > "$step_file.name"
  shift
  echo "== Started: $(cat "$step_file.name")"
  (
    started=$(date +%s)
    if "$@" > "$step_file.log" 2>&1; then rc=0; else rc=$?; fi
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
    { [ -f "$step_file.status" ] && read -r rc seconds < "$step_file.status"; } || :
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
