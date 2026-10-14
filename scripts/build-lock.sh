#!/bin/sh
# One heavy build at a time on this Mac: verify.sh, swift build/test and xcodebuild take one lock, shared by every
# worktree of this repo, so parallel agents don't starve each other (and the tests that time out under load).
# Sourced by verify.sh and the scripts/bin shims. A build that finds the lock taken waits, and says so.
#   SHOWRECORDER_BUILD_LOCK=<file>   use this lock file instead (scripts/test-build-lock.sh)
#   SHOWRECORDER_BUILD_LOCK_HELD=1   set while the lock is held: builds started inside it don't take it again
#   SHOWRECORDER_BUILD_TIMEOUT=<min> stop a build that has held the lock this long (default 20 minutes; #578), its
#                                    whole process group, and free the lock (scripts/build-limit.sh)
#   SHOWRECORDER_BUILD_JOBS=<n>      compile jobs for a build (default: this Mac's cores less 4, at least 1), so one
#                                    build alone doesn't take the whole CPU either. verify.sh takes it as its total
#                                    and gives each of the builds it runs at once a share.
# Stop a locked build with Ctrl-C, or with TERM to its scripts/build-limit.sh (lockf's child): it stops the build's own
# process group, waits for it, then lockf frees the lock. A signal to lockf alone, or a SIGKILL to build-limit.sh,
# frees the lock while the build goes on; the next locked build then stops it, from the record build-limit.sh keeps
# in <lock>.build (#608).

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
  # The build runs under a time limit (scripts/build-limit.sh, #578), so a hung one can't hold every other build up.
  limit=$(CDPATH= cd -P -- "$(dirname -- "$0")/.." 2>/dev/null && pwd -P)/build-limit.sh
  [ -x "$limit" ] || limit=$(git rev-parse --show-toplevel 2>/dev/null)/scripts/build-limit.sh
  # A checkout without it (one made before #578) still builds, without the limit.
  if [ -x "$limit" ]; then
    exec lockf -k "$lock" env SHOWRECORDER_BUILD_LOCK_HELD=1 SHOWRECORDER_BUILD_RECORD="$lock.build" nice -n 10 "$limit" "$@"
  fi
  exec lockf -k "$lock" env SHOWRECORDER_BUILD_LOCK_HELD=1 nice -n 10 "$@"
}

# The absolute git folder every worktree of the repo at or above $1 shares, or nothing outside a git repo.
common_git_dir() {
  # CDPATH empty, so cd never prints a folder into what's captured.
  dir=$(CDPATH= cd -P -- "$1" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null) || return 1
  # Relative to $1 from the main checkout (".git"), absolute from a worktree.
  (CDPATH= cd -P -- "$1" && CDPATH= cd -P -- "$dir" && pwd -P)
}

# How many compile jobs a build may use.
build_jobs() {
  # A whole number of at least 1; anything else is ignored.
  case "${SHOWRECORDER_BUILD_JOBS:-}" in
    "" | *[!0-9]* | 0 | 0*) ;;
    *) printf '%s\n' "$SHOWRECORDER_BUILD_JOBS"; return ;;
  esac
  cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 5)
  [ "$cores" -gt 5 ] && echo $((cores - 4)) || echo 1
}

# Whether the current folder is in a checkout of the repo this script is in: any worktree, even one made before the
# lock existed, which has no scripts/build-lock.sh of its own.
in_showrecorder() {
  here=$(common_git_dir .) || return 1
  ours=$(common_git_dir "$(dirname "$0")/../..") || return 1
  [ "$here" = "$ours" ]
}
