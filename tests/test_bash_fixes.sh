#!/bin/bash
# Structural regression tests for audit fixes
# Guards Phase 1 fixes from being accidentally reverted.
# Auto-discovered by CI (tests/test_*.sh glob pattern).
set -euo pipefail

PASS=0
FAIL=0

pass() {
    echo "  PASS: $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "  FAIL: $1"
    FAIL=$((FAIL + 1))
}

echo "=== Structural Regression Tests ==="

# CQ-016: interactive_configure uses while loop, not recursion
echo ""
echo "--- CQ-016: interactive_configure recursion fix ---"
if grep -q "while true" docker/configure_tools.sh; then
    pass "configure_tools.sh uses 'while true' loop"
else
    fail "configure_tools.sh missing 'while true' loop"
fi

# Count recursive calls to interactive_configure inside the function body
# Should only appear in function definition and the main case entry point, NOT inside the case block
recursive_calls=$(grep -c "interactive_configure" docker/configure_tools.sh)
if [ "$recursive_calls" -le 2 ]; then
    pass "interactive_configure has no recursive calls inside case block (found $recursive_calls refs total)"
else
    fail "interactive_configure may still have recursive calls (found $recursive_calls refs, expected <=2)"
fi

# BP-010: Quoted $(whoami) in install_cli_tools.sh
echo ""
echo "--- BP-010: Quoted whoami in install_cli_tools.sh ---"
if grep -q '"$(whoami)"' docker/install_cli_tools.sh; then
    pass "install_cli_tools.sh has quoted \$(whoami)"
else
    fail "install_cli_tools.sh has unquoted \$(whoami)"
fi

# BP-015: Quoted $(whoami) in auto_update.sh (2 instances)
echo ""
echo "--- BP-015: Quoted whoami in auto_update.sh ---"
quoted_count=$(grep -c '"$(whoami)"' docker/auto_update.sh)
if [ "$quoted_count" -ge 2 ]; then
    pass "auto_update.sh has $quoted_count quoted \$(whoami) instances"
else
    fail "auto_update.sh has only $quoted_count quoted \$(whoami) (expected >=2)"
fi

# BP-027: .secrets/ in .gitignore
echo ""
echo "--- BP-027: .secrets/ in .gitignore ---"
if grep -q '\.secrets/' .gitignore; then
    pass ".gitignore contains .secrets/"
else
    fail ".gitignore missing .secrets/"
fi

# DEP-014: ps2exe pinned in release workflow
echo ""
echo "--- DEP-014: ps2exe version pinned ---"
if grep -q 'RequiredVersion' .github/workflows/release.yml; then
    pass "release.yml pins ps2exe with -RequiredVersion"
else
    fail "release.yml does not pin ps2exe version"
fi

# Bash syntax check for all docker shell scripts
echo ""
echo "--- Bash syntax validation ---"
syntax_ok=true
for script in docker/*.sh; do
    if bash -n "$script" 2>/dev/null; then
        pass "$script passes bash -n"
    else
        fail "$script has syntax errors"
        syntax_ok=false
    fi
done

# Shared module files exist
echo ""
echo "--- Shared module existence ---"
for module in scripts/log_utils.ps1 scripts/docker_helpers.ps1 scripts/setup_utils.ps1 scripts/env_utils.ps1; do
    if [ -f "$module" ]; then
        pass "$module exists"
    else
        fail "$module missing"
    fi
done

# Phase 4: Color dedup - logging.sh exports color vars
echo ""
echo "--- Phase 4: logging.sh color exports ---"
if grep -q 'export RED GREEN' docker/lib/logging.sh; then
    pass "logging.sh exports color variables"
else
    fail "logging.sh does not export color variables"
fi

if grep -q "CYAN=" docker/lib/logging.sh && grep -q "BOLD=" docker/lib/logging.sh; then
    pass "logging.sh defines CYAN and BOLD"
else
    fail "logging.sh missing CYAN or BOLD"
fi

# Color vars should NOT be redefined in scripts that source logging.sh
for script in docker/configure_tools.sh docker/install_cli_tools.sh docker/auto_update.sh; do
    if grep -qE "^RED='" "$script" 2>/dev/null; then
        fail "$script still defines its own color vars"
    else
        pass "$script uses shared color vars from logging.sh"
    fi
done

# add_ssh_key.sh and setup_remote_connection.sh should source logging.sh
for script in docker/add_ssh_key.sh docker/setup_remote_connection.sh; do
    if grep -q 'source.*logging.sh' "$script"; then
        pass "$script sources logging.sh"
    else
        fail "$script does not source logging.sh"
    fi
done

# Phase 5: Security fixes and dead code cleanup
echo ""
echo "--- Phase 5: Security fixes + dead code ---"

# CQ-008: claude_wrapper.sh removed
if [ ! -f "docker/claude_wrapper.sh" ]; then
    pass "claude_wrapper.sh has been removed (CQ-008)"
else
    fail "claude_wrapper.sh still exists"
fi

# CQ-020: entrypoint uses sleep infinity
if grep -q 'sleep infinity' docker/entrypoint.sh; then
    pass "entrypoint.sh uses 'sleep infinity' (CQ-020)"
else
    fail "entrypoint.sh still uses 'tail -f /dev/null'"
fi

# BP-028: no useless cat in entrypoint
if grep -q 'cat.*secret_file.*tr' docker/entrypoint.sh; then
    fail "entrypoint.sh still has useless use of cat (BP-028)"
else
    pass "entrypoint.sh uses input redirection instead of cat (BP-028)"
fi

# SEC-015: crypto RNG in setup_utils
if grep -q 'RandomNumberGenerator' scripts/setup_utils.ps1; then
    pass "setup_utils.ps1 uses cryptographic RNG (SEC-015)"
else
    fail "setup_utils.ps1 still uses System.Random"
fi

# New-SecurePasswordFile in setup_utils
if grep -q 'function New-SecurePasswordFile' scripts/setup_utils.ps1; then
    pass "New-SecurePasswordFile defined in setup_utils.ps1"
else
    fail "New-SecurePasswordFile missing from setup_utils.ps1"
fi

# Phase 6: Sanitization pattern order and CI linting
echo ""
echo "--- Phase 6: Sanitization + batch fixes ---"

# SEC-020: sk-ant- must appear before generic sk- in logging.sh
ant_line=$(grep -n 'sk-ant-' docker/lib/logging.sh | head -1 | cut -d: -f1)
generic_line=$(grep -n 'sk-\[a-zA-Z0-9\]' docker/lib/logging.sh | head -1 | cut -d: -f1)
if [ -n "$ant_line" ] && [ -n "$generic_line" ] && [ "$ant_line" -lt "$generic_line" ]; then
    pass "logging.sh: sk-ant- before generic sk- (SEC-020)"
else
    fail "logging.sh: sk-ant- must come before generic sk-"
fi

# SEC-019: github_pat_ pattern exists in logging.sh
if grep -q 'github_pat_' docker/lib/logging.sh; then
    pass "logging.sh has github_pat_ pattern (SEC-019)"
else
    fail "logging.sh missing github_pat_ pattern"
fi

# SEC-019: github_pat_ pattern exists in log_utils.ps1
if grep -q 'github_pat_' scripts/log_utils.ps1; then
    pass "log_utils.ps1 has github_pat_ pattern (SEC-019)"
else
    fail "log_utils.ps1 missing github_pat_ pattern"
fi

# CQ-017: update_log strips ANSI codes
if grep -q 'clean_msg' docker/auto_update.sh; then
    pass "auto_update.sh strips ANSI codes in update_log (CQ-017)"
else
    fail "auto_update.sh does not strip ANSI codes"
fi

echo ""
echo "========================================="
echo "Results: $PASS passed, $FAIL failed"
echo "========================================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
