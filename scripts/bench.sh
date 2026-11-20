#!/bin/bash
# Measures Tethera on this Mac and prints a Markdown table:
#
#   scripts/bench.sh                 # uses dist/Tethera.app (make app first)
#   scripts/bench.sh path/to/Tethera.app
#
# Everything runs against a throwaway TETHERA_HOME, so your own sessions are never touched.
set -euo pipefail

APP="${1:-dist/Tethera.app}"
CLI="$APP/Contents/Helpers/tethera"
[ -x "$CLI" ] || { echo "No $CLI; run make app first." >&2; exit 1; }

export TETHERA_HOME
TETHERA_HOME="$(mktemp -d "${TMPDIR:-/tmp}/tethera-bench.XXXXXX")"
cleanup() {
    "$CLI" shutdown >/dev/null 2>&1 || true
    [ -n "${APP_PID:-}" ] && kill "$APP_PID" 2>/dev/null || true
    rm -rf "${TETHERA_HOME:?}"
}
trap cleanup EXIT

now() { perl -MTime::HiRes=time -e 'printf "%.6f\n", time'; }
elapsed_ms() { perl -e "printf '%.0f', ($2 - $1) * 1000"; }

# Wait until no session is left (each one exits its shell when its command ends).
wait_for_sessions_to_end() {
    for _ in $(seq 1 3000); do
        "$CLI" list 2>/dev/null | grep -q "No sessions" && return 0
        sleep 0.02
    done
    echo "timed out" >&2
    return 1
}

echo "Measuring $("$CLI" version) on $(sysctl -n machdep.cpu.brand_string), macOS $(sw_vers -productVersion)…" >&2

# 1. The daemon starting from nothing, as the first `tethera list` does.
start=$(now); "$CLI" list >/dev/null; end=$(now)
DAEMON_START=$(elapsed_ms "$start" "$end")

# 2. A command round trip once it's running (median of 30).
times=()
for _ in $(seq 1 30); do
    start=$(now); "$CLI" list >/dev/null; end=$(now)
    times+=("$(elapsed_ms "$start" "$end")")
done
ROUND_TRIP=$(printf '%s\n' "${times[@]}" | sort -n | sed -n '15p')

# 3. Throughput: 2,000,000 lines (about 14.8 MB) through a session's emulator, no window.
# A session that only exits first, so the shell's own startup isn't counted.
start=$(now)
"$CLI" new --name baseline -- 'exit' >/dev/null
wait_for_sessions_to_end
end=$(now)
BASELINE_MS=$(elapsed_ms "$start" "$end")
start=$(now)
"$CLI" new --name bench -- 'seq 1 2000000; exit' >/dev/null
wait_for_sessions_to_end
end=$(now)
SEQ_MS=$(( $(elapsed_ms "$start" "$end") - BASELINE_MS ))
SEQ_MBS=$(perl -e "printf '%.0f', 14.8 / ($SEQ_MS / 1000)")

# 4. Handing the daemon over to a new image with 10 live sessions.
for i in $(seq 1 10); do "$CLI" new --name "s$i" >/dev/null; done
sleep 2
start=$(now); "$CLI" handover >/dev/null; end=$(now)
HANDOVER=$(elapsed_ms "$start" "$end")
"$CLI" shutdown >/dev/null 2>&1 || true
sleep 0.5

# 5. App launch until it answers on its socket (cold-ish: after the daemon exists).
"$CLI" list >/dev/null
start=$(now)
"$APP/Contents/MacOS/Tethera" >/dev/null 2>&1 &
APP_PID=$!
for _ in $(seq 1 1000); do [ -S "$TETHERA_HOME/app.sock" ] && break; sleep 0.01; done
end=$(now)
LAUNCH=$(elapsed_ms "$start" "$end")
kill "$APP_PID" 2>/dev/null || true
APP_PID=""

cat <<TABLE
| What | Time |
| --- | --- |
| Daemon start (first command) | ${DAEMON_START} ms |
| Command round trip (median) | ${ROUND_TRIP} ms |
| \`seq 1 2000000\` through a session | ${SEQ_MS} ms (${SEQ_MBS} MB/s) |
| Handover to a new daemon, 10 sessions | ${HANDOVER} ms |
| App launch to ready | ${LAUNCH} ms |
TABLE
