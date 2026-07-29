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
    *' update -g '*) printf 'simulated npm update\n'; exit "$FAKE_NPM_UPDATE_RC" ;;
    *' install -g '*) exit "$FAKE_NPM_INSTALL_RC" ;;
    *' cache clean --force '*) exit 0 ;;
    *) exit 0 ;;
esac
SCRIPT

    cat > "$CASE_DIR/bin/pip3" <<'SCRIPT'
#!/usr/bin/env bash
printf 'pip3 %s\n' "$*" >> "$FAKE_LOG"
if [ "${1:-}" = list ]; then
    printf '%s\n' "$FAKE_PIP_OUTDATED_OUTPUT"
    exit "$FAKE_PIP_CHECK_RC"
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

printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
