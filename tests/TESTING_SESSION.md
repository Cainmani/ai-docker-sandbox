# AI Docker Manager - Live Testing Session

**Date**: _______________
**Testers**: You + Claude
**Goal**: Test each fix systematically and validate it works

---

## 🎯 Testing Approach

We'll go through each critical fix:
1. **Explain what the fix does**
2. **Show the code changes**
3. **Test it live on your Windows machine**
4. **Check off in TESTING_CHECKLIST.md if it works**
5. **Move to next fix**

---

## ✅ Fix #1: .claude Directory Permission Error (MOST CRITICAL!)

### What This Fix Does:
**Problem**: When your boss ran `claude`, he got:
```
Error: EACCES: permission denied, mkdir '/home/mniszl/.claude/debug'
```

**Root Cause**: The `.claude` directory was owned by root, not the user.

**Fix Location**: `docker/entrypoint.sh` lines 22-29

**What We Changed**:
```bash
# CRITICAL: Ensure user's home directory has correct ownership
chown -R "$USER_NAME:$USER_NAME" "/home/$USER_NAME" 2>/dev/null || true

# Ensure .claude directory exists with correct permissions
mkdir -p "/home/$USER_NAME/.claude"
chown -R "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.claude"
chmod 755 "/home/$USER_NAME/.claude"
```

### How to Test:
```powershell
# 1. Clean environment
docker stop ai-cli ; docker rm ai-cli ; docker rmi ai-docker-ai
Remove-Item "$env:LOCALAPPDATA\AI_Docker_Manager" -Recurse -Force

# 2. Run setup
.\AI_Docker_Manager.exe
# Click "1. FIRST TIME SETUP"
# Use: testuser / TestPass123!

# 3. After setup, launch
.\AI_Docker_Manager.exe
# Click "2. LAUNCH CLAUDE CLI"

# 4. In terminal, check permissions
ls -la ~ | grep .claude
# Expected: drwxr-xr-x testuser testuser .claude
# NOT owned by root!

# 5. Run claude
claude
# Expected: NO permission errors!
```

### Test Result:
- [ ] **PASS**: .claude directory owned by testuser
- [ ] **PASS**: claude command works without permission errors
- [ ] **FAIL**: (describe issue) _______________

**Notes**: _______________________________________________

---

## ✅ Fix #2: Docker Compose Command (Quoted Paths Issue)

### What This Fix Does:
**Problem**: Docker commands like `docker compose -f "C:/Users/..." build` failed on other devices.

**Root Cause**: PowerShell ProcessStartInfo doesn't handle quoted paths well.

**Fix Location**: `scripts/setup_wizard.ps1` lines 527-557

**What We Changed**:
```powershell
# OLD (broken):
$buildArgs = 'compose -f "' + $composePath + '" build'
# Result: docker compose -f "C:/Users/.../docker-compose.yml" build

# NEW (fixed):
Set-Location $PSScriptRoot
$buildArgs = 'compose build'
# Result: docker compose build (finds file in current directory)
```

### How to Test:
```powershell
# During First Time Setup, watch console output carefully
# Look for these lines:

# GOOD (what you should see):
[EXEC] docker compose build

# BAD (what you should NOT see):
[EXEC] docker compose -f "C:/Users/.../docker-compose.yml" build
```

### Test Result:
- [ ] **PASS**: Console shows `docker compose build` (no -f flag)
- [ ] **PASS**: Build completes successfully
- [ ] **FAIL**: (describe issue) _______________

**Notes**: _______________________________________________

---

## ✅ Fix #3: Post-Installation Validation

### What This Fix Does:
**Problem**: Setup said "Complete!" even when Claude wasn't actually working.

**Fix Location**: `scripts/setup_wizard.ps1` lines 623-650

**What We Added**:
- Test that `claude` command exists
- Test that it's executable
- Test user has sudo privileges
- Only show "Complete" if all tests pass

### How to Test:
```powershell
# During setup, watch console for these messages:

[INFO] Validating Claude CLI installation...
[SUCCESS] Claude CLI validated successfully
[INFO] Claude is ready at: /usr/local/bin/claude
[INFO] Verifying user sudo privileges...
[SUCCESS] User has passwordless sudo access
[SUCCESS] Installation complete!
```

### Test Result:
- [ ] **PASS**: Console shows all validation messages
- [ ] **PASS**: Setup fails if Claude not working (try breaking npm install to test)
- [ ] **FAIL**: (describe issue) _______________

**Notes**: _______________________________________________

---

## ✅ Fix #4: Enhanced Error Messages

### What This Fix Does:
**Problem**: When npm install failed, errors were cryptic.

**Fix Location**: `scripts/setup_wizard.ps1` lines 594-628

**What We Added**:
```powershell
$errMsg = "npm install failed (exit code: $($r3a.Code))`n`n" +
          "Common causes:`n" +
          "- No internet connection`n" +
          "- npm registry is down`n" +
          "- Firewall blocking npm`n`n" +
          "Check console for detailed error output."
```

### How to Test:
```powershell
# This is hard to test without breaking things
# During normal setup, you should see:

[INFO] This step requires internet connection
[SUCCESS] Claude Code CLI npm package installed
[INFO] Verifying npm installation...
[SUCCESS] npm package verified
```

### Test Result:
- [ ] **PASS**: Clear messages during npm install
- [ ] **SKIP**: (don't want to break npm to test error messages)

**Notes**: _______________________________________________

---

## ✅ Fix #5: Cancel Button Improvements

### What This Fix Does:
**Problem**: Cancel button didn't work properly during critical steps.

**Fix Location**: `scripts/setup_wizard.ps1` lines 417-453

**What We Added**:
- Confirmation dialog if cancelling during pages 4-5 (docker build/npm install)
- Proper process termination
- Exit code 1 on cancel

### How to Test:
```powershell
# Test 1: Cancel on early page
# 1. Run setup
# 2. On Page 2 (credentials), click "Cancel"
# 3. Expected: Closes immediately

# Test 2: Cancel during build
# 1. Run setup
# 2. Get to Page 5 (docker build running)
# 3. Click "Cancel"
# 4. Expected: Confirmation dialog appears
# 5. Click "No" - setup continues
# 6. Click "Cancel" again, then "Yes" - setup exits
```

### Test Result:
- [ ] **PASS**: Cancel works on early pages
- [ ] **PASS**: Confirmation dialog on critical pages
- [ ] **PASS**: Can choose to continue or cancel
- [ ] **FAIL**: (describe issue) _______________

**Notes**: _______________________________________________

---

## ✅ Fix #6: Container Protection

### What This Fix Does:
**Problem**: Re-running setup would delete existing container without warning.

**Fix Location**: `scripts/setup_wizard.ps1` lines 645-692

**What We Added**:
- Check if `ai-cli` container exists
- Show warning dialog before deletion
- Default button is "No" (safe)
- Recommend using "Launch Claude" instead

### How to Test:
```powershell
# 1. Complete a successful setup first
# 2. Run setup wizard AGAIN (intentionally)
# 3. Expected: Warning dialog appears

# Warning should say:
# "*** EXISTING CONTAINER DETECTED ***"
# "This container contains:"
# "  - Your Claude authentication"
# "  - Your configuration and settings"
# Default button: "No"

# 4. Click "No" - setup exits, container safe
# 5. Verify container still works: Launch Claude CLI
```

### Test Result:
- [ ] **PASS**: Warning appears when running setup with existing container
- [ ] **PASS**: Default button is "No"
- [ ] **PASS**: Clicking "No" keeps container safe
- [ ] **PASS**: Existing container still works after cancellation
- [ ] **FAIL**: (describe issue) _______________

**Notes**: _______________________________________________

---

## 📊 Overall Test Results

### Fixes Tested:
- [ ] Fix #1: .claude permissions (CRITICAL!)
- [ ] Fix #2: Docker compose commands
- [ ] Fix #3: Post-installation validation
- [ ] Fix #4: Enhanced error messages
- [ ] Fix #5: Cancel button
- [ ] Fix #6: Container protection

### Critical Tests:
- [ ] Claude works on first run (no permission errors)
- [ ] Authentication persists after container restart
- [ ] Files sync between Windows and container
- [ ] Setup fails gracefully if something breaks

### Overall Assessment:
- **Pass Rate**: _____ / 6 fixes working
- **Critical Issues**: _______________________________________________
- **Ready for CEO Demo?**: [ ] YES  [ ] NO

---

## 🚨 Issues Found During Testing

### Issue 1:
**Description**: _______________________________________________
**Severity**: [ ] Critical  [ ] Major  [ ] Minor
**Fix Required**: _______________________________________________

### Issue 2:
**Description**: _______________________________________________
**Severity**: [ ] Critical  [ ] Major  [ ] Minor
**Fix Required**: _______________________________________________

---

## ✅ Sign-Off

**Testing Completed**: [ ] YES
**All Critical Fixes Working**: [ ] YES
**Ready to Send to Boss**: [ ] YES
**Ready for CEO Demo**: [ ] YES

**Tester Signature**: __________________ **Date**: __________

---

## 📝 Next Steps After Testing

If all tests pass:
1. [ ] Send new exe to boss for validation
2. [ ] Practice CEO demo script
3. [ ] Prepare backup materials
4. [ ] Print documentation

If issues found:
1. [ ] Document all issues in this file
2. [ ] Prioritize critical issues
3. [ ] Fix and re-test
4. [ ] Re-run testing session
