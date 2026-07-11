#!/bin/bash

# Shared AI router process helpers for ai-docker-sandbox (9router / OmniRoute).
#
# Sourced by:
#   - the managed router-wrapper block that entrypoint.sh installs into ~/.bashrc
#   - configure_tools.sh (interactive "AI Router" menu)
#   - behavioral tests (tests/test_router_utils.sh)
#
# Ownership model
# ---------------
# Every router we start records "<pid> <starttime> <executable>" in
# $AI_ROUTER_PID_DIR/<name>.pid. The kernel process start time (field 22 of
# /proc/<pid>/stat) and resolved executable must both still match. npm entry
# points may exec from env/bash into Node immediately after launch; that
# executable transition is accepted only while the same process start time is
# present and its command line still names the expected installed router, then
# the record is refreshed atomically. A recycled or repurposed PID never
# validates and is never signalled. Stopping a router only ever signals that
# exact validated process - no broad `pkill -f <substring>` matches an unrelated
# command line.
#
# Port probing uses `ss` (iproute2, installed explicitly in the Dockerfile)
# with a netstat fallback. A missing probe is an ERROR (return code 2), never
# treated as "port is free".

# Directory holding <name>.pid ownership records (persisted router-data volume
# in the container; overridable for tests).
AI_ROUTER_PID_DIR="${AI_ROUTER_PID_DIR:-${HOME}/.router-data}"

# Poll interval (seconds) for wait loops; tests override this for speed.
AI_ROUTER_POLL_INTERVAL="${AI_ROUTER_POLL_INTERVAL:-1}"

# Pinned router versions (name@version literals; CI's check-pinned-versions
# greps these). The routers are NOT installed by default - they are installed
# on demand the first time you run `9router` or `omniroute`, at these versions.
AI_ROUTER_PIN_9ROUTER="9router@0.5.18"
AI_ROUTER_PIN_OMNIROUTE="omniroute@3.8.45"

# The npm package name for a router equals its command name.
__ai_router_pin() {
    case "$1" in
        9router)   echo "$AI_ROUTER_PIN_9ROUTER" ;;
        omniroute) echo "$AI_ROUTER_PIN_OMNIROUTE" ;;
    esac
}
__ai_router_other() {
    case "$1" in
        9router)   echo "omniroute" ;;
        omniroute) echo "9router" ;;
    esac
}

# True when the router's npm package is installed globally.
ai_router_installed() {
    npm list -g "$1" >/dev/null 2>&1
}

# Install a router at its pinned version, enforcing "only one at a time": if the
# other router is installed it is removed first. Records the single pin so the
# weekly updater holds it. Returns nonzero on install failure.
ai_router_install() {
    local name="$1" other pin
    other=$(__ai_router_other "$name")
    pin=$(__ai_router_pin "$name")
    if [ -z "$pin" ]; then
        echo "Unknown router: $name" >&2
        return 1
    fi
    if [ -n "$other" ] && ai_router_installed "$other"; then
        echo "Removing $other (only one router can be installed at a time)..."
        npm uninstall -g "$other" >/dev/null 2>&1 || true
    fi
    echo "Installing $pin (first run only - this can take a minute)..."
    if ! npm install -g "$pin"; then
        echo "ERROR: failed to install $pin. Try manually: npm install -g $pin" >&2
        return 1
    fi
    # Record the single active pin so auto_update.sh holds it at this version.
    printf '%s\n' "$pin" > "${HOME}/.npm-pinned-tools"
    return 0
}

# Echo the PIDs of processes listening on the given TCP port (one per line).
# Catches the Next.js `next-server` child that actually binds the port, which
# can outlive the router process the wrappers launched.
ai_router_port_pids() {
    local port="$1"
    command -v ss >/dev/null 2>&1 || return 0
    ss -tlnp 2>/dev/null | awk -v port="$port" '
        NR == 1 { next }
        { n = split($4, a, /[:.]/); if (a[n] == port) print $0 }
    ' | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u
}

# Free the shared router port by terminating whatever is listening on it
# (TERM, then KILL for survivors). This is what makes `9router` self-healing:
# a stale or orphaned listener from a previous run is reclaimed rather than
# blocking the next start. Best-effort; returns 0.
ai_router_free_port() {
    local port="${1:-${AI_ROUTER_PORT:-20128}}" pids attempt=0
    pids=$(ai_router_port_pids "$port")
    [ -z "$pids" ] && return 0
    # shellcheck disable=SC2086
    kill -TERM $pids 2>/dev/null || true
    while [ "$attempt" -lt 10 ]; do
        pids=$(ai_router_port_pids "$port")
        [ -z "$pids" ] && return 0
        sleep 0.3
        attempt=$((attempt + 1))
    done
    pids=$(ai_router_port_pids "$port")
    if [ -n "$pids" ]; then
        # shellcheck disable=SC2086
        kill -KILL $pids 2>/dev/null || true
    fi
    return 0
}

__ai_router_pid_file() {
    echo "${AI_ROUTER_PID_DIR}/$1.pid"
}

# True when the process command line identifies the expected installed router.
# This is used only to authorize an executable refresh after an npm wrapper exec.
# Match NUL-delimited argv entries exactly or as a path basename; never accept a
# mere substring in an unrelated argument.
__ai_router_process_matches_name() {
    local name="$1" pid="$2" arg base index=0
    [ -r "/proc/${pid}/cmdline" ] || return 1
    while IFS= read -r -d '' arg; do
        base=${arg##*/}
        if [ "$index" -eq 0 ] && [ "$base" = "$name" ]; then
            return 0
        fi
        if [ "$index" -eq 1 ]; then
            case "$arg" in
                */.npm-global/bin/"$name"|*/node_modules/"$name"/*|*/node_modules/.bin/"$name") return 0 ;;
            esac
        fi
        index=$((index + 1))
    done < "/proc/${pid}/cmdline"
    return 1
}

# Atomically write an ownership record so readers never observe a partial line.
__ai_router_write_pid_record() {
    local name="$1" pid="$2" st="$3" executable="$4" pid_file tmp
    pid_file=$(__ai_router_pid_file "$name")
    tmp="${pid_file}.tmp.$$"
    printf '%s %s %s\n' "$pid" "$st" "$executable" > "$tmp" || return 1
    mv "$tmp" "$pid_file"
}

# Print the kernel start time of a process (clock ticks since boot).
# Returns 1 if the process does not exist.
ai_router_proc_starttime() {
    local pid="$1" stat
    [ -r "/proc/${pid}/stat" ] || return 1
    stat=$(cat "/proc/${pid}/stat" 2>/dev/null) || return 1
    # Strip the "pid (comm) " prefix - comm may itself contain spaces/parens,
    # so cut at the LAST closing paren. starttime is then field 20.
    echo "${stat##*) }" | awk '{print $20}'
}

# Record ownership of a router process: ai_router_record_pid <name> <pid>
ai_router_record_pid() {
    local name="$1" pid="$2" st executable attempt=0
    mkdir -p "$AI_ROUTER_PID_DIR" 2>/dev/null || return 1
    # A just-forked shell may not have exec'd the npm entry point yet. Give that
    # transition a short bounded window rather than recording an ambiguous shell.
    while [ "$attempt" -lt 20 ]; do
        st=$(ai_router_proc_starttime "$pid") || return 1
        executable=$(readlink -f "/proc/${pid}/exe" 2>/dev/null) || return 1
        if [ -n "$st" ] && [ -n "$executable" ] \
            && __ai_router_process_matches_name "$name" "$pid"; then
            __ai_router_write_pid_record "$name" "$pid" "$st" "$executable"
            return $?
        fi
        sleep 0.01
        attempt=$((attempt + 1))
    done
    return 1
}

# Remove the ownership record for a router.
ai_router_clear_pid() {
    rm -f "$(__ai_router_pid_file "$1")"
}

# Echo the PID of the router we own, iff it is alive AND its start time still
# matches the recorded one (i.e. the PID has not been recycled). Returns 1 when
# there is no valid owned process.
ai_router_owned_pid() {
    local name="$1" pid_file pid st executable cur current_executable
    pid_file=$(__ai_router_pid_file "$name")
    [ -f "$pid_file" ] || return 1
    read -r pid st executable < "$pid_file" 2>/dev/null || return 1
    case "$pid" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ -n "${st:-}" ] && [ -n "${executable:-}" ] || return 1
    cur=$(ai_router_proc_starttime "$pid") || return 1
    current_executable=$(readlink -f "/proc/${pid}/exe" 2>/dev/null) || return 1
    [ "$cur" = "$st" ] || return 1
    if [ "$current_executable" != "$executable" ]; then
        # npm's launcher may exec Node after the initial record. Accept and
        # persist that transition only while the original process identity and
        # expected router argv are both still present.
        __ai_router_process_matches_name "$name" "$pid" || return 1
        __ai_router_write_pid_record "$name" "$pid" "$st" "$current_executable" || return 1
    fi
    echo "$pid"
}

# True (0) if the given TCP port has a listener, 1 if free.
# Returns 2 when NO probe is available - callers must treat that as an error,
# never as "port is free".
ai_router_port_busy() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        if ss -tln 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}\$"; then
            return 0
        fi
        return 1
    fi
    if command -v netstat >/dev/null 2>&1; then
        if netstat -tln 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}\$"; then
            return 0
        fi
        return 1
    fi
    return 2
}

# Wait until a port is released: ai_router_wait_port_free <port> [timeout_polls]
# Returns 0 = free, 1 = still busy after the timeout, 2 = no probe available.
ai_router_wait_port_free() {
    local port="$1" timeout="${2:-10}" waited=0 rc
    while :; do
        ai_router_port_busy "$port"
        rc=$?
        [ "$rc" -eq 2 ] && return 2
        [ "$rc" -eq 1 ] && return 0
        [ "$waited" -ge "$timeout" ] && return 1
        sleep "$AI_ROUTER_POLL_INTERVAL"
        waited=$((waited + 1))
    done
}

# Wait until a port HAS a listener (router startup): same return codes,
# 0 = listening, 1 = timeout, 2 = no probe.
ai_router_wait_port_listen() {
    local port="$1" timeout="${2:-30}" waited=0 rc
    while [ "$waited" -lt "$timeout" ]; do
        ai_router_port_busy "$port"
        rc=$?
        [ "$rc" -eq 0 ] && return 0
        [ "$rc" -eq 2 ] && return 2
        sleep "$AI_ROUTER_POLL_INTERVAL"
        waited=$((waited + 1))
    done
    return 1
}

# Stop ONLY the router process we own: ai_router_stop_process <name> [grace_polls]
# SIGTERM first, then SIGKILL after the grace period. Never touches other
# processes; a stale/recycled PID record is simply cleared.
ai_router_stop_process() {
    local name="$1" grace="${2:-5}" pid waited=0
    if ! pid=$(ai_router_owned_pid "$name"); then
        ai_router_clear_pid "$name"
        return 0
    fi
    kill -TERM "$pid" 2>/dev/null || true
    while [ "$waited" -lt "$grace" ]; do
        if ! ai_router_owned_pid "$name" >/dev/null 2>&1; then
            ai_router_clear_pid "$name"
            return 0
        fi
        sleep "$AI_ROUTER_POLL_INTERVAL"
        waited=$((waited + 1))
    done
    # Revalidate immediately before SIGKILL. If the owned process exited and its
    # PID was recycled during the grace period, never signal the replacement.
    if pid=$(ai_router_owned_pid "$name"); then
        kill -KILL "$pid" 2>/dev/null || true
    fi
    ai_router_clear_pid "$name"
    return 0
}

# Last-resort stop for routers started by OLD (pre-PID-file) wrappers, which
# left no ownership record. The pattern is anchored to the real installed npm
# entry points - it can never match an unrelated process whose command line
# merely contains the router name.
__ai_router_legacy_kill() {
    local name="$1" sig="${2:-TERM}"
    pkill "-${sig}" -f "\.npm-global/(bin|lib/node_modules)/(\.bin/)?${name}( |\$)" 2>/dev/null || true
}

# Stop every router (owned first, legacy fallback only if the port is still
# held) and wait for the shared dashboard port to be released.
# Usage: ai_router_stop_all [port] [timeout_polls]
# Returns 0 = port free, 1 = port still busy after timeout, 2 = no port probe.
ai_router_stop_all() {
    local port="${1:-${AI_ROUTER_PORT:-20128}}" timeout="${2:-10}"
    # Stop any process we recorded ownership of (clears its pid file), then
    # definitively reclaim the port from whatever still holds it - including an
    # orphaned next-server child the recorded-PID stop can't see.
    ai_router_stop_process 9router
    ai_router_stop_process omniroute
    ai_router_free_port "$port"
    ai_router_wait_port_free "$port" "$timeout"
}

# Entry point for the `9router` / `omniroute` shell commands.
#
# Goal: typing `9router` just works and drops you into the router's own
# interface. Specifically:
#   1. If the router isn't installed, offer to install it on the spot (routers
#      are opt-in, not part of first-time setup). Installing one removes the
#      other, so only one is ever present.
#   2. Reclaim the shared dashboard port from any stale/orphaned listener
#      (no "port in use" refusal - it self-heals instead).
#   3. Run the router in the FOREGROUND, bound to 0.0.0.0 so the host browser
#      reaches http://localhost:<port>/dashboard, with its own persisted
#      DATA_DIR. You configure providers in the router's own dashboard.
# Stop it with Ctrl+C; the next run reclaims the port regardless of how it exited.
ai_router_exec() {
    local name="$1"
    shift
    local port="${AI_ROUTER_PORT:-20128}" other reply

    if ! ai_router_installed "$name"; then
        other=$(__ai_router_other "$name")
        printf '%s is not installed. Install it now' "$name"
        if [ -n "$other" ] && ai_router_installed "$other"; then
            printf ' (this removes %s - only one router at a time)' "$other"
        fi
        printf '? [y/N] '
        read -r reply
        case "$reply" in
            [yY]|[yY][eE][sS]) ;;
            *) echo "Not installed. Run '${name}' again to install it later."; return 1 ;;
        esac
        ai_router_install "$name" || return 1
    fi

    # Reclaim the port from any stale/orphaned listener, then run in foreground.
    ai_router_free_port "$port"
    mkdir -p "${HOME}/.router-data/${name}"
    echo "Starting ${name} - dashboard at http://localhost:${port}/dashboard  (Ctrl+C to stop)"
    env HOST=0.0.0.0 HOSTNAME=0.0.0.0 PORT="$port" \
        DATA_DIR="${HOME}/.router-data/${name}" "$name" "$@"
}

# Start a router DETACHED (nohup, logging to a file) and record ownership.
# Usage: ai_router_start_detached <name> [port] [log_file]
ai_router_start_detached() {
    local name="$1" port="${2:-${AI_ROUTER_PORT:-20128}}" log_file="${3:-/tmp/$1.log}" pid
    mkdir -p "${HOME}/.router-data/${name}"
    HOST=0.0.0.0 HOSTNAME=0.0.0.0 PORT="$port" \
        DATA_DIR="${HOME}/.router-data/${name}" nohup "$name" > "$log_file" 2>&1 &
    pid=$!
    if ! ai_router_record_pid "$name" "$pid"; then
        kill -TERM "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        return 1
    fi
    disown 2>/dev/null || true
    return 0
}
