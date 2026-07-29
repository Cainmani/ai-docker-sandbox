#!/usr/bin/env bash
set -u

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
PASS=0
FAIL=0
PIDS=()
cleanup() {
    local pid
    for pid in "${PIDS[@]}"; do
        kill -KILL "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    done
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

export AI_ROUTER_PID_DIR="$TMP_DIR/pids"
export AI_ROUTER_POLL_INTERVAL=0
# shellcheck source=../docker/lib/router_utils.sh
source "$ROOT_DIR/docker/lib/router_utils.sh"

pass() { printf 'ok - %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'not ok - %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
assert_true() { local label=$1; shift; if "$@"; then pass "$label"; else fail "$label"; fi; }
assert_false() { local label=$1; shift; if "$@" >/dev/null 2>&1; then fail "$label"; else pass "$label"; fi; }

mkdir -p "$TMP_DIR/bin"
cat > "$TMP_DIR/bin/9router" <<'SCRIPT'
#!/usr/bin/env bash
exec -a 9router sleep 60
SCRIPT
chmod +x "$TMP_DIR/bin/9router"

PATH="$TMP_DIR/bin:$PATH" 9router &
router_pid=$!
PIDS+=("$router_pid")
sleep 0.05
assert_true "records a named router process" ai_router_record_pid 9router "$router_pid"
assert_true "validates the recorded router process" test "$(ai_router_owned_pid 9router)" = "$router_pid"

recorded_exe=$(readlink -f "/proc/$router_pid/exe")
record_file="$AI_ROUTER_PID_DIR/9router.pid"
assert_true "records the post-exec executable" grep -Fq "$recorded_exe" "$record_file"

# A stale executable is refreshed only for the same start time and expected
# router argv. This models recording an npm shell wrapper immediately before it
# execs Node.
read -r saved_pid saved_start _ < "$record_file"
printf '%s %s %s\n' "$saved_pid" "$saved_start" /usr/bin/env > "$record_file"
assert_true "accepts and refreshes an npm wrapper exec transition" test "$(ai_router_owned_pid 9router)" = "$router_pid"
assert_true "persists the refreshed executable" grep -Fq "$recorded_exe" "$record_file"

# A valid PID/start time with an unrelated argv must never be adopted merely
# because its executable differs from a stale record.
sleep 60 &
decoy_pid=$!
PIDS+=("$decoy_pid")
decoy_start=$(ai_router_proc_starttime "$decoy_pid")
printf '%s %s %s\n' "$decoy_pid" "$decoy_start" /usr/bin/env > "$record_file"
assert_false "rejects an unrelated process after executable mismatch" ai_router_owned_pid 9router
assert_true "unrelated decoy remains alive" kill -0 "$decoy_pid"

# Stopping signals only the exact owned process and leaves the decoy alive.
ai_router_record_pid 9router "$router_pid"
assert_true "stops the owned router" ai_router_stop_process 9router 1
sleep 0.05
assert_false "owned router exited" kill -0 "$router_pid"
assert_true "decoy survives owned-router stop" kill -0 "$decoy_pid"

# Port polling behavior is tested through a fake ss command. Two busy probes
# followed by a free probe exercise delayed socket release without real ports.
probe_count="$TMP_DIR/probe-count"
printf '0\n' > "$probe_count"
ss() {
    local count
    count=$(<"$probe_count")
    count=$((count + 1))
    printf '%s\n' "$count" > "$probe_count"
    if [ "$count" -le 2 ]; then
        printf 'State Recv-Q Send-Q Local Address:Port Peer Address:Port\nLISTEN 0 1 0.0.0.0:20128 0.0.0.0:*\n'
    else
        printf 'State Recv-Q Send-Q Local Address:Port Peer Address:Port\n'
    fi
}
assert_true "waits through delayed socket release" ai_router_wait_port_free 20128 3

ss() { printf 'State Recv-Q Send-Q Local Address:Port Peer Address:Port\nLISTEN 0 1 0.0.0.0:20128 0.0.0.0:*\n'; }
assert_false "times out while a port remains occupied" ai_router_wait_port_free 20128 1

if PATH=/nonexistent /bin/bash -c ". '$ROOT_DIR/docker/lib/router_utils.sh'; ai_router_port_busy 20128"; then
    fail "missing probe is not reported as free"
else
    rc=$?
    if [ "$rc" -eq 2 ]; then pass "missing probe returns status 2"; else fail "missing probe returns status 2"; fi
fi

# --- opt-in install helpers (pins, mutual exclusion mapping, port pids) ---

# The router package name equals its command name and maps to a pinned spec.
assert_true "9router pin is a name@version literal" test "$(__ai_router_pin 9router)" = "9router@0.5.40"
assert_true "omniroute pin is a name@version literal" test "$(__ai_router_pin omniroute)" = "omniroute@3.8.48"

# "Only one at a time" mapping: each router's counterpart is the other one.
assert_true "9router's counterpart is omniroute" test "$(__ai_router_other 9router)" = "omniroute"
assert_true "omniroute's counterpart is 9router" test "$(__ai_router_other omniroute)" = "9router"

# ai_router_port_pids extracts the listener PID from ss output (the next-server
# child that holds the shared port).
ss() { printf 'State Recv-Q Send-Q Local Address:Port Peer Address:Port Process\nLISTEN 0 511 0.0.0.0:20128 0.0.0.0:* users:(("next-server",pid=4242,fd=18))\n'; }
assert_true "port_pids finds the listener pid" test "$(ai_router_port_pids 20128)" = "4242"
ss() { printf 'State Recv-Q Send-Q Local Address:Port Peer Address:Port Process\n'; }
assert_true "port_pids is empty when nothing listens" test -z "$(ai_router_port_pids 20128)"
unset -f ss

printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
