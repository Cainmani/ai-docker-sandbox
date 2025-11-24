# Application Logging System

## Overview

The AI Docker CLI Setup application now includes a comprehensive centralized logging system that records all operations, errors, and debugging information to help with troubleshooting and support.

## Log File Location

All application logs are written to a single centralized log file:

**Windows Location:**
```
%LOCALAPPDATA%\AI-Docker-CLI\logs\ai-docker.log
```

**Full Path Example:**
```
C:\Users\YourUsername\AppData\Local\AI-Docker-CLI\logs\ai-docker.log
```

## How to Access Your Log File

### Method 1: Using Windows Explorer
1. Press `Windows + R` to open Run dialog
2. Type: `%LOCALAPPDATA%\AI-Docker-CLI\logs`
3. Press Enter
4. Open the `ai-docker.log` file with Notepad or any text editor

### Method 2: Using Command Prompt
```cmd
notepad %LOCALAPPDATA%\AI-Docker-CLI\logs\ai-docker.log
```

### Method 3: Using PowerShell
```powershell
Get-Content "$env:LOCALAPPDATA\AI-Docker-CLI\logs\ai-docker.log" -Tail 50
```

## Log Format

Each log entry follows this format:
```
[YYYY-MM-DD HH:mm:ss.fff] [LEVEL] [COMPONENT] Message
```

**Example:**
```
[2025-01-24 14:32:15.123] [INFO] [LAUNCHER] Launch AI Workspace button clicked
[2025-01-24 14:32:15.234] [DEBUG] [LAUNCHER] Checking for existing ai-cli container...
[2025-01-24 14:32:15.345] [INFO] [LAUNCHER] Container 'ai-cli' found - launching workspace...
```

### Log Levels

- **INFO**: Normal operations and key events
- **WARN**: Warnings that don't prevent operation but may need attention
- **ERROR**: Errors that caused an operation to fail
- **DEBUG**: Detailed diagnostic information for troubleshooting

### Components

- **LAUNCHER**: Main AI_Docker_Launcher.ps1 script
- **LAUNCH_CLAUDE**: launch_claude.ps1 workspace launcher
- **COMPLETE**: AI_Docker_Complete.ps1 standalone executable

## What Gets Logged

### Startup & Initialization
- Application start time
- Log file location
- Script path detection and resolution
- Environment variable checks

### Docker Operations
- Docker executable location
- Docker status checks
- Container existence checks
- Container start/stop operations
- Docker Desktop auto-start attempts

### User Actions
- Button clicks
- User choices in dialog boxes
- Navigation through setup wizard

### File Operations
- .env file reading/writing
- Codex authentication sync
- Script extraction from embedded resources
- Docker file extraction

### Path Resolution
- All path detection attempts
- Type conversions (PathInfo to string)
- Join-Path operations
- Fallback path selection

### Errors & Exceptions
- Exception messages
- Stack traces
- Failed operations
- Recovery attempts

## Common Use Cases

### 1. Debugging "Cannot bind argument to parameter 'Path'" Error

Search the log for path-related entries:
```
scriptPath value: [...]
scriptPath type: System.String
Join-Path succeeded: [...]
```

This will show you exactly what path values were used and where the error occurred.

### 2. Checking Why Container Won't Start

Search for Docker-related entries:
```
Docker found at: ...
Docker is running and responding
Container check result: [ai-cli]
```

### 3. Troubleshooting Setup Failures

Look for entries during setup wizard execution:
```
Setup wizard process completed with exit code: 0
```

Exit code 0 = success, 1 = error, 2 = cancelled

### 4. Verifying Codex Authentication Sync

Search for Codex-related entries:
```
Windows Codex auth found - checking container...
Codex auth synced to container successfully
```

## Log File Management

### Size
The log file will grow over time. We recommend:
- Checking the size periodically
- Archiving or deleting old logs if the file becomes too large (>10MB)

### Manual Cleanup
To clear the log file:
```powershell
Clear-Content "$env:LOCALAPPDATA\AI-Docker-CLI\logs\ai-docker.log"
```

Or simply delete the file - it will be recreated on next run.

### Backup
To save a copy of your logs before clearing:
```powershell
Copy-Item "$env:LOCALAPPDATA\AI-Docker-CLI\logs\ai-docker.log" "$env:USERPROFILE\Desktop\ai-docker-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
```

## Getting Support

When reporting issues:

1. **Reproduce the problem** while logging is active
2. **Locate your log file** at `%LOCALAPPDATA%\AI-Docker-CLI\logs\ai-docker.log`
3. **Copy the relevant section** (last 50-100 lines usually sufficient)
4. **Include it with your issue report** on GitHub

**Example PowerShell command to get last 100 lines:**
```powershell
Get-Content "$env:LOCALAPPDATA\AI-Docker-CLI\logs\ai-docker.log" -Tail 100 | Out-File "$env:USERPROFILE\Desktop\debug-log.txt"
```

This will save the last 100 log lines to `debug-log.txt` on your Desktop.

## Privacy & Security

### What's Logged
- System paths (may include your username)
- Docker container names
- File paths
- Operation results

### What's NOT Logged
- API keys or authentication tokens
- Password or credentials
- Personal code or data from your containers
- Contents of your workspace files

### Sharing Logs Safely
When sharing logs for support:
- Review the log file first
- Remove any sensitive information if present
- You can redact your username if privacy is a concern

## Technical Details

### Implementation
- All scripts use a centralized `Write-AppLog` function
- Logs are appended (not overwritten) on each run
- Timestamp precision: milliseconds
- Encoding: UTF-8
- Error handling: Logging failures are silently suppressed to prevent app breakage

### Performance
- Minimal performance impact (async file writes)
- No console output from logging (won't create unwanted windows)
- Logs only written when operations occur

### Future Enhancements
Potential future improvements:
- Automatic log rotation
- Configurable log levels
- Separate error log file
- Log file compression for old entries

## Troubleshooting the Logging System

If logs are not being created:

1. **Check directory permissions:**
   ```powershell
   Test-Path "$env:LOCALAPPDATA\AI-Docker-CLI\logs" -ErrorAction SilentlyContinue
   ```

2. **Verify LOCALAPPDATA is set:**
   ```powershell
   $env:LOCALAPPDATA
   ```

3. **Manually create the directory:**
   ```powershell
   New-Item -ItemType Directory -Path "$env:LOCALAPPDATA\AI-Docker-CLI\logs" -Force
   ```

The application will continue to work even if logging fails - it's designed to fail silently rather than break the application.

## Examples

### Finding All Errors
```powershell
Select-String -Path "$env:LOCALAPPDATA\AI-Docker-CLI\logs\ai-docker.log" -Pattern "\[ERROR\]"
```

### Viewing Logs in Real-Time
```powershell
Get-Content "$env:LOCALAPPDATA\AI-Docker-CLI\logs\ai-docker.log" -Wait -Tail 20
```

### Exporting Today's Logs
```powershell
$today = Get-Date -Format "yyyy-MM-dd"
Select-String -Path "$env:LOCALAPPDATA\AI-Docker-CLI\logs\ai-docker.log" -Pattern "^\[$today" |
    Out-File "$env:USERPROFILE\Desktop\logs-$today.txt"
```

---

**Last Updated:** 2025-01-24
**Version:** 1.0
