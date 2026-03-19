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
for module in scripts/log_utils.ps1 scripts/docker_helpers.ps1 scripts/setup_utils.ps1; do
    if [ -f "$module" ]; then
        pass "$module exists"
    else
        fail "$module missing"
    fi
done

echo ""
echo "========================================="
echo "Results: $PASS passed, $FAIL failed"
echo "========================================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
