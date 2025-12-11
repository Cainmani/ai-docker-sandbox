# Contributing to AI Docker CLI Manager

First off, thank you for considering contributing to AI Docker CLI Manager! It's people like you that make this tool better for everyone.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Making Changes](#making-changes)
- [Submitting Changes](#submitting-changes)
- [Style Guidelines](#style-guidelines)
- [Reporting Bugs](#reporting-bugs)
- [Suggesting Features](#suggesting-features)

## Code of Conduct

This project and everyone participating in it is governed by our commitment to providing a welcoming and inclusive environment. Please be respectful and constructive in all interactions.

## Getting Started

### Prerequisites

- Windows 10/11
- Docker Desktop
- PowerShell 5.1+ or PowerShell 7+
- Git
- (Optional) Visual Studio Code with PowerShell extension

### Development Setup

1. **Fork the repository** on GitHub

2. **Clone your fork**:
   ```powershell
   git clone https://github.com/YOUR_USERNAME/ai-docker-cli-setup.git
   cd ai-docker-cli-setup
   ```

3. **Add upstream remote**:
   ```powershell
   git remote add upstream https://github.com/Cainmani/ai-docker-cli-setup.git
   ```

4. **Create a feature branch**:
   ```powershell
   git checkout -b feature/your-feature-name
   ```

### Project Structure

```
ai-docker-cli-setup/
├── scripts/           # PowerShell scripts
│   ├── setup_wizard.ps1          # Main setup wizard
│   ├── AI_Docker_Launcher.ps1    # Daily launcher
│   ├── AI_Docker_Complete.ps1    # Complete exe template
│   └── launch_claude.ps1         # Claude-specific launcher
├── docker/            # Docker configuration
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── entrypoint.sh
│   └── install_cli_tools.sh
├── docs/              # Documentation
├── tests/             # Testing documentation
└── assets/            # Logo and branding assets
```

## Making Changes

### Before You Start

1. **Check existing issues** to see if someone is already working on it
2. **Open an issue** to discuss major changes before implementation
3. **Keep changes focused** - one feature or fix per PR

### Development Workflow

1. **Sync with upstream**:
   ```powershell
   git fetch upstream
   git rebase upstream/main
   ```

2. **Make your changes** following our [style guidelines](#style-guidelines)

3. **Test thoroughly**:
   - Run the setup wizard through all pages
   - Test on a clean Windows installation if possible
   - Verify Docker operations work correctly

4. **Commit with conventional commits**:
   ```powershell
   git commit -m "feat: add new feature description"
   git commit -m "fix: resolve bug description"
   git commit -m "docs: update documentation"
   ```

### Conventional Commit Types

| Type | Description |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `style` | Formatting, no code change |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `test` | Adding or updating tests |
| `chore` | Maintenance tasks |

## Submitting Changes

1. **Push to your fork**:
   ```powershell
   git push origin feature/your-feature-name
   ```

2. **Open a Pull Request** on GitHub

3. **Fill out the PR template** completely

4. **Wait for review** - we'll respond as soon as possible

### PR Requirements

- [ ] All tests pass
- [ ] Code follows style guidelines
- [ ] Documentation updated (if applicable)
- [ ] Commit messages follow conventional commit format
- [ ] PR description explains the changes clearly

## Style Guidelines

### PowerShell

- Use PascalCase for function names: `Get-UserInput`, `Start-DockerBuild`
- Use camelCase for variables: `$userName`, `$configPath`
- Use descriptive variable names
- Add comments for complex logic
- Use proper error handling with try/catch

```powershell
# Good
function Get-UserCredentials {
    param(
        [Parameter(Mandatory=$true)]
        [string]$UserName
    )

    try {
        # Implementation
    } catch {
        Write-Error "Failed to get credentials: $($_.Exception.Message)"
    }
}

# Bad
function getcreds($u) {
    # Implementation without error handling
}
```

### Shell Scripts (Bash)

- Use snake_case for variables: `user_name`, `config_path`
- Use functions for reusable code
- Always quote variables: `"$variable"`
- Add `set -e` for fail-fast behavior

### Documentation

- Use clear, concise language
- Include code examples where helpful
- Keep the README focused on getting started
- Put detailed docs in the `/docs` folder

## Reporting Bugs

Use the [Bug Report template](https://github.com/Cainmani/ai-docker-cli-setup/issues/new?template=bug_report.yml) and include:

1. **Clear description** of the problem
2. **Steps to reproduce** the issue
3. **Expected vs actual behavior**
4. **Log file contents** from `%LOCALAPPDATA%\AI-Docker-CLI\logs\ai-docker.log`
5. **System information** (Windows version, Docker version)

## Suggesting Features

Use the [Feature Request template](https://github.com/Cainmani/ai-docker-cli-setup/issues/new?template=feature_request.yml) and include:

1. **Problem statement** - what problem does this solve?
2. **Proposed solution** - how should it work?
3. **Alternatives considered** - what other approaches did you think of?

## Questions?

Feel free to open a [Discussion](https://github.com/Cainmani/ai-docker-cli-setup/discussions) for questions or ideas that aren't bugs or feature requests.

---

## Release Process (Maintainers)

When creating a new release, follow this checklist:

### Pre-Release Checklist

1. **Update Version Numbers**
   - [ ] `scripts/AI_Docker_Complete.ps1` - `$script:AppVersion`
   - [ ] `scripts/AI_Docker_Launcher.ps1` - `$script:AppVersion`

2. **Update Documentation**
   - [ ] `CHANGELOG.md` - Add new version section with changes
   - [ ] `README.md` - Update version badge if using static badge
   - [ ] `docs/USER_MANUAL.md` - Update if features changed

3. **Code Quality**
   - [ ] Test all new features locally
   - [ ] Verify build works by running `scripts/build/build_complete_exe.ps1`

### Release Steps

```bash
# 1. Commit all changes
git add .
git commit -m "feat: Description of changes"

# 2. Push to main
git push origin main

# 3. Create annotated tag
git tag -a v1.x.x -m "v1.x.x - Brief description"

# 4. Push tag (triggers GitHub Actions release workflow)
git push origin v1.x.x

# 5. Verify release
gh release view v1.x.x
```

### Post-Release Verification

- [ ] GitHub Actions workflow completed successfully
- [ ] Release page shows correct version and assets
- [ ] Download and test `.exe` file
- [ ] Verify update detection works from previous version

---

Thank you for contributing! Your efforts help make AI Docker CLI Manager better for everyone.
