#!/usr/bin/env bash
# Behavioral tests for configure_tools.sh diagnostics.
#
# Focus: the --diagnose TLS reachability probe must classify a successful
# DNS+TCP+TLS handshake as reachable EVEN WHEN the HTTP status is >= 400
# (e.g. an unauthenticated 401/403 or a bare-root 404/421). Only genuine
# transport failures (DNS/connect/timeout/SSL) count as TLS=failed.
set -u

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
PASS=0
FAIL=0
trap 'rm -rf "$TMP_DIR"; [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null' EXIT

pass() { printf 'ok - %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'not ok - %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
assert_true() { local label=$1; shift; if "$@"; then pass "$label"; else fail "$label"; fi; }
assert_false() { local label=$1; shift; if "$@" >/dev/null 2>&1; then fail "$label"; else pass "$label"; fi; }

CONFIG="$ROOT_DIR/docker/configure_tools.sh"

# ---------------------------------------------------------------------------
# Regression guard: the TLS probe must not use `curl -f`/`--fail`, which folds
# any HTTP >= 400 into a transport-failure exit code.
# ---------------------------------------------------------------------------
# Check the actual curl invocation line (ignore comments, which mention curl -f
# to explain WHY it is avoided).
# Grab the curl invocation including its line continuation.
curl_line=$(awk '/code=\$\(curl/{c=1} c{print; if($0 !~ /\\$/) exit}' "$CONFIG")
assert_true "found the tls_probe curl invocation" test -n "$curl_line"
assert_false "TLS probe curl call does not use -f/--fail" bash -c "printf '%s' \"\$1\" | grep -Eq '(-[a-zA-Z]*f[a-zA-Z]*|--fail)'" _ "$curl_line"
assert_true "TLS probe inspects http_code" bash -c "printf '%s' \"\$1\" | grep -q 'http_code'" _ "$curl_line"

# ---------------------------------------------------------------------------
# Extract the tls_probe function definition and exercise it directly against a
# local server. This mirrors the exact logic used by diagnose_environment
# without sourcing the whole script (which has side effects).
# ---------------------------------------------------------------------------
probe_def=$(awk '/^    tls_probe\(\) \{/{f=1} f{print} /^    \}$/{if(f) exit}' "$CONFIG" | sed 's/^    //')
if [ -z "$probe_def" ]; then
    fail "could not extract tls_probe definition"
else
    pass "extracted tls_probe definition"
    eval "$probe_def"

    if command -v python3 >/dev/null 2>&1; then
        # Mock HTTP server that returns 404 for every request - a healthy
        # transport with a non-2xx application status.
        python3 -m http.server 0 --bind 127.0.0.1 --directory "$TMP_DIR" >"$TMP_DIR/server.log" 2>&1 &
        SERVER_PID=$!
        # Discover the assigned port. Prefer python's own startup banner
        # ("Serving HTTP on 127.0.0.1 port NNNNN ..."), which needs no
        # privileges; fall back to ss (which only shows pid= as root, so it
        # can't be the sole source in an unprivileged container/CI runner).
        port=""
        for _ in $(seq 1 50); do
            port=$(grep -oE 'port [0-9]+' "$TMP_DIR/server.log" 2>/dev/null | head -1 | awk '{print $2}')
            [ -z "$port" ] && port=$(ss -ltnp 2>/dev/null | grep "pid=$SERVER_PID," | grep -oE '127.0.0.1:[0-9]+' | head -1 | cut -d: -f2)
            [ -n "$port" ] && break
            sleep 0.1
        done
        if [ -n "$port" ]; then
            # http.server returns 404 for missing paths; probe must still succeed.
            assert_true "probe treats 404 (healthy transport) as reachable" tls_probe "http://127.0.0.1:$port/nonexistent"
            code=$(tls_probe "http://127.0.0.1:$port/nonexistent")
            assert_true "probe echoes the real HTTP status" test "$code" = "404"
        else
            fail "could not determine mock server port"
        fi

        # Unroutable/closed port: genuine transport failure -> probe fails.
        assert_false "probe treats connection refused as unreachable" tls_probe "http://127.0.0.1:1/"
    else
        printf '# skipping live probe tests (python3 unavailable)\n'
    fi
fi

printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
