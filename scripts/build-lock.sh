#!/bin/sh
# One heavy build at a time on this Mac: verify.sh, swift build/test and xcodebuild take one lock, shared by every
# worktree of this repo, so parallel agents don't starve each other (and the tests that time out under load).
# Sourced by verify.sh and the scripts/bin shims. A build that finds the lock taken waits, and says so.
#   SHOWRECORDER_BUILD_LOCK=<file>   use this lock file instead (scripts/test-build-lock.sh)
#   SHOWRECORDER_BUILD_LOCK_HELD=1   set while the lock is held: builds started inside it don't take it again
# Stop a locked build with Ctrl-C, or by signaling its whole process group (kill -- -PGID): lockf holds the lock and
# runs the build as its child, so a signal to lockf alone frees the lock while the build goes on.

# The lock file: one per repo, in the git folder every worktree shares.
build_lock_path() {
  if [ -n "${SHOWRECORDER_BUILD_LOCK:-}" ]; then
    printf '%s\n' "$SHOWRECORDER_BUILD_LOCK"
    return
  fi
  common=$(common_git_dir .) || return 1
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

# The absolute git folder every worktree of the repo at or above $1 shares, or nothing outside a git repo.
common_git_dir() {
  dir=$(cd "$1" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null) || return 1
  # Relative to $1 from the main checkout (".git"), absolute from a worktree.
  (cd "$1" && cd "$dir" && pwd -P)
}

# Whether the current folder is in a checkout of the repo this script is in: any worktree, even one made before the
# lock existed, which has no scripts/build-lock.sh of its own.
in_showrecorder() {
  here=$(common_git_dir .) || return 1
  ours=$(common_git_dir "$(dirname "$0")/../..") || return 1
  [ "$here" = "$ours" ]
}
