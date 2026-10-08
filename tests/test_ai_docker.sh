#!/usr/bin/env bash
# Behavioral tests for docker/ai_docker.sh (`ai-docker status`).
set -u

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
PASS=0
FAIL=0
trap 'rm -rf "$TMP_DIR"' EXIT

pass() { printf 'ok - %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'not ok - %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
assert_eq() {
    local label=$1 expected=$2 actual=$3
    if [ "$expected" = "$actual" ]; then pass "$label"; else fail "$label (expected $expected, got $actual)"; fi
}
assert_contains() {
    local label=$1 haystack=$2 needle=$3
    if printf '%s\n' "$haystack" | grep -Fq -- "$needle"; then pass "$label"; else fail "$label (missing: $needle)"; fi
}
assert_not_contains() {
    local label=$1 haystack=$2 needle=$3
    if printf '%s\n' "$haystack" | grep -Fq -- "$needle"; then fail "$label (unexpected: $needle)"; else pass "$label"; fi
}

days_ago() { date -Iseconds -d "-$1 days"; }

setup_case() {
    CASE_DIR=$(mktemp -d "$TMP_DIR/case.XXXXXX")
    export HOME="$CASE_DIR/home"
    mkdir -p "$HOME/.ai-docker" "$CASE_DIR/bin" "$CASE_DIR/cgroup" "$CASE_DIR/tmp"
    printf 'STATUS=ok\nFAILED_TOOLS=\n' > "$HOME/.cli_tools_installed"
    printf '1.6.0\n' > "$CASE_DIR/version"
    printf '10737418240\n' > "$CASE_DIR/cgroup/memory.max"
    printf '600000 100000\n' > "$CASE_DIR/cgroup/cpu.max"
    export AI_DOCKER_LIB_DIR="$ROOT_DIR/docker/lib"
    export AI_DOCKER_VERSION_FILE="$CASE_DIR/version"
    export AI_DOCKER_CGROUP_DIR="$CASE_DIR/cgroup"
    export AI_DOCKER_TMP_DIR="$CASE_DIR/tmp"
    export AI_DOCKER_DISK_PATH="$CASE_DIR"
    export AI_DOCKER_DISK_WARN_GB=100000
    # Tools that record any invocation, so --brief can be proven not to run them.
    export TOOL_CALLS="$CASE_DIR/tool-calls"
    for tool in claude gh codex gemini opencode; do
        cat > "$CASE_DIR/bin/$tool" <<SCRIPT
#!/usr/bin/env bash
echo "$tool" >> "\$TOOL_CALLS"
echo "$tool 9.9.9"
SCRIPT
    done
    chmod +x "$CASE_DIR/bin/"*
    export PATH="$CASE_DIR/bin:/usr/bin:/bin"
}

write_status() {
    # write_status <result> <last_check_ok> <last_update_ok> <failed_stages> [last_attempt]
    {
        echo "RESULT=$1"
        echo "LAST_ATTEMPT=${5:-$(date -Iseconds)}"
        echo "LAST_CHECK_OK=$2"
        echo "LAST_UPDATE_OK=$3"
        echo "FAILED_STAGES=$4"
    } > "$HOME/.ai-docker/update-status"
}

run_cli() {
    set +e
    RUN_OUTPUT=$(bash "$ROOT_DIR/docker/ai_docker.sh" "$@" 2>&1)
    RUN_RC=$?
    set -u
}

# --- brief (login banner) ----------------------------------------------------

setup_case
write_status updated "$(days_ago 2)" "$(days_ago 2)" ""
run_cli status --brief
assert_eq "healthy brief exits 0" 0 "$RUN_RC"
assert_eq "brief is a single line" 1 "$(printf '%s\n' "$RUN_OUTPUT" | wc -l)"
assert_contains "healthy brief says tools are OK" "$RUN_OUTPUT" "tools OK"
assert_contains "healthy brief shows update check age" "$RUN_OUTPUT" "updates checked 2 days ago"
assert_contains "brief shows image version" "$RUN_OUTPUT" "1.6.0"
assert_not_contains "healthy brief raises no attention flag" "$RUN_OUTPUT" "ATTENTION"
if [ -e "$TOOL_CALLS" ]; then fail "brief never runs the tools"; else pass "brief never runs the tools"; fi

setup_case
write_status failed "$(days_ago 1)" "$(days_ago 9)" "pip" "$(days_ago 1)"
run_cli status --brief
assert_eq "failed update makes brief exit 1" 1 "$RUN_RC"
assert_contains "failed update is flagged" "$RUN_OUTPUT" "ATTENTION"
assert_contains "failed stage is named" "$RUN_OUTPUT" "last update failed (pip)"
assert_contains "brief points to details" "$RUN_OUTPUT" "ai-docker status"

setup_case
write_status check_failed "" "" "check" "$(days_ago 0)"
run_cli status --brief
assert_contains "failed check is flagged" "$RUN_OUTPUT" "last update check failed"

setup_case
write_status up_to_date "$(days_ago 14)" "" ""
run_cli status --brief
assert_eq "stale checks make brief exit 1" 1 "$RUN_RC"
assert_contains "stale checks are flagged with their age" "$RUN_OUTPUT" "no successful update check for 14 days"

setup_case
run_cli status --brief
assert_eq "fresh container without status is not an error" 0 "$RUN_RC"
assert_contains "fresh container says the check is pending" "$RUN_OUTPUT" "update check pending"

setup_case
write_status updated "$(days_ago 1)" "$(days_ago 1)" ""
printf 'STATUS=partial\nFAILED_TOOLS=claude gh\n' > "$HOME/.cli_tools_installed"
run_cli status --brief
assert_eq "partial install makes brief exit 1" 1 "$RUN_RC"
assert_contains "failed tools are named" "$RUN_OUTPUT" "tools failed to install: claude gh"

setup_case
write_status updated "$(days_ago 1)" "$(days_ago 1)" ""
export AI_DOCKER_DISK_WARN_GB=0
run_cli status --brief
assert_contains "disk over threshold is flagged" "$RUN_OUTPUT" "Docker disk"
assert_eq "disk over threshold makes brief exit 1" 1 "$RUN_RC"

# --- full status ---------------------------------------------------------------

setup_case
write_status failed "$(days_ago 1)" "$(days_ago 9)" "pip" "$(days_ago 1)"
mkdir -p "$AI_DOCKER_TMP_DIR/claude-$(id -u)/session/scratchpad"
head -c 2048 /dev/zero > "$AI_DOCKER_TMP_DIR/claude-$(id -u)/session/scratchpad/blob"
run_cli status
assert_eq "full status with a failure exits 1" 1 "$RUN_RC"
assert_contains "full status shows memory limit" "$RUN_OUTPUT" "memory limit 10.0 GB"
assert_contains "full status shows CPU limit" "$RUN_OUTPUT" "6 CPUs"
assert_contains "full status shows live tool versions" "$RUN_OUTPUT" "codex 9.9.9"
assert_contains "full status shows the last result" "$RUN_OUTPUT" "last result: failed"
assert_contains "full status shows the failed stage" "$RUN_OUTPUT" "failed stages: pip"
assert_contains "full status reports scratch dirs" "$RUN_OUTPUT" "Claude scratch dirs"
assert_contains "disk figures are labelled as estimates" "$RUN_OUTPUT" "estimate"
assert_contains "full status suggests a fix for the failure" "$RUN_OUTPUT" "update-container-tools"
assert_contains "full status points to doctor for network checks" "$RUN_OUTPUT" "ai-docker doctor"

# An unreadable folder still yields a (partial) size, not a bogus timeout.
setup_case
mkdir -p "$AI_DOCKER_TMP_DIR/locked/inner" "$AI_DOCKER_TMP_DIR/open"
head -c 4096 /dev/zero > "$AI_DOCKER_TMP_DIR/open/blob"
chmod 000 "$AI_DOCKER_TMP_DIR/locked"
run_cli status
chmod 755 "$AI_DOCKER_TMP_DIR/locked"
if [ "$(id -u)" -ne 0 ]; then
    assert_contains "unreadable folders mark the size as partial" "$RUN_OUTPUT" "(partial)"
fi
assert_not_contains "permission errors are not reported as a timeout" "$RUN_OUTPUT" "over time limit"

setup_case
printf 'max\n' > "$AI_DOCKER_CGROUP_DIR/memory.max"
printf 'max 100000\n' > "$AI_DOCKER_CGROUP_DIR/cpu.max"
run_cli status
assert_contains "unlimited memory is reported as such" "$RUN_OUTPUT" "memory limit none"
assert_contains "unlimited CPU is reported as such" "$RUN_OUTPUT" "CPU limit none"

setup_case
run_cli --help
assert_eq "help exits 0" 0 "$RUN_RC"
assert_contains "help lists status" "$RUN_OUTPUT" "status"
run_cli bogus
assert_eq "unknown command exits 2" 2 "$RUN_RC"

# Review regression: an interrupted update is flagged; a running one is not.
setup_case
write_status running "$(days_ago 1)" "$(days_ago 1)" ""
run_cli status --brief
assert_eq "interrupted update needs attention" 1 "$RUN_RC"
assert_contains "interrupted update is named" "$RUN_OUTPUT" "last update was interrupted"
( flock 9; sleep 3 ) 9> "$HOME/.ai-docker/update.lock" &
holder=$!; sleep 0.5
run_cli status --brief
wait "$holder"
assert_eq "update in progress is not an error" 0 "$RUN_RC"
assert_contains "update in progress is shown" "$RUN_OUTPUT" "update running"

# Review regression: a broken installed tool makes full status unhealthy.
setup_case
write_status updated "$(days_ago 1)" "$(days_ago 1)" ""
printf 'STATUS=ok\nFAILED_TOOLS=\nTOOL_codex=ok\n' > "$HOME/.cli_tools_installed"
printf '#!/usr/bin/env bash\nexit 1\n' > "$CASE_DIR/bin/codex"
run_cli status
assert_eq "broken installed tool fails full status" 1 "$RUN_RC"
assert_contains "broken tool is named" "$RUN_OUTPUT" "codex is installed but not working"
assert_not_contains "no healthy verdict with a broken tool" "$RUN_OUTPUT" "Everything looks healthy"

# Review regression: update records must survive a container recreate.
compose="$ROOT_DIR/docker/docker-compose.yml"
if grep -Eq '^[[:space:]]*- ai-docker-state:/home/\$\{USER_NAME\}/\.ai-docker[[:space:]]*$' "$compose"; then
    pass "update records live on a named volume"
else
    fail "update records live on a named volume"
fi
grep -Eq '^  ai-docker-state:' "$compose" && pass "state volume is declared" || fail "state volume is declared"
grep -Fq "'ai-docker-state'" "$ROOT_DIR/scripts/uninstall.ps1" && pass "uninstall -RemoveVolumes knows the state volume" || fail "uninstall -RemoveVolumes knows the state volume"
grep -Fq 'own_tree "/home/$USER_NAME/.ai-docker"' "$ROOT_DIR/docker/entrypoint.sh" && pass "entrypoint hands the state volume to the user" || fail "entrypoint hands the state volume to the user"

printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
