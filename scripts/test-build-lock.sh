#!/bin/sh
# Checks the one-heavy-build-at-a-time lock for the shims (scripts/build-lock.sh, scripts/bin/swift and
# scripts/bin/xcodebuild; verify.sh's own lock is scripts/test-verify-lock.sh) with stand-in tools and a lock of its own, so it never waits on, or holds up, a real build on this Mac.
set -eu
cd "$(dirname "$0")/.."
repo=$(pwd)

fail=0
# expect DESCRIPTION COMMAND...: records a failure when the command fails.
expect() {
  desc=$1; shift
  if ! "$@"; then echo "FAIL: $desc"; fail=1; fi
}
# has PATTERN: the last output contains it.
has() { printf '%s\n' "$out" | grep -q -- "$1"; }

work=$(mktemp -d)
old="$work/old-worktree"
# The temporary worktree check 5 makes goes too, even if the test is stopped partway.
trap '[ -d "$old" ] && git worktree remove --force "$old" 2>/dev/null; rm -rf "$work"' EXIT
export SHOWRECORDER_BUILD_LOCK="$work/test.lock"
unset SHOWRECORDER_BUILD_LOCK_HELD || true
log="$work/runs.log"

# Stand-in tools: say when they start and end, take a second (STUB_SLEEP), and echo their arguments.
for tool in swift xcodebuild; do
  cat > "$work/real-$tool" <<STUB
#!/bin/sh
echo "start \$\$ \$(date +%s)" >> "$log"
sleep \${STUB_SLEEP:-1}
echo "end \$\$ \$(date +%s)" >> "$log"
echo "ran $tool \$*"
echo "$tool \$*" >> "$work/args"
STUB
  chmod +x "$work/real-$tool"
done
export SHOWRECORDER_REAL_SWIFT="$work/real-swift" SHOWRECORDER_REAL_XCODEBUILD="$work/real-xcodebuild"

# Holds the test lock in the background, the way another build would, until release_lock.
hold_lock() {
  lockf -k "$SHOWRECORDER_BUILD_LOCK" sleep 30 &
  holder=$!
  sleep 0.5
}
release_lock() {
  # Ends the holder's sleep, so lockf exits and lets the lock go (the sleep would keep it open).
  pkill -P "$holder" sleep 2>/dev/null || true
  wait "$holder" 2>/dev/null || true
}

# How long a command takes, in whole seconds; its stand-in tool returns at once, so only waiting shows.
timed() {
  t0=$(date +%s)
  out=$(STUB_SLEEP=0 "$@" 2>&1) || true
  elapsed=$(( $(date +%s) - t0 ))
}

# 1. Two heavy builds at once: the second waits, says so, and they never overlap.
: > "$log"
"$repo/scripts/bin/swift" build > "$work/first.out" 2>&1 &
first=$!
# Until the first build's tool has started, so it holds the lock (a fixed sleep isn't enough on a busy Mac).
i=0
until grep -q start "$log" 2>/dev/null || [ $i -ge 600 ]; do i=$((i + 1)); sleep 0.1; done
out=$("$repo/scripts/bin/xcodebuild" -scheme ShowRecorder build 2>&1) || true
wait $first || true
expect "a second build says it is waiting" has "Waiting for another build"
expect "the second build still runs, with its arguments" has "ran xcodebuild -scheme ShowRecorder build"
# start A, end A, start B, end B: the second start comes after the first end.
order=$(cut -d' ' -f1 "$log" | tr '\n' ' ')
expect "builds don't overlap (got: $order)" [ "$order" = "start end start end " ]

# 2. A build verify.sh runs while it holds the lock (SHOWRECORDER_BUILD_LOCK_HELD=1) doesn't wait for it.
hold_lock
timed env SHOWRECORDER_BUILD_LOCK_HELD=1 "$repo/scripts/bin/swift" test
expect "a build inside a locked verify doesn't wait (took ${elapsed}s)" [ "$elapsed" -lt 10 ]
release_lock

# 3. Light commands don't wait.
hold_lock
for cmd in "swift --version" "swift package describe" "swift package resolve" \
           "swift package --package-path Packages/ShowRecorderKit describe" "xcodebuild -list" \
           "xcodebuild -version" "xcodebuild -showdestinations -scheme ShowRecorder" "xcodebuild -showsdks"; do
  set -- $cmd
  tool=$1; shift
  timed "$repo/scripts/bin/$tool" "$@"
  expect "'$cmd' doesn't wait (took ${elapsed}s)" [ "$elapsed" -lt 10 ]
done
release_lock

# 4. Outside a ShowRecorder checkout, the shims are plain pass-throughs.
mkdir "$work/elsewhere"
hold_lock
timed sh -c "cd '$work/elsewhere' && '$repo/scripts/bin/swift' build"
expect "outside the repo, swift build doesn't wait (took ${elapsed}s)" [ "$elapsed" -lt 10 ]
expect "outside the repo, the real tool still runs" has "ran swift build"
release_lock

# 5. A worktree of this repo made before the lock existed (no scripts/build-lock.sh of its own) still takes it; another
#    git repo doesn't. The old worktree is a bare, unchecked-out one, made here and removed at the end.
git worktree add -q --detach --no-checkout "$old" HEAD
mkdir -p "$old/Packages/ShowRecorderKit"
hold_lock
(cd "$old/Packages/ShowRecorderKit" && STUB_SLEEP=0 "$repo/scripts/bin/swift" build) > "$work/old.out" 2>&1 &
waiter=$!
# Until it says it's waiting (or 20 s), then let the lock go, rather than sit out the holder.
i=0
until grep -q "Waiting for another build" "$work/old.out" || [ $i -ge 200 ]; do i=$((i + 1)); sleep 0.1; done
release_lock
wait "$waiter" || true
out=$(cat "$work/old.out")
expect "an old worktree without build-lock.sh still waits for the lock" has "Waiting for another build"
expect "and then runs" has "ran swift build"
git worktree remove --force "$old"
mkdir "$work/other-repo"
git -C "$work/other-repo" init -q
hold_lock
timed sh -c "cd '$work/other-repo' && '$repo/scripts/bin/swift' build"
release_lock
expect "another git repo doesn't wait (took ${elapsed}s)" [ "$elapsed" -lt 10 ]
expect "another git repo still runs the real tool" has "ran swift build"

# 6. Every heavy build is capped at N compile jobs: SHOWRECORDER_BUILD_JOBS, or the Mac's cores less 4 (at least 1).
#    A count the caller gave is kept, light commands get none, and builds inside verify.sh are capped too.
cores=$(sysctl -n hw.ncpu)
default=$(( cores > 5 ? cores - 4 : 1 ))
timed "$repo/scripts/bin/swift" build
expect "swift build gets -j <cores - 4> by default (output: $out)" has "ran swift build -j $default\$"
timed env SHOWRECORDER_BUILD_JOBS=3 "$repo/scripts/bin/xcodebuild" -scheme ShowRecorder build
expect "xcodebuild gets -jobs from SHOWRECORDER_BUILD_JOBS (output: $out)" has "ran xcodebuild -scheme ShowRecorder build -jobs 3\$"
timed env SHOWRECORDER_BUILD_JOBS=3 "$repo/scripts/bin/swift" run Tool -- --verbose
expect "swift run gets -j before the program's own arguments (output: $out)" has "ran swift run -j 3 Tool -- --verbose\$"
timed env SHOWRECORDER_BUILD_JOBS=3 "$repo/scripts/bin/swift" build -j 2
expect "a -j the caller gave is kept (output: $out)" has "ran swift build -j 2\$"
timed env SHOWRECORDER_BUILD_JOBS=3 "$repo/scripts/bin/xcodebuild" build -jobs 5
expect "a -jobs the caller gave is kept (output: $out)" has "ran xcodebuild build -jobs 5\$"
timed env SHOWRECORDER_BUILD_JOBS=3 SHOWRECORDER_BUILD_LOCK_HELD=1 "$repo/scripts/bin/swift" test
expect "a build inside verify.sh's lock is capped too (output: $out)" has "ran swift test -j 3\$"
timed env SHOWRECORDER_BUILD_JOBS=3 "$repo/scripts/bin/swift" --version
expect "light commands get no -j (output: $out)" has "ran swift --version\$"

# verify.sh runs the package tests and both app builds at once: each gets a third of N.
: > "$work/args"
out=$(SHOWRECORDER_BUILD_JOBS=6 VERIFY_FILES="Packages/ShowRecorderKit/Sources/Recording/AutoGainSession.swift" ./scripts/verify.sh 2>&1) || true
expect "verify.sh's package tests get N/3 (args: $(cat "$work/args"))" grep -q "^swift test -j 2 --parallel\$" "$work/args"
expect "verify.sh's app builds get N/3 each" [ "$(grep -c -- "-jobs 2\$" "$work/args")" = 2 ]

[ $fail = 0 ] && echo "build lock: all checks passed"
exit $fail
