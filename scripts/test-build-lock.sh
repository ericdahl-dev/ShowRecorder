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
# Stand-ins that hang sleep for a length only this run uses, matched exactly (^sleep N$), so two runs at once (agents
# in other worktrees) never see, or stop, each other's processes, and no shell whose command line mentions it matches.
hang=$((600 + $$ % 1000))
timer=$((1700 + $$ % 1000))
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
# Stopped, it takes STUB_CLEANUP seconds to clean up (a build writing its last files), then says so.
trap 'sleep \${STUB_CLEANUP:-0}; echo "cleaned \$\$" >> "$log"; exit 143' TERM
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
# The first holds the lock for 4 s, so on a busy Mac the second still finds it taken.
STUB_SLEEP=4 "$repo/scripts/bin/swift" build > "$work/first.out" 2>&1 &
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

timed env SHOWRECORDER_BUILD_JOBS=3 "$repo/scripts/bin/swift" run Tool -j 4
expect "a -j for the program, after it, doesn't turn the cap off (output: $out)" has "ran swift run -j 3 Tool -j 4\$"
timed env SHOWRECORDER_BUILD_JOBS=3 "$repo/scripts/bin/xcodebuild" -create-xcframework -framework A.framework -output A.xcframework
expect "xcodebuild without a build action gets no -jobs (output: $out)" has "ran xcodebuild -create-xcframework -framework A.framework -output A.xcframework\$"
for bad in abc 0; do
  timed env SHOWRECORDER_BUILD_JOBS=$bad "$repo/scripts/bin/swift" build
  expect "SHOWRECORDER_BUILD_JOBS=$bad falls back to the default (output: $out)" has "ran swift build -j $default\$"
done

# verify.sh runs the package tests and both app builds at once: each gets a third of N.
: > "$work/args"
out=$(VERIFY_QUICK=0 SHOWRECORDER_BUILD_JOBS=6 VERIFY_FILES="Packages/ShowRecorderKit/Sources/Recording/AutoGainSession.swift" ./scripts/verify.sh 2>&1) || true
expect "verify.sh's package tests get N/3 (args: $(cat "$work/args"))" grep -q "^swift test -j 2 --parallel\$" "$work/args"
expect "verify.sh's app builds get N/3 each" [ "$(grep -c -- "-jobs 2\$" "$work/args")" = 2 ]

# 7. A build that holds the lock past the time limit (#578) is stopped, its whole process group, says why, and the
#    lock is free again. SHOWRECORDER_BUILD_TIMEOUT is minutes; 0.05 is 3 s.
: > "$log"
t0=$(date +%s)
STUB_SLEEP=$hang SHOWRECORDER_BUILD_TIMEOUT=0.05 "$repo/scripts/bin/swift" test > "$work/limit.out" 2>&1 &
limited=$!
# This test stops waiting after 20 s itself, so a missing limit fails fast instead of hanging for 10 minutes.
i=0
while kill -0 "$limited" 2>/dev/null && [ $i -lt 200 ]; do i=$((i + 1)); sleep 0.1; done
still=0
if kill -0 "$limited" 2>/dev/null; then
  still=1
  pkill -f "^sleep $hang\$" 2>/dev/null || true
fi
status=0
wait "$limited" || status=$?
out=$(cat "$work/limit.out")
elapsed=$(( $(date +%s) - t0 ))
expect "a build past the limit is stopped (took ${elapsed}s)" [ "$still" = 0 ]
expect "it fails (status $status)" [ "$status" != 0 ]
expect "it says why (output: $out)" has "held the build lock for more than"
expect "the lock is free again" lockf -k -t 0 "$SHOWRECORDER_BUILD_LOCK" true
stub=$(awk '/^start/ { print $2 }' "$log")
expect "the stand-in was started" [ -n "$stub" ]
expect "the stand-in is gone" sh -c "! kill -0 '$stub' 2>/dev/null"
expect "its own child (sleep $hang) is gone too: the whole process group" sh -c "! kill -0 -- -'$stub' 2>/dev/null"

# 8. Stopping a build (Ctrl-C at a terminal, or TERM as a harness sends) holds the lock until the build has finished
#    cleaning up, so the next build never starts beside it (#578). TERM here: a script's background jobs start with
#    SIGINT ignored, which no shell can trap, while at a terminal Ctrl-C takes the same path.
: > "$log"
# A limit whose timer is `sleep $timer`, a length only this run uses.
STUB_SLEEP=$hang STUB_CLEANUP=2 SHOWRECORDER_BUILD_TIMEOUT=$(awk -v s="$timer" 'BEGIN { printf "%.6f", s / 60 }') \
  "$repo/scripts/bin/swift" test > "$work/stop.out" 2>&1 &
shim=$!
i=0
until grep -q start "$log" 2>/dev/null || [ $i -ge 600 ]; do i=$((i + 1)); sleep 0.1; done
# The shim became lockf; its child is build-limit.sh.
wrapper=$(pgrep -P "$shim" | head -1)
expect "build-limit.sh runs under lockf" [ -n "$wrapper" ]
[ -n "$wrapper" ] && kill -TERM "$wrapper"
i=0
until lockf -k -t 0 "$SHOWRECORDER_BUILD_LOCK" true 2>/dev/null || [ $i -ge 200 ]; do i=$((i + 1)); sleep 0.1; done
expect "a stopped build frees the lock only once it has cleaned up (log: $(tr '\n' ' ' < "$log"))" grep -q cleaned "$log"
pkill -f "^sleep $hang\$" 2>/dev/null || true
i=0
while kill -0 "$shim" 2>/dev/null && [ $i -lt 100 ]; do i=$((i + 1)); sleep 0.1; done
kill "$shim" 2>/dev/null || true
expect "a stopped build leaves no timer behind" sh -c "! pgrep -f '^sleep $timer\$' >/dev/null"
pkill -f "^sleep $timer\$" 2>/dev/null || true
expect "a normal build prints nothing about the time limit (output: $(cat "$work/first.out"))" sh -c "! grep -q 'Terminated' '$work/first.out'"

# 9. Input piped into a locked command still reaches it (`swift run Tool < input`); only a terminal is cut off, so a
#    build can't stop on reading it.
out=$(echo piped | "$repo/scripts/build-limit.sh" cat 2>&1) || true
expect "piped input reaches the command (output: $out)" has "^piped\$"

[ $fail = 0 ] && echo "build lock: all checks passed"
exit $fail
