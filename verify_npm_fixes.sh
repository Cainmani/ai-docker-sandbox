#!/bin/bash

# Verification script to test npm permission fixes
# This script should be run inside the Docker container

set -e

echo "=========================================="
echo "NPM Permission Fixes Verification Script"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0

# Test 1: Check npm prefix configuration
echo "Test 1: Checking npm prefix configuration..."
NPM_PREFIX=$(npm config get prefix)
EXPECTED_PREFIX="$HOME/.npm-global"
if [ "$NPM_PREFIX" = "$EXPECTED_PREFIX" ]; then
    echo -e "${GREEN}✓ PASS${NC} - npm prefix is correctly set to: $NPM_PREFIX"
else
    echo -e "${RED}✗ FAIL${NC} - npm prefix is $NPM_PREFIX, expected $EXPECTED_PREFIX"
    ((ERRORS++))
fi
echo ""

# Test 2: Check if .npm-global directory exists
echo "Test 2: Checking if .npm-global directory exists..."
if [ -d "$HOME/.npm-global" ]; then
    echo -e "${GREEN}✓ PASS${NC} - .npm-global directory exists"
    ls -ld "$HOME/.npm-global"
else
    echo -e "${RED}✗ FAIL${NC} - .npm-global directory not found"
    ((ERRORS++))
fi
echo ""

# Test 3: Check PATH in .bashrc
echo "Test 3: Checking PATH in .bashrc..."
if [ -f "$HOME/.bashrc" ]; then
    if grep -q "\.npm-global/bin" "$HOME/.bashrc"; then
        echo -e "${GREEN}✓ PASS${NC} - .bashrc contains npm-global in PATH"
        grep "\.npm-global/bin" "$HOME/.bashrc"
    else
        echo -e "${RED}✗ FAIL${NC} - .bashrc does not contain npm-global in PATH"
        ((ERRORS++))
    fi
else
    echo -e "${YELLOW}⚠ SKIP${NC} - .bashrc not found"
fi
echo ""

# Test 4: Check PATH in .profile
echo "Test 4: Checking PATH in .profile..."
if [ -f "$HOME/.profile" ]; then
    if grep -q "\.npm-global/bin" "$HOME/.profile"; then
        echo -e "${GREEN}✓ PASS${NC} - .profile contains npm-global in PATH"
        grep "\.npm-global/bin" "$HOME/.profile"
    else
        echo -e "${RED}✗ FAIL${NC} - .profile does not contain npm-global in PATH"
        ((ERRORS++))
    fi
else
    echo -e "${RED}✗ FAIL${NC} - .profile not found"
    ((ERRORS++))
fi
echo ""

# Test 5: Check current PATH
echo "Test 5: Checking current PATH..."
if echo "$PATH" | grep -q "\.npm-global/bin"; then
    echo -e "${GREEN}✓ PASS${NC} - Current PATH contains .npm-global/bin"
    echo "PATH: $PATH"
else
    echo -e "${YELLOW}⚠ WARNING${NC} - Current PATH does not contain .npm-global/bin"
    echo "PATH: $PATH"
    echo "Note: This may be expected if running in a non-login shell. Try: source ~/.profile"
fi
echo ""

# Test 6: Check if we can install npm packages without sudo
echo "Test 6: Testing npm install without sudo..."
TEST_PKG="cowsay"
if npm install -g "$TEST_PKG" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ PASS${NC} - Can install npm packages without sudo"
    # Cleanup
    npm uninstall -g "$TEST_PKG" >/dev/null 2>&1
else
    echo -e "${RED}✗ FAIL${NC} - Cannot install npm packages without sudo"
    ((ERRORS++))
fi
echo ""

# Test 7: Check directory ownership
echo "Test 7: Checking .npm-global ownership..."
if [ -d "$HOME/.npm-global" ]; then
    OWNER=$(stat -c '%U' "$HOME/.npm-global")
    if [ "$OWNER" = "$(whoami)" ]; then
        echo -e "${GREEN}✓ PASS${NC} - .npm-global is owned by current user"
    else
        echo -e "${RED}✗ FAIL${NC} - .npm-global is owned by $OWNER, expected $(whoami)"
        ((ERRORS++))
    fi
fi
echo ""

# Test 8: Check installation marker file
echo "Test 8: Checking CLI tools installation marker..."
if [ -f "$HOME/.cli_tools_installed" ]; then
    echo -e "${GREEN}✓ PASS${NC} - Installation marker file exists"
    echo "Contents:"
    cat "$HOME/.cli_tools_installed"
else
    echo -e "${YELLOW}⚠ WARNING${NC} - Installation marker file not found (may still be installing)"
fi
echo ""

# Test 9: Check if Claude CLI is installed
echo "Test 9: Checking if Claude CLI is installed..."
if command -v claude >/dev/null 2>&1; then
    echo -e "${GREEN}✓ PASS${NC} - Claude CLI is installed"
    which claude
else
    echo -e "${YELLOW}⚠ WARNING${NC} - Claude CLI not found in PATH"
    echo "Checking if it exists in .npm-global..."
    if [ -f "$HOME/.npm-global/bin/claude" ]; then
        echo -e "${YELLOW}Found at: $HOME/.npm-global/bin/claude${NC}"
        echo "You may need to reload your shell: source ~/.profile"
    fi
fi
echo ""

# Test 10: Check GitHub CLI
echo "Test 10: Checking if GitHub CLI is installed..."
if command -v gh >/dev/null 2>&1; then
    echo -e "${GREEN}✓ PASS${NC} - GitHub CLI is installed"
    gh --version | head -n1
else
    echo -e "${YELLOW}⚠ WARNING${NC} - GitHub CLI not found"
fi
echo ""

# Summary
echo "=========================================="
echo "VERIFICATION SUMMARY"
echo "=========================================="
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}All critical tests passed!${NC}"
    echo "The npm permission fixes are working correctly."
    exit 0
else
    echo -e "${RED}Found $ERRORS error(s)${NC}"
    echo "Please review the failed tests above."
    exit 1
fi
