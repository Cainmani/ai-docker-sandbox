#!/usr/bin/env bash
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
    if printf '%s\n' "$haystack" | grep -Fq -- "$needle"; then pass "$label"; else fail "$label"; fi
}
assert_log_contains() {
    local label=$1 needle=$2
    if grep -Fq -- "$needle" "$FAKE_LOG"; then pass "$label"; else fail "$label"; fi
}
assert_log_not_contains() {
    local label=$1 needle=$2
    if grep -Fq -- "$needle" "$FAKE_LOG"; then fail "$label"; else pass "$label"; fi
}

setup_case() {
    CASE_DIR=$(mktemp -d "$TMP_DIR/case.XXXXXX")
    export HOME="$CASE_DIR/home"
    export FAKE_LOG="$CASE_DIR/commands.log"
    export FAKE_STATE="$CASE_DIR/state"
    export FAKE_NPM_OUTDATED_RC=0
    export FAKE_NPM_OUTDATED_OUTPUT=''
    export FAKE_PIP_CHECK_RC=0
    export FAKE_PIP_OUTDATED_OUTPUT=$'Package Version Latest Type\n------- ------- ------ ----'
    export FAKE_PIP_OUTDATED_JSON='[]'
    export FAKE_PIP_INSTALL_RC=0
    export FAKE_APT_UPDATE_RC=0
    export FAKE_APT_LIST_OUTPUT=''
    export FAKE_NPM_UPDATE_RC=0
    export FAKE_NPM_BEFORE=''
    export FAKE_NPM_AFTER=''
    export FAKE_NPM_INSTALL_RC=0
    export FAKE_APT_UPGRADE_RC=0
    export FAKE_NPM_ROOT=''
    mkdir -p "$HOME" "$CASE_DIR/bin"
    : > "$FAKE_LOG"
    export AI_MAINTENANCE_PROC_ROOT="$CASE_DIR/proc"
    mkdir -p "$AI_MAINTENANCE_PROC_ROOT"

    cat > "$CASE_DIR/bin/npm" <<'SCRIPT'
#!/usr/bin/env bash
printf 'npm %s\n' "$*" >> "$FAKE_LOG"
case " $* " in
    *' config set prefix '*) exit 0 ;;
    *' root -g '*) printf '%s\n' "$FAKE_NPM_ROOT"; exit 0 ;;
    *' outdated -g '*) printf '%s\n' "$FAKE_NPM_OUTDATED_OUTPUT"; exit "$FAKE_NPM_OUTDATED_RC" ;;
    *' ls -g --depth=0 --parseable '*)
        count_file="$FAKE_STATE.ls-count"
        count=$(cat "$count_file" 2>/dev/null || printf 0)
        count=$((count + 1)); printf '%s' "$count" > "$count_file"
        printf '/fake/lib\n'
        if [ "$count" -eq 1 ]; then printf '%s\n' "$FAKE_NPM_BEFORE"; else printf '%s\n' "$FAKE_NPM_AFTER"; fi
        exit 0
        ;;
    *' update -g '*)
        [ -n "${FAKE_NPM_UPDATE_SLEEP:-}" ] && sleep "$FAKE_NPM_UPDATE_SLEEP"
        # Optionally simulate the update changing (or breaking) a tool.
        [ -n "${FAKE_CODEX_AFTER_VERSION:-}" ] && printf '%s' "$FAKE_CODEX_AFTER_VERSION" > "$FAKE_STATE.codex-version"
        [ -n "${FAKE_CODEX_AFTER_RC:-}" ] && printf '%s' "$FAKE_CODEX_AFTER_RC" > "$FAKE_STATE.codex-rc"
        printf 'simulated npm update\n'; exit "$FAKE_NPM_UPDATE_RC" ;;
    *' install -g '*) exit "$FAKE_NPM_INSTALL_RC" ;;
    *' cache clean --force '*) exit 0 ;;
    *) exit 0 ;;
esac
SCRIPT

    # Faithful to real pip: `--outdated` cannot be combined with `--format=freeze`.
    cat > "$CASE_DIR/bin/pip3" <<'SCRIPT'
#!/usr/bin/env bash
printf 'pip3 %s\n' "$*" >> "$FAKE_LOG"
if [ "${1:-}" = list ]; then
    case " $* " in
        *' --outdated '*'--format=freeze '*|*' --format=freeze '*'--outdated '*)
            echo "ERROR: List format 'freeze' cannot be used with the --outdated option." >&2
            exit 1 ;;
        *' --format=json '*)
            [ "$FAKE_PIP_CHECK_RC" -eq 0 ] || exit "$FAKE_PIP_CHECK_RC"
            printf '%s\n' "$FAKE_PIP_OUTDATED_JSON"; exit 0 ;;
    esac
    printf '%s\n' "$FAKE_PIP_OUTDATED_OUTPUT"
    exit "$FAKE_PIP_CHECK_RC"
fi
if [ "${1:-}" = install ]; then
    # Ubuntu 24.04 (PEP 668) refuses user installs without this flag.
    case " $* " in
        *' --break-system-packages '*) ;;
        *) echo "error: externally-managed-environment" >&2; exit 1 ;;
    esac
    exit "$FAKE_PIP_INSTALL_RC"
fi
exit 0
SCRIPT

    cat > "$CASE_DIR/bin/sudo" <<'SCRIPT'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "$FAKE_LOG"
if [ "${1:-}" = apt-get ] && [ "${2:-}" = update ]; then exit "$FAKE_APT_UPDATE_RC"; fi
if [ "${1:-}" = apt-get ] && [ "${2:-}" = upgrade ]; then exit "$FAKE_APT_UPGRADE_RC"; fi
exit 0
SCRIPT

    cat > "$CASE_DIR/bin/apt" <<'SCRIPT'
#!/usr/bin/env bash
printf 'apt %s\n' "$*" >> "$FAKE_LOG"
printf '%s\n' "$FAKE_APT_LIST_OUTPUT"
SCRIPT

    cat > "$CASE_DIR/bin/chown" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
    chmod +x "$CASE_DIR/bin/"*
    export PATH="$CASE_DIR/bin:/usr/bin:/bin"
}

run_updater() {
    set +e
    RUN_OUTPUT=$(bash "$ROOT_DIR/docker/auto_update.sh" "$@" 2>&1)
    RUN_RC=$?
    set -e
}

setup_case
export FAKE_NPM_OUTDATED_RC=1
export FAKE_NPM_OUTDATED_OUTPUT=$'Package Current Wanted Latest Location\nvibe-kanban 1.0.0 1.1.0 1.1.0 global'
run_updater --check
assert_eq "available updates produce a successful --check result" 0 "$RUN_RC"
assert_contains "available updates are reported" "$RUN_OUTPUT" "Updates are available"

setup_case
run_updater --check
assert_eq "no updates is not a command failure" 0 "$RUN_RC"
assert_contains "no updates is reported distinctly" "$RUN_OUTPUT" "No updates available"

setup_case
export FAKE_NPM_OUTDATED_RC=2
run_updater --check
assert_eq "registry failure has distinct check status" 2 "$RUN_RC"
assert_contains "registry failure is reported" "$RUN_OUTPUT" "Update check FAILED"

setup_case
export FAKE_NPM_OUTDATED_RC=2
run_updater --force
assert_eq "forced failed check returns failure" 1 "$RUN_RC"
assert_log_not_contains "--force does not apply updates after a failed check" "npm update -g"

setup_case
export FAKE_NPM_UPDATE_RC=1
export FAKE_NPM_BEFORE='/fake/lib/node_modules/vibe-kanban'
export FAKE_NPM_AFTER=''
run_updater --apply
assert_eq "partial apply returns failure" 1 "$RUN_RC"
assert_log_contains "package removed by failed npm update is reinstalled" "npm install -g vibe-kanban"
assert_contains "partial apply does not print a success summary" "$RUN_OUTPUT" "Updates completed WITH ERRORS"
if printf '%s\n' "$RUN_OUTPUT" | grep -Fq 'Updates completed successfully'; then
    fail "partial apply suppresses success summary"
else
    pass "partial apply suppresses success summary"
fi

# Orphaned staging directories from an interrupted install are swept before the
# npm update, so a leftover ".<pkg>-<hash>" can no longer abort the whole run.
setup_case
FAKE_NPM_ROOT="$CASE_DIR/node_modules"
export FAKE_NPM_ROOT
mkdir -p \
    "$FAKE_NPM_ROOT/.9router-wciiY0Kj" \
    "$FAKE_NPM_ROOT/@google/.gemini-cli-yRHhsjle" \
    "$FAKE_NPM_ROOT/@google/gemini-cli" \
    "$FAKE_NPM_ROOT/vibe-kanban" \
    "$FAKE_NPM_ROOT/.bin"
: > "$FAKE_NPM_ROOT/.package-lock.json"
run_updater --apply
assert_eq "apply with only staging orphans succeeds" 0 "$RUN_RC"
if [ -e "$FAKE_NPM_ROOT/.9router-wciiY0Kj" ]; then fail "unscoped staging orphan removed"; else pass "unscoped staging orphan removed"; fi
if [ -e "$FAKE_NPM_ROOT/@google/.gemini-cli-yRHhsjle" ]; then fail "scoped staging orphan removed"; else pass "scoped staging orphan removed"; fi
if [ -e "$FAKE_NPM_ROOT/@google/gemini-cli" ]; then pass "real scoped package kept"; else fail "real scoped package kept"; fi
if [ -e "$FAKE_NPM_ROOT/vibe-kanban" ]; then pass "real package kept"; else fail "real package kept"; fi
if [ -e "$FAKE_NPM_ROOT/.bin" ]; then pass ".bin kept"; else fail ".bin kept"; fi
if [ -e "$FAKE_NPM_ROOT/.package-lock.json" ]; then pass ".package-lock.json kept"; else fail ".package-lock.json kept"; fi
assert_contains "cleanup is reported" "$RUN_OUTPUT" "staging directories from interrupted installs"

# --- #87: honest status --------------------------------------------------------

status_get() { sed -n "s/^$1=//p" "$HOME/.ai-docker/update-status" 2>/dev/null | head -n1; }

# A fake codex whose version and health come from state files, so a test can
# make the npm update change or break it.
add_fake_codex() {
    printf '%s' "${1:-codex-cli 1.0.0}" > "$FAKE_STATE.codex-version"
    printf '0' > "$FAKE_STATE.codex-rc"
    cat > "$CASE_DIR/bin/codex" <<'SCRIPT'
#!/usr/bin/env bash
rc=$(cat "$FAKE_STATE.codex-rc"); [ "$rc" -eq 0 ] || exit "$rc"
cat "$FAKE_STATE.codex-version"; echo
SCRIPT
    chmod +x "$CASE_DIR/bin/codex"
}

# Outdated pip packages found by the check are actually upgraded on apply
# (previously `--outdated --format=freeze` errored silently -> "up to date").
setup_case
export FAKE_PIP_OUTDATED_JSON='[{"name": "openai", "version": "2.44.0", "latest_version": "2.50.0"}]'
run_updater --apply
assert_log_contains "outdated pip package is upgraded" "openai"
assert_eq "pip upgrade succeeds on a PEP 668 system" 0 "$RUN_RC"
assert_log_not_contains "pip is never asked for the unsupported freeze+outdated combination" "--format=freeze"

# A failing pip listing during apply is an error, not "all up to date".
setup_case
export FAKE_PIP_CHECK_RC=1
run_updater --apply
assert_eq "pip listing failure fails the apply" 1 "$RUN_RC"
if printf '%s\n' "$RUN_OUTPUT" | grep -Fq 'All Python packages are up to date'; then
    fail "pip listing failure is not reported as up to date"
else
    pass "pip listing failure is not reported as up to date"
fi
assert_contains "failed stage recorded for pip" "$(status_get FAILED_STAGES)" "pip"

# The status record distinguishes a check that found nothing from an applied update.
setup_case
run_updater --force
assert_eq "up-to-date run succeeds" 0 "$RUN_RC"
assert_eq "up-to-date run recorded as such" "up_to_date" "$(status_get RESULT)"
[ -n "$(status_get LAST_ATTEMPT)" ] && pass "attempt time recorded" || fail "attempt time recorded"
[ -n "$(status_get LAST_CHECK_OK)" ] && pass "successful check time recorded" || fail "successful check time recorded"
assert_eq "no update recorded when nothing was applied" "" "$(status_get LAST_UPDATE_OK)"

setup_case
export FAKE_NPM_OUTDATED_RC=1
export FAKE_NPM_OUTDATED_OUTPUT=$'Package Current Wanted Latest Location\nvibe-kanban 1.0.0 1.1.0 1.1.0 global'
export FAKE_NPM_BEFORE='/fake/lib/node_modules/vibe-kanban'
export FAKE_NPM_AFTER='/fake/lib/node_modules/vibe-kanban'
run_updater --force
assert_eq "applied update recorded" "updated" "$(status_get RESULT)"
[ -n "$(status_get LAST_UPDATE_OK)" ] && pass "update time recorded" || fail "update time recorded"

setup_case
export FAKE_NPM_OUTDATED_RC=1
export FAKE_NPM_OUTDATED_OUTPUT=$'Package Current Wanted Latest Location\nvibe-kanban 1.0.0 1.1.0 1.1.0 global'
export FAKE_NPM_UPDATE_RC=1
export FAKE_NPM_BEFORE='/fake/lib/node_modules/vibe-kanban'
export FAKE_NPM_AFTER='/fake/lib/node_modules/vibe-kanban'
run_updater --force
assert_eq "failed update recorded" "failed" "$(status_get RESULT)"
assert_contains "failed stage recorded for npm" "$(status_get FAILED_STAGES)" "npm"

setup_case
export FAKE_NPM_OUTDATED_RC=2
run_updater --force
assert_eq "failed check recorded" "check_failed" "$(status_get RESULT)"
assert_eq "failed check keeps no successful check time" "" "$(status_get LAST_CHECK_OK)"

# Only one updater runs at a time; a second invocation backs off cleanly.
setup_case
mkdir -p "$HOME/.ai-docker"
( flock 9; sleep 3 ) 9> "$HOME/.ai-docker/update.lock" &
holder=$!
sleep 0.5
run_updater --force
wait "$holder"
assert_eq "concurrent run reports busy" 75 "$RUN_RC"
assert_contains "concurrent run says it is already running" "$RUN_OUTPUT" "LOCK=busy"
assert_log_not_contains "concurrent run does not touch npm" "npm outdated -g"

assert_contains "busy skip has a durable separate status" "$(cat "$HOME/.ai-docker/update-skipped")" "RESULT=skipped_busy"
assert_eq "busy skip does not mark a successful scheduled check" false "$(test -f "$HOME/.last_update_check" && echo true || echo false)"

# The entrypoint and old cron lines invoke the updater without arguments.
setup_case
run_updater
assert_eq "bare updater runs its normal check" 0 "$RUN_RC"
assert_eq "bare updater records checked state" up_to_date "$(status_get RESULT)"
run_updater
assert_eq "bare updater honours the interval" 0 "$RUN_RC"

# A long-lived visible CLI blocks the old default path without npm mutation.
setup_case
mkdir -p "$AI_MAINTENANCE_PROC_ROOT/123" "$HOME/.ai-docker"
printf 'codex\0app-server\0' > "$AI_MAINTENANCE_PROC_ROOT/123/cmdline"
printf 'RESULT=running\nLAST_CHECK_OK=previous-success\n' > "$HOME/.ai-docker/update-status"
run_updater
assert_eq "bare updater skips a long-running process" 75 "$RUN_RC"
assert_eq "busy skip preserves another updater status" running "$(status_get RESULT)"
assert_eq "busy skip preserves the last successful check" previous-success "$(status_get LAST_CHECK_OK)"
assert_log_not_contains "busy default invocation performs no npm config" "npm config"
rm "$AI_MAINTENANCE_PROC_ROOT/123/cmdline"
run_updater --scheduled
assert_eq "scheduled updater runs once the process exits" 0 "$RUN_RC"

# Scheduled retry admits after a transient holder exits instead of failing.
setup_case
mkdir -p "$HOME/.ai-docker"
( flock 9; sleep 2 ) 9> "$HOME/.ai-docker/update.lock" &
holder=$!
sleep 0.2
run_updater --scheduled
wait "$holder"
assert_eq "scheduled trigger retries a transient busy lock" 0 "$RUN_RC"

# Versions are snapshotted before/after, and a tool broken by the update is caught.
setup_case
add_fake_codex "codex-cli 1.0.0"
export FAKE_CODEX_AFTER_VERSION="codex-cli 1.1.0"
export FAKE_NPM_BEFORE='/fake/lib/node_modules/@openai/codex'
export FAKE_NPM_AFTER='/fake/lib/node_modules/@openai/codex'
run_updater --apply
assert_eq "healthy tool update succeeds" 0 "$RUN_RC"
assert_contains "version before is recorded" "$(cat "$HOME/.ai-docker/versions-before" 2>/dev/null)" "codex	codex-cli 1.0.0"
assert_contains "version after is recorded" "$(cat "$HOME/.ai-docker/versions-after" 2>/dev/null)" "codex	codex-cli 1.1.0"

setup_case
add_fake_codex "codex-cli 1.0.0"
export FAKE_CODEX_AFTER_RC=127
export FAKE_NPM_BEFORE='/fake/lib/node_modules/@openai/codex'
export FAKE_NPM_AFTER='/fake/lib/node_modules/@openai/codex'
run_updater --apply
assert_eq "tool broken by update fails the apply" 1 "$RUN_RC"
assert_contains "verify stage recorded" "$(status_get FAILED_STAGES)" "verify"
assert_contains "broken tool is named" "$RUN_OUTPUT" "codex no longer runs"

# Pinned packages are excluded from the npm update instead of updated then restored.
setup_case
printf '9router@0.5.40\n' > "$HOME/.npm-pinned-tools"
export PINNED_TOOLS_FILE="$HOME/.npm-pinned-tools"
export FAKE_NPM_BEFORE=$'/fake/lib/node_modules/9router\n/fake/lib/node_modules/vibe-kanban'
export FAKE_NPM_AFTER="$FAKE_NPM_BEFORE"
run_updater --apply
assert_log_contains "unpinned package is updated" "npm update -g vibe-kanban"
if grep -E '^npm update -g' "$FAKE_LOG" | grep -Fq '9router'; then
    fail "pinned package is excluded from npm update"
else
    pass "pinned package is excluded from npm update"
fi
unset PINNED_TOOLS_FILE

# Review regression: a failed check stage is not erased by a later success.
setup_case
export FAKE_APT_UPDATE_RC=1
export FAKE_NPM_OUTDATED_RC=1
export FAKE_NPM_OUTDATED_OUTPUT=$'Package Current Wanted Latest Location\nvibe-kanban 1.0.0 1.1.0 1.1.0 global'
export FAKE_NPM_BEFORE='/fake/lib/node_modules/vibe-kanban'
export FAKE_NPM_AFTER='/fake/lib/node_modules/vibe-kanban'
run_updater --force
assert_eq "check failure + successful apply is not 'updated'" "failed" "$(status_get RESULT)"
assert_contains "failed check stage is recorded" "$(status_get FAILED_STAGES)" "check-apt"
assert_eq "partial run exits non-zero" 1 "$RUN_RC"

# Review regression: an interrupted run leaves a trace instead of the old record.
setup_case
mkdir -p "$HOME/.ai-docker"
printf 'RESULT=updated\nLAST_ATTEMPT=2026-01-01T00:00:00+00:00\nLAST_CHECK_OK=2026-01-01T00:00:00+00:00\nLAST_UPDATE_OK=2026-01-01T00:00:00+00:00\nFAILED_STAGES=\n' > "$HOME/.ai-docker/update-status"
export FAKE_NPM_BEFORE='/fake/lib/node_modules/vibe-kanban'
export FAKE_NPM_AFTER='/fake/lib/node_modules/vibe-kanban'
export FAKE_NPM_UPDATE_SLEEP=5
bash "$ROOT_DIR/docker/auto_update.sh" --apply > /dev/null 2>&1 &
updater=$!
sleep 1.5
pkill -9 -P "$updater" 2>/dev/null || true; kill -9 "$updater" 2>/dev/null || true; wait "$updater" 2>/dev/null || true
unset FAKE_NPM_UPDATE_SLEEP
assert_eq "interrupted run is visible" "running" "$(status_get RESULT)"
assert_contains "interrupted run records its attempt time" "$(status_get LAST_ATTEMPT)" "$(date +%Y-%m-%d)"
assert_eq "interrupted run keeps the last good check" "2026-01-01T00:00:00+00:00" "$(status_get LAST_CHECK_OK)"

# Second review 6: real npm reports an unreachable registry as exit 1 with no
# output - the same exit code as "updates available". That is a failed check.
setup_case
mkdir -p "$HOME/.ai-docker"
printf 'RESULT=up_to_date\nLAST_ATTEMPT=2026-01-01T00:00:00+00:00\nLAST_CHECK_OK=2026-01-01T00:00:00+00:00\nLAST_UPDATE_OK=\nFAILED_STAGES=\n' > "$HOME/.ai-docker/update-status"
export FAKE_NPM_OUTDATED_RC=1
export FAKE_NPM_OUTDATED_OUTPUT=''
run_updater --force
assert_eq "npm exit 1 with no output fails the run" 1 "$RUN_RC"
assert_eq "npm exit 1 with no output is a failed check" "check_failed" "$(status_get RESULT)"
assert_contains "npm check stage recorded" "$(status_get FAILED_STAGES)" "check-npm"
assert_eq "failed npm check keeps the last good check time" "2026-01-01T00:00:00+00:00" "$(status_get LAST_CHECK_OK)"
[ ! -e "$HOME/.last_update_check" ] && pass "failed check does not postpone the next attempt" || fail "failed check does not postpone the next attempt"

# Second review 9: a failed check stage must not advance "last successful check",
# even when other updates were applied.
setup_case
mkdir -p "$HOME/.ai-docker"
printf 'RESULT=updated\nLAST_ATTEMPT=2026-01-01T00:00:00+00:00\nLAST_CHECK_OK=2026-01-01T00:00:00+00:00\nLAST_UPDATE_OK=2026-01-01T00:00:00+00:00\nFAILED_STAGES=\n' > "$HOME/.ai-docker/update-status"
export FAKE_APT_UPDATE_RC=1
export FAKE_NPM_OUTDATED_RC=1
export FAKE_NPM_OUTDATED_OUTPUT=$'Package Current Wanted Latest Location\nvibe-kanban 1.0.0 1.1.0 1.1.0 global'
export FAKE_NPM_BEFORE='/fake/lib/node_modules/vibe-kanban'
export FAKE_NPM_AFTER='/fake/lib/node_modules/vibe-kanban'
run_updater --force
assert_eq "partial check is a failed run" "failed" "$(status_get RESULT)"
assert_eq "failed check stage keeps the previous successful check time" "2026-01-01T00:00:00+00:00" "$(status_get LAST_CHECK_OK)"

printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
