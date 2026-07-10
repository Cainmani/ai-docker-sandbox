#!/usr/bin/env bash
set -u

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
PASS=0
FAIL=0
trap 'rm -rf "$TMP_DIR"' EXIT

pass() { printf 'ok - %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'not ok - %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
assert_eq() { local l=$1 e=$2 a=$3; if [ "$e" = "$a" ]; then pass "$l"; else fail "$l (expected $e, got $a)"; fi; }
assert_file_contains() { local l=$1 f=$2 n=$3; if grep -Fq -- "$n" "$f" 2>/dev/null; then pass "$l"; else fail "$l"; fi; }
assert_log_contains() { assert_file_contains "$1" "$FAKE_LOG" "$2"; }
assert_log_not_contains() { local l=$1 n=$2; if grep -Fq -- "$n" "$FAKE_LOG"; then fail "$l"; else pass "$l"; fi; }

make_tool() {
    local name=$1
    cat > "$CASE_DIR/bin/$name" <<SCRIPT
#!/usr/bin/env bash
printf '$name %s\\n' "\$*" >> "\$FAKE_LOG"
if [ "\${1:-}" = --version ]; then printf '$name 1.0.0\\n'; fi
exit 0
SCRIPT
    chmod +x "$CASE_DIR/bin/$name"
}

setup_case() {
    CASE_DIR=$(mktemp -d "$TMP_DIR/case.XXXXXX")
    export HOME="$CASE_DIR/home"
    export FAKE_LOG="$CASE_DIR/commands.log"
    export CLAUDE_INSTALL_RESULT=success
    mkdir -p "$HOME/.npm-global/bin" "$HOME/.local/bin" "$CASE_DIR/bin"
    : > "$FAKE_LOG"

    for tool in gh codex gemini node python3; do make_tool "$tool"; done

    cat > "$CASE_DIR/bin/npm" <<'SCRIPT'
#!/usr/bin/env bash
printf 'npm %s\n' "$*" >> "$FAKE_LOG"
case " $* " in
    *' --version '*) printf '10.0.0\n' ;;
    *' list -g --depth=0 '*) printf '/fake\n' ;;
    *' list -g vibe-kanban '*) printf 'vibe-kanban@1.0.0\n' ;;
    *' list -g 9router '*) printf '9router@1.0.0\n' ;;
    *' list -g omniroute '*) printf 'omniroute@1.0.0\n' ;;
    *' view '*) printf '1.0.0\n' ;;
    *' install -g '*) exit 0 ;;
    *' uninstall -g '*) exit 0 ;;
esac
exit 0
SCRIPT

    cat > "$CASE_DIR/bin/pip3" <<'SCRIPT'
#!/usr/bin/env bash
printf 'pip3 %s\n' "$*" >> "$FAKE_LOG"
if [ "${1:-}" = show ]; then exit 0; fi
exit 0
SCRIPT

    cat > "$CASE_DIR/bin/sudo" <<'SCRIPT'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "$FAKE_LOG"
exit 0
SCRIPT

    cat > "$CASE_DIR/bin/curl" <<'SCRIPT'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >> "$FAKE_LOG"
out=''
prev=''
for arg in "$@"; do
    if [ "$prev" = -o ]; then out=$arg; fi
    prev=$arg
done
case " $* " in
    *'https://claude.ai/install.sh'*)
        if [ "$CLAUDE_INSTALL_RESULT" = download-fail ]; then exit 22; fi
        if [ "$CLAUDE_INSTALL_RESULT" = invalid ]; then
            printf '#!/usr/bin/env bash\nmkdir -p "$HOME/.local/bin"\nprintf "#!/usr/bin/env bash\\nexit 1\\n" > "$HOME/.local/bin/claude"\nchmod +x "$HOME/.local/bin/claude"\n' > "$out"
        else
            printf '#!/usr/bin/env bash\nmkdir -p "$HOME/.local/bin"\nprintf "#!/usr/bin/env bash\\necho claude-native-2.0.0\\n" > "$HOME/.local/bin/claude"\nchmod +x "$HOME/.local/bin/claude"\n' > "$out"
        fi
        ;;
    *) : > "$out" ;;
esac
exit 0
SCRIPT
    chmod +x "$CASE_DIR/bin/"*
    export PATH="$CASE_DIR/bin:$HOME/.npm-global/bin:/usr/bin:/bin"
}

make_old_claude() {
    cat > "$HOME/.npm-global/bin/claude" <<'SCRIPT'
#!/usr/bin/env bash
echo claude-old-1.0.0
SCRIPT
    chmod +x "$HOME/.npm-global/bin/claude"
}

run_installer() {
    set +e
    RUN_OUTPUT=$(bash "$ROOT_DIR/docker/install_cli_tools.sh" "$@" 2>&1)
    RUN_RC=$?
    set -e
}

setup_case
make_old_claude
run_installer --repair
assert_eq "repair succeeds when required tools are healthy" 0 "$RUN_RC"
assert_log_not_contains "repair does not reinstall healthy npm tools" "npm install -g"
assert_log_not_contains "repair does not invoke the Claude installer" "https://claude.ai/install.sh"
assert_log_not_contains "repair does not reinstall healthy GitHub CLI" "apt-get install gh"
assert_file_contains "repair writes a healthy structured marker" "$HOME/.cli_tools_installed" "STATUS=ok"

setup_case
make_old_claude
export CLAUDE_INSTALL_RESULT=download-fail
run_installer --force
assert_eq "force retains success when the previous required Claude remains healthy" 0 "$RUN_RC"
if "$HOME/.npm-global/bin/claude" --version >/dev/null 2>&1; then pass "failed force replacement preserves old Claude"; else fail "failed force replacement preserves old Claude"; fi
assert_log_not_contains "failed native replacement does not uninstall old npm Claude" "npm uninstall -g @anthropic-ai/claude-code"
assert_file_contains "preserved Claude is recorded healthy" "$HOME/.cli_tools_installed" "TOOL_claude=ok"

setup_case
make_old_claude
export CLAUDE_INSTALL_RESULT=invalid
run_installer --force
assert_eq "invalid native replacement keeps a working required fallback" 0 "$RUN_RC"
if "$HOME/.npm-global/bin/claude" --version >/dev/null 2>&1; then pass "native validation failure preserves old Claude executable"; else fail "native validation failure preserves old Claude executable"; fi
assert_file_contains "native validation failure is surfaced" <(printf '%s\n' "$RUN_OUTPUT") "failed validation"

setup_case
rm -f "$CASE_DIR/bin/claude" "$HOME/.npm-global/bin/claude"
export CLAUDE_INSTALL_RESULT=download-fail
run_installer --repair
assert_eq "missing required tool produces nonzero exit" 1 "$RUN_RC"
assert_file_contains "required failure writes partial status" "$HOME/.cli_tools_installed" "STATUS=partial"
assert_file_contains "required failure names Claude" "$HOME/.cli_tools_installed" "FAILED_TOOLS=claude"
assert_file_contains "required failure writes per-tool failure" "$HOME/.cli_tools_installed" "TOOL_claude=failed"

printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
