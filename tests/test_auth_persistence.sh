#!/usr/bin/env bash
# Test auth persistence symlink logic from entrypoint.sh
# Runs entirely in a temp directory — no Docker required.
set -euo pipefail

PASS=0
FAIL=0
TEST_DIR=""

setup() {
    TEST_DIR=$(mktemp -d)
    export HOME="$TEST_DIR/home/testuser"
    mkdir -p "$HOME"
    mkdir -p "$HOME/.claude"
    mkdir -p "$HOME/.tool-auth"
    mkdir -p "$HOME/.config"
}

teardown() {
    rm -rf "$TEST_DIR"
}

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected='$expected', actual='$actual')"
        FAIL=$((FAIL + 1))
    fi
}

assert_symlink() {
    local desc="$1" path="$2" target="$3"
    if [ -L "$path" ]; then
        local actual_target
        actual_target=$(readlink "$path")
        if [ "$actual_target" = "$target" ]; then
            echo "  PASS: $desc"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: $desc (symlink points to '$actual_target', expected '$target')"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "  FAIL: $desc (not a symlink)"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_contains() {
    local desc="$1" path="$2" content="$3"
    if [ -f "$path" ] && grep -qF "$content" "$path"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (file missing or doesn't contain '$content')"
        FAIL=$((FAIL + 1))
    fi
}

# ---------- Extract and run the symlink logic from entrypoint.sh ----------
# This replicates the entrypoint logic using $HOME instead of /home/$USER_NAME
run_claude_json_logic() {
    CLAUDE_ROOT_JSON="$HOME/.claude.json"
    CLAUDE_ROOT_JSON_VOLUME="$HOME/.claude/_claude_root.json"
    if [ -f "$CLAUDE_ROOT_JSON" ] && [ ! -L "$CLAUDE_ROOT_JSON" ]; then
        mv "$CLAUDE_ROOT_JSON" "$CLAUDE_ROOT_JSON_VOLUME"
    fi
    if [ ! -f "$CLAUDE_ROOT_JSON_VOLUME" ]; then
        echo '{"hasCompletedOnboarding":false}' > "$CLAUDE_ROOT_JSON_VOLUME"
    fi
    ln -sf "$CLAUDE_ROOT_JSON_VOLUME" "$CLAUDE_ROOT_JSON"
}

run_tool_auth_logic() {
    TOOL_AUTH_DIR="$HOME/.tool-auth"
    mkdir -p "$TOOL_AUTH_DIR"

    for tool_dir in gh openai gemini codex; do
        mkdir -p "$TOOL_AUTH_DIR/$tool_dir"
    done

    for tool_dir in gh openai gemini; do
        config_path="$HOME/.config/$tool_dir"
        volume_path="$TOOL_AUTH_DIR/$tool_dir"
        if [ -d "$config_path" ] && [ ! -L "$config_path" ]; then
            cp -a "$config_path"/. "$volume_path"/ 2>/dev/null || true
            rm -rf "$config_path"
        fi
        mkdir -p "$HOME/.config"
        ln -sfn "$volume_path" "$config_path"
    done

    CODEX_CONFIG="$HOME/.codex"
    CODEX_VOLUME="$TOOL_AUTH_DIR/codex"
    if [ -d "$CODEX_CONFIG" ] && [ ! -L "$CODEX_CONFIG" ]; then
        cp -a "$CODEX_CONFIG"/. "$CODEX_VOLUME"/ 2>/dev/null || true
        rm -rf "$CODEX_CONFIG"
    fi
    ln -sfn "$CODEX_VOLUME" "$CODEX_CONFIG"
}

# ========================== TEST CASES ==========================

echo "=== Test 1: First run (empty volumes) ==="
setup
run_claude_json_logic
run_tool_auth_logic
assert_symlink "~/.claude.json is symlink" "$HOME/.claude.json" "$HOME/.claude/_claude_root.json"
assert_file_contains "claude root json has onboarding key" "$HOME/.claude/_claude_root.json" "hasCompletedOnboarding"
assert_symlink "~/.config/gh is symlink" "$HOME/.config/gh" "$HOME/.tool-auth/gh"
assert_symlink "~/.config/openai is symlink" "$HOME/.config/openai" "$HOME/.tool-auth/openai"
assert_symlink "~/.config/gemini is symlink" "$HOME/.config/gemini" "$HOME/.tool-auth/gemini"
assert_symlink "~/.codex is symlink" "$HOME/.codex" "$HOME/.tool-auth/codex"
# Writing through symlink should land in volume
echo "test-token" > "$HOME/.config/gh/hosts.yml"
assert_file_contains "write through symlink lands in volume" "$HOME/.tool-auth/gh/hosts.yml" "test-token"
teardown

echo ""
echo "=== Test 2: Migration (real dirs exist pre-persistence) ==="
setup
# Pre-populate real config dirs with data
mkdir -p "$HOME/.config/gh" && echo "gh-auth-data" > "$HOME/.config/gh/hosts.yml"
mkdir -p "$HOME/.config/openai" && echo "sk-test123" > "$HOME/.config/openai/api_key"
mkdir -p "$HOME/.codex" && echo '{"token":"abc"}' > "$HOME/.codex/auth.json"
echo '{"hasCompletedOnboarding":true}' > "$HOME/.claude.json"
run_claude_json_logic
run_tool_auth_logic
assert_symlink "~/.claude.json migrated to symlink" "$HOME/.claude.json" "$HOME/.claude/_claude_root.json"
assert_file_contains "claude.json content preserved" "$HOME/.claude/_claude_root.json" "hasCompletedOnboarding"
assert_file_contains "gh auth migrated into volume" "$HOME/.tool-auth/gh/hosts.yml" "gh-auth-data"
assert_symlink "~/.config/gh replaced with symlink" "$HOME/.config/gh" "$HOME/.tool-auth/gh"
assert_file_contains "openai key migrated into volume" "$HOME/.tool-auth/openai/api_key" "sk-test123"
assert_file_contains "codex auth migrated into volume" "$HOME/.tool-auth/codex/auth.json" '{"token":"abc"}'
assert_symlink "~/.codex replaced with symlink" "$HOME/.codex" "$HOME/.tool-auth/codex"
teardown

echo ""
echo "=== Test 3: Rebuild (volumes have data, container is fresh) ==="
setup
# Simulate volume already having data from a previous run
# (subdirs exist because a prior entrypoint created them)
echo '{"hasCompletedOnboarding":true,"userId":"u123"}' > "$HOME/.claude/_claude_root.json"
for d in gh openai gemini codex; do mkdir -p "$HOME/.tool-auth/$d"; done
echo "gh-existing" > "$HOME/.tool-auth/gh/hosts.yml"
echo "sk-existing" > "$HOME/.tool-auth/openai/api_key"
echo '{"token":"existing"}' > "$HOME/.tool-auth/codex/auth.json"
# No symlinks exist (fresh container layer)
run_claude_json_logic
run_tool_auth_logic
assert_symlink "~/.claude.json symlink recreated" "$HOME/.claude.json" "$HOME/.claude/_claude_root.json"
assert_file_contains "claude.json volume data preserved" "$HOME/.claude/_claude_root.json" "userId"
assert_symlink "~/.config/gh symlink recreated" "$HOME/.config/gh" "$HOME/.tool-auth/gh"
assert_file_contains "gh data accessible through symlink" "$HOME/.config/gh/hosts.yml" "gh-existing"
assert_file_contains "openai key accessible through symlink" "$HOME/.config/openai/api_key" "sk-existing"
assert_file_contains "codex auth accessible through symlink" "$HOME/.codex/auth.json" '{"token":"existing"}'
teardown

echo ""
echo "=== Test 4: Idempotent re-run (symlinks already in place) ==="
setup
# First run
echo '{"hasCompletedOnboarding":true}' > "$HOME/.claude/_claude_root.json"
ln -sf "$HOME/.claude/_claude_root.json" "$HOME/.claude.json"
for tool_dir in gh openai gemini codex; do
    mkdir -p "$HOME/.tool-auth/$tool_dir"
done
for tool_dir in gh openai gemini; do
    ln -sfn "$HOME/.tool-auth/$tool_dir" "$HOME/.config/$tool_dir"
done
ln -sfn "$HOME/.tool-auth/codex" "$HOME/.codex"
echo "persistent-data" > "$HOME/.tool-auth/gh/hosts.yml"
# Second run (simulates container restart, not rebuild)
run_claude_json_logic
run_tool_auth_logic
assert_symlink "~/.claude.json still a symlink" "$HOME/.claude.json" "$HOME/.claude/_claude_root.json"
assert_file_contains "data still intact" "$HOME/.tool-auth/gh/hosts.yml" "persistent-data"
assert_symlink "gh symlink unchanged" "$HOME/.config/gh" "$HOME/.tool-auth/gh"
teardown

echo ""
echo "=== Test 5: configure_tools.sh is_configured claude ==="
setup
# Replicate the new is_configured logic
is_configured_claude() {
    local creds_file="$HOME/.claude/.credentials.json"
    if [ -f "$creds_file" ] && [ -s "$creds_file" ]; then
        return 0
    fi
    return 1
}
# No creds file
if is_configured_claude; then
    echo "  FAIL: should not be configured without creds file"; FAIL=$((FAIL + 1))
else
    echo "  PASS: not configured when creds file missing"; PASS=$((PASS + 1))
fi
# Empty creds file
touch "$HOME/.claude/.credentials.json"
if is_configured_claude; then
    echo "  FAIL: should not be configured with empty creds file"; FAIL=$((FAIL + 1))
else
    echo "  PASS: not configured when creds file empty"; PASS=$((PASS + 1))
fi
# Valid creds file
echo '{"accessToken":"abc123"}' > "$HOME/.claude/.credentials.json"
if is_configured_claude; then
    echo "  PASS: configured when creds file has content"; PASS=$((PASS + 1))
else
    echo "  FAIL: should be configured when creds file has content"; FAIL=$((FAIL + 1))
fi
teardown

echo ""
echo "========================================="
echo "Results: $PASS passed, $FAIL failed"
echo "========================================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
