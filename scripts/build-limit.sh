#!/bin/sh
# Runs a held build (the command given) for at most SHOWRECORDER_BUILD_TIMEOUT minutes (default 20; whole or decimal
# minutes of at least a second, such as 0.5; anything else means the default), then stops it, its whole process
# group, and says why (#578). build-lock.sh runs it under lockf, so the lock is freed once the build is stopped and
# the next waiting build starts. Only time holding the lock counts, never the wait for it.
#
# The build runs in a process group of its own, so stopping it reaches everything it started (swiftpm-testing-helper,
# compilers). Ctrl-C, Ctrl-\, TERM and HUP to this script stop the build the same way, and this script waits for it to
# finish before it exits, so the lock is never freed while the build still runs. A SIGKILL to this script can't be
# caught: the build then goes on without the lock.
minutes=${SHOWRECORDER_BUILD_TIMEOUT:-20}
seconds=$(awk -v m="$minutes" 'BEGIN { s = m * 60; if (m ~ /^[0-9]*\.?[0-9]+$/ && s >= 1) printf "%d", s + 0.5 }')
if [ -z "$seconds" ]; then
  minutes=20
  seconds=1200
fi

# A build in its own group stops (SIGTTIN) if it reads a terminal, so a terminal on stdin is cut off; piped input
# still reaches the build, as in `swift run Tool < input` (#578).
set -m
if [ -t 0 ]; then "$@" < /dev/null & else "$@" & fi
build=$!
set +m

# Stops the build's whole group: TERM, then KILL whatever is left after 5 s. Then waits for it, and stops the timer.
stop() {
  # A second signal during the stop wait doesn't start stopping again (#578).
  trap '' INT QUIT TERM HUP USR1
  kill -TERM -- -"$build" 2>/dev/null
  i=0
  while kill -0 -- -"$build" 2>/dev/null && [ $i -lt 50 ]; do i=$((i + 1)); sleep 0.1; done
  kill -KILL -- -"$build" 2>/dev/null
  wait "$build" 2>/dev/null
  end_timer
}

# The timer goes with this script, whichever way it ends.
end_timer() {
  [ -n "${watchdog:-}" ] || return 0
  kill "$watchdog" 2>/dev/null
  wait "$watchdog" 2>/dev/null
}
trap 'stop; exit 130' INT
trap 'stop; exit 131' QUIT
trap 'stop; exit 143' TERM HUP
trap 'echo "== Stopped: this build held the build lock for more than $minutes min (SHOWRECORDER_BUILD_TIMEOUT), so it was stopped and the lock freed for the next one. A hung test? Run it again, or set SHOWRECORDER_BUILD_TIMEOUT higher for a long build." >&2; stop; exit 124' USR1

# The time limit: tells this script (USR1) when it's reached. Quiet when the build ends first and it's told to go.
(
  trap 'kill "$timer" 2>/dev/null; exit 0' TERM
  sleep "$seconds" &
  timer=$!
  wait "$timer" && kill -USR1 "$$"
) 2>/dev/null &
watchdog=$!

status=0
wait "$build" || status=$?
# A timer firing as the build ends can't stop or fail a build that already finished (#578).
trap '' USR1
end_timer
exit "$status"
