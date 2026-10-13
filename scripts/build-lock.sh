#!/bin/sh
# One heavy build at a time on this Mac: verify.sh, swift build/test and xcodebuild take one lock, shared by every
# worktree of this repo, so parallel agents don't starve each other (and the tests that time out under load).
# Sourced by verify.sh and the scripts/bin shims. A build that finds the lock taken waits, and says so.
#   SHOWRECORDER_BUILD_LOCK=<file>   use this lock file instead (scripts/test-build-lock.sh)
#   SHOWRECORDER_BUILD_LOCK_HELD=1   set while the lock is held: builds started inside it don't take it again

# The lock file: one per repo, in the git folder every worktree shares.
build_lock_path() {
  if [ -n "${SHOWRECORDER_BUILD_LOCK:-}" ]; then
    printf '%s\n' "$SHOWRECORDER_BUILD_LOCK"
    return
  fi
  common=$(git rev-parse --git-common-dir) || return 1
  # Relative from the main checkout (".git"), absolute from a worktree.
  case "$common" in /*) ;; *) common="$(pwd)/$common" ;; esac
  printf '%s\n' "$common/verify.lock"
}

# build_lock_exec COMMAND...: runs the command holding the lock, at low priority, waiting for it if another build has
# it. Replaces the current process.
build_lock_exec() {
  lock=$(build_lock_path) || { echo "build-lock: not in a git checkout" >&2; exit 1; }
  if ! lockf -k -t 0 "$lock" true 2>/dev/null; then
    echo "== Waiting for another build on this Mac to finish (lock: $lock)" >&2
  fi
  exec lockf -k "$lock" env SHOWRECORDER_BUILD_LOCK_HELD=1 nice -n 10 "$@"
}

# Whether the current folder is in a ShowRecorder checkout.
in_showrecorder() {
  top=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  [ -f "$top/scripts/build-lock.sh" ] && [ -d "$top/Packages/ShowRecorderKit" ]
}
