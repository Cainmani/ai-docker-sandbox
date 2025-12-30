#!/bin/bash
# Test script for Vibe Kanban integration
# Run this after creating the feature branch to validate changes

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    echo -e "       $2"
    ((TESTS_FAILED++))
}

header() {
    echo ""
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}================================================================${NC}"
}

# ============================================================================
# VIBE KANBAN INTEGRATION TESTS
# ============================================================================

header "VIBE KANBAN INTEGRATION TESTS"

# Test 1: docker-compose.yml has port mapping
echo ""
echo "Testing docker-compose.yml changes..."

if grep -q "VIBE_KANBAN_PORT" docker/docker-compose.yml; then
    pass "docker-compose.yml contains VIBE_KANBAN_PORT environment variable"
else
    fail "docker-compose.yml missing VIBE_KANBAN_PORT" "Environment variable not defined"
fi

if grep -q "ports:" docker/docker-compose.yml; then
    pass "docker-compose.yml has ports section"
else
    fail "docker-compose.yml missing ports section" "Port mapping not configured"
fi

if grep -q "3000:.*3000" docker/docker-compose.yml; then
    pass "docker-compose.yml maps port 3000"
else
    fail "docker-compose.yml not mapping port 3000" "Port mapping incorrect"
fi

if grep -q "vibe-kanban-data" docker/docker-compose.yml; then
    pass "docker-compose.yml has vibe-kanban-data volume"
else
    fail "docker-compose.yml missing vibe-kanban-data volume" "Data persistence not configured"
fi

# Test 2: install_cli_tools.sh includes Vibe Kanban
echo ""
echo "Testing install_cli_tools.sh changes..."

if grep -q "vibe-kanban" docker/install_cli_tools.sh; then
    pass "install_cli_tools.sh references vibe-kanban"
else
    fail "install_cli_tools.sh missing vibe-kanban" "Installation not configured"
fi

if grep -q "Vibe Kanban" docker/install_cli_tools.sh; then
    pass "install_cli_tools.sh has Vibe Kanban installation section"
else
    fail "install_cli_tools.sh missing Vibe Kanban section" "Installation section not added"
fi

if grep -q "npm install -g vibe-kanban" docker/install_cli_tools.sh; then
    pass "install_cli_tools.sh has npm install command for vibe-kanban"
else
    fail "install_cli_tools.sh missing npm install command" "Install command not configured"
fi

# Test 3: auto_update.sh includes Vibe Kanban
echo ""
echo "Testing auto_update.sh changes..."

if grep -q "vibe-kanban" docker/auto_update.sh; then
    pass "auto_update.sh includes vibe-kanban in update checks"
else
    fail "auto_update.sh missing vibe-kanban" "Auto-update not configured"
fi

# Test 4: launch_vibe_kanban.ps1 exists
echo ""
echo "Testing launcher script..."

if [ -f "scripts/launch_vibe_kanban.ps1" ]; then
    pass "launch_vibe_kanban.ps1 exists"
else
    fail "launch_vibe_kanban.ps1 missing" "Launcher script not created"
fi

if grep -q "HOST=0.0.0.0" scripts/launch_vibe_kanban.ps1 2>/dev/null; then
    pass "launch_vibe_kanban.ps1 uses HOST=0.0.0.0 for remote access"
else
    fail "launch_vibe_kanban.ps1 missing HOST binding" "Container access not configured"
fi

if grep -q "localhost:3000" scripts/launch_vibe_kanban.ps1 2>/dev/null || grep -q 'localhost:\$' scripts/launch_vibe_kanban.ps1 2>/dev/null; then
    pass "launch_vibe_kanban.ps1 opens browser to localhost"
else
    fail "launch_vibe_kanban.ps1 missing browser launch" "Browser open not configured"
fi

# Test 5: AI_Docker_Launcher.ps1 has Vibe Kanban button
echo ""
echo "Testing main launcher changes..."

if grep -q "LAUNCH VIBE KANBAN" scripts/AI_Docker_Launcher.ps1; then
    pass "AI_Docker_Launcher.ps1 has Vibe Kanban button"
else
    fail "AI_Docker_Launcher.ps1 missing Vibe Kanban button" "Button not added"
fi

if grep -q "btnVibeKanban" scripts/AI_Docker_Launcher.ps1; then
    pass "AI_Docker_Launcher.ps1 has btnVibeKanban control"
else
    fail "AI_Docker_Launcher.ps1 missing button control" "Button control not defined"
fi

if grep -q "launch_vibe_kanban.ps1" scripts/AI_Docker_Launcher.ps1; then
    pass "AI_Docker_Launcher.ps1 references launch_vibe_kanban.ps1"
else
    fail "AI_Docker_Launcher.ps1 missing script reference" "Launcher script not linked"
fi

# Test 6: Documentation updated
echo ""
echo "Testing documentation updates..."

if grep -q "Vibe Kanban" docs/CLI_TOOLS_GUIDE.md; then
    pass "CLI_TOOLS_GUIDE.md documents Vibe Kanban"
else
    fail "CLI_TOOLS_GUIDE.md missing Vibe Kanban" "Documentation not updated"
fi

if grep -q "vibekanban.com" docs/CLI_TOOLS_GUIDE.md; then
    pass "CLI_TOOLS_GUIDE.md has vibekanban.com reference"
else
    fail "CLI_TOOLS_GUIDE.md missing website reference" "Link not added"
fi

if grep -q "Vibe Kanban" docs/USER_MANUAL.md; then
    pass "USER_MANUAL.md documents Vibe Kanban"
else
    fail "USER_MANUAL.md missing Vibe Kanban" "User manual not updated"
fi

if grep -q "Using Vibe Kanban" docs/USER_MANUAL.md; then
    pass "USER_MANUAL.md has 'Using Vibe Kanban' section"
else
    fail "USER_MANUAL.md missing section" "Section not added"
fi

if grep -q "Vibe Kanban" docs/QUICK_REFERENCE.md; then
    pass "QUICK_REFERENCE.md documents Vibe Kanban"
else
    fail "QUICK_REFERENCE.md missing Vibe Kanban" "Quick reference not updated"
fi

if grep -q "localhost:3000" docs/QUICK_REFERENCE.md; then
    pass "QUICK_REFERENCE.md mentions localhost:3000"
else
    fail "QUICK_REFERENCE.md missing URL" "Access URL not documented"
fi

# Test 7: Shell scripts have correct line endings
echo ""
echo "Testing file format..."

for script in docker/install_cli_tools.sh docker/auto_update.sh docker/entrypoint.sh; do
    if file "$script" | grep -q "CRLF"; then
        fail "$script has CRLF line endings" "Will fail in Linux container"
    else
        pass "$script has correct line endings (LF)"
    fi
done

# ============================================================================
# RESULTS SUMMARY
# ============================================================================

header "TEST RESULTS SUMMARY"

echo ""
echo -e "Tests Passed:  ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed:  ${RED}$TESTS_FAILED${NC}"
echo ""

TOTAL=$((TESTS_PASSED + TESTS_FAILED))
if [ $TOTAL -gt 0 ]; then
    PASS_RATE=$((TESTS_PASSED * 100 / TOTAL))
    echo "Pass Rate: $PASS_RATE%"
fi

echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}================================================================${NC}"
    echo -e "${GREEN}  ALL VIBE KANBAN INTEGRATION TESTS PASSED${NC}"
    echo -e "${GREEN}================================================================${NC}"
    exit 0
else
    echo -e "${RED}================================================================${NC}"
    echo -e "${RED}  SOME TESTS FAILED - PLEASE FIX BEFORE MERGING${NC}"
    echo -e "${RED}================================================================${NC}"
    exit 1
fi
