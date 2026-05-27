# Codex Desktop — Windows Conversion Toolkit

> Convert the macOS-only OpenAI Codex Desktop app (`.dmg`) into a runnable Windows Electron application.

## Overview

This toolkit provides a complete pipeline for taking the macOS Codex Desktop DMG distribution and converting it into a fully functional Windows Electron application. The process involves:

1. **Downloading** the macOS Codex.dmg
2. **Extracting** the DMG on Windows using 7-Zip
3. **Detecting** the Electron version from the extracted app
4. **Downloading** the matching Windows Electron binary
5. **Patching** app.asar for Windows compatibility
6. **Rebuilding** native Node modules for Windows
7. **Installing** the application with shortcuts and URL protocol handlers

## Prerequisites

### Required Software

| Dependency | Minimum Version | Purpose | Download |
|---|---|---|---|
| **PowerShell** | 5.1 | Script execution | Built into Windows 10+ |
| **Python 3** | 3.8+ | Webview HTTP server | [python.org](https://www.python.org/downloads/) |
| **7-Zip** | 21.0+ | DMG extraction | [7-zip.org](https://www.7-zip.org/) |
| **Node.js** | 18.0+ | Native module rebuild | [nodejs.org](https://nodejs.org/) |
| **npm** | 9.0+ | Package management | Included with Node.js |

### Optional Software

| Dependency | Purpose | Download |
|---|---|---|
| **Rust (stable)** | Build native launcher & updater | [rustup.rs](https://rustup.rs/) |
| **NSIS** | Build Windows installer | [nsis.sourceforge.io](https://nsis.sourceforge.io/) |
| **Visual Studio Build Tools** | Native module compilation | [visualstudio.microsoft.com](https://visualstudio.microsoft.com/visual-cpp-build-tools/) |

### System Requirements

- Windows 10 version 1809 or later
- x64 or ARM64 processor
- 500 MB free disk space
- Internet connection for downloading DMG and Electron

## Installation

### Quick Install (Recommended)

Run the main installer script from an elevated PowerShell:

```powershell
# Run as Administrator
.\install.ps1
```

### Install with Options

```powershell
# Fresh install (removes existing installation)
.\install.ps1 -Fresh

# Use a pre-downloaded DMG
.\install.ps1 -DmgPath "C:\Downloads\Codex.dmg"

# Reuse cached DMG
.\install.ps1 -ReuseDmg

# Custom install directory
.\install.ps1 -InstallDir "D:\Apps\Codex Desktop"

# Combine options
.\install.ps1 -ReuseDmg -InstallDir "D:\Apps\Codex Desktop"
```

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `-Fresh` | `$false` | Remove existing installation before installing |
| `-ReuseDmg` | `$false` | Reuse cached DMG instead of re-downloading |
| `-DmgPath` | `""` | Path to existing Codex.dmg file |
| `-InstallDir` | `$env:ProgramFiles\Codex Desktop` | Installation target directory |

## Building from Source

### Build the Native Launcher

The launcher is a Rust application that compiles to `codex-desktop-launcher.exe`:

```bash
# From the toolkit root
cargo build --release -p codex-desktop-launcher
```

The output will be at `target/release/codex-desktop-launcher.exe`.

### Build the Update Manager

```bash
cargo build --release -p codex-update-manager
```

The output will be at `target/release/codex-update-manager.exe`.

### Build the NSIS Installer

1. Install [NSIS](https://nsis.sourceforge.io/)
2. Prepare the build directory with all application files
3. Run the NSIS compiler:

```bash
makensis packaging/codex-desktop.nsi
```

The output will be `codex-desktop-0.1.0-setup.exe`.

### Full Build Pipeline

```powershell
# 1. Run the installer to create the app
.\install.ps1

# 2. Build the native launcher
cargo build --release -p codex-desktop-launcher

# 3. Copy the launcher to the install directory
Copy-Item target\release\codex-desktop-launcher.exe "$env:ProgramFiles\Codex Desktop\"

# 4. Build the update manager
cargo build --release -p codex-update-manager

# 5. Create the NSIS installer
makensis packaging\codex-desktop.nsi
```

## Configuration

### Application Configuration

The application stores configuration and data in standard Windows locations:

| Path | Purpose |
|---|---|
| `%ProgramFiles%\Codex Desktop\` | Application installation |
| `%APPDATA%\.codex\` | User configuration and plugin data |
| `%LOCALAPPDATA%\codex-desktop\` | Cache, logs, and runtime state |
| `%LOCALAPPDATA%\codex-update-manager\` | Update manager state |

### Update Manager Configuration

The update manager reads configuration from:

```
%APPDATA%\codex-update-manager\config.toml
```

Default configuration:

```toml
dmg_url = "https://persistent.oaistatic.com/codex-app-prod/Codex.dmg"
check_interval_hours = 6
auto_update = false
show_notifications = true
enable_rollback = true
max_rollback_snapshots = 3
```

### Scheduled Update Task

To install the automatic update checker as a Windows scheduled task:

```powershell
# Import the task
schtasks /Create /TN "CodexDesktopUpdateManager" /XML packaging\codex-update-manager.xml

# Or using PowerShell
Register-ScheduledTask -Xml (Get-Content packaging\codex-update-manager.xml | Out-String) -TaskName "CodexDesktopUpdateManager"
```

### URL Protocol Handler

The installer registers the `codex://` URL protocol, allowing the app to be launched from browsers and other applications. This is stored in the Windows registry at:

- Per-machine: `HKLM\SOFTWARE\Classes\codex`
- Per-user: `HKCU\SOFTWARE\Classes\codex`

## Troubleshooting

### Common Issues

#### "7-Zip not found"

Install 7-Zip from [7-zip.org](https://www.7-zip.org/) and ensure it's in the default location (`C:\Program Files\7-Zip\7z.exe`) or on the system PATH.

#### "Python not found"

Install Python 3.8+ from [python.org](https://www.python.org/downloads/). Make sure to check "Add Python to PATH" during installation.

#### DMG extraction fails

Some DMG files use APFS format which 7-Zip may not fully support. Try:
1. Updating 7-Zip to the latest version
2. Using the `--ReuseDmg` flag to re-use a previously extracted copy

#### Native module rebuild fails

This typically requires Visual Studio Build Tools:
1. Install [Visual Studio Build Tools](https://visualstudio.microsoft.com/visual-cpp-build-tools/)
2. Select the "Desktop development with C++" workload
3. Re-run the installer

#### "Access denied" errors

Run the installer as Administrator:
1. Right-click on `install.ps1`
2. Select "Run with PowerShell" or "Run as Administrator"

#### Electron crashes on startup

Try adding additional flags to the launcher:
```powershell
.\start.ps1 -NoDaemon -Verbose
```
Check the log files in `%LOCALAPPDATA%\codex-desktop\logs\` for error details.

#### URL protocol (codex://) not working

Re-register the protocol handler:
```powershell
# As Administrator
$regPath = "HKLM:\SOFTWARE\Classes\codex"
New-Item -Path $regPath -Force
Set-ItemProperty -Path $regPath -Name "(Default)" -Value "URL:Codex Desktop Protocol"
Set-ItemProperty -Path $regPath -Name "URL Protocol" -Value ""
New-Item -Path "$regPath\shell\open\command" -Force
Set-ItemProperty -Path "$regPath\shell\open\command" -Name "(Default)" -Value "`"$env:ProgramFiles\Codex Desktop\start.ps1`" -Url `"%1`""
```

### Log Files

| Log File | Location | Purpose |
|---|---|---|
| Install log | `%LOCALAPPDATA%\codex-desktop\logs\install-*.log` | Installation process |
| Launcher log | `%LOCALAPPDATA%\codex-desktop\logs\launcher-*.log` | Launcher activity |
| Start log | `%LOCALAPPDATA%\codex-desktop\logs\start-*.log` | PowerShell launcher |
| Webview server | `%LOCALAPPDATA%\codex-desktop\logs\webview-server-*.log` | HTTP server |
| Electron | `%LOCALAPPDATA%\codex-desktop\logs\electron-*.log` | Electron process |
| Update manager | `%LOCALAPPDATA%\codex-update-manager\logs\*.log` | Update checks |

### Manual Uninstall

```powershell
# Remove installation directory
Remove-Item "$env:ProgramFiles\Codex Desktop" -Recurse -Force

# Remove shortcuts
Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Codex Desktop" -Recurse -Force
Remove-Item "$env:USERPROFILE\Desktop\Codex Desktop.lnk" -Force

# Remove registry entries
Remove-Item "HKLM:\SOFTWARE\Classes\codex" -Recurse -Force
Remove-Item "HKLM:\SOFTWARE\Codex Desktop" -Recurse -Force
Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Codex Desktop" -Recurse -Force

# Remove scheduled task
schtasks /Delete /TN "CodexDesktopUpdateManager" /F

# Remove user data (optional)
Remove-Item "$env:APPDATA\.codex" -Recurse -Force
Remove-Item "$env:LOCALAPPDATA\codex-desktop" -Recurse -Force
Remove-Item "$env:LOCALAPPDATA\codex-update-manager" -Recurse -Force
```

## Architecture Overview

```
codex-desktop-windows/
├── install.ps1                      # Main PowerShell installer
├── Cargo.toml                       # Rust workspace root
├── README.md                        # This file
│
├── launcher/
│   ├── Cargo.toml                   # Rust launcher dependencies
│   ├── start.ps1.template           # PowerShell launcher script template
│   ├── webview-server.py            # Cross-platform webview HTTP server
│   └── src/
│       └── main.rs                  # Rust native launcher (→ .exe)
│
├── scripts/
│   ├── patch-windows.js             # ASAR patch system for Windows
│   └── lib/
│       ├── Dmg-Extractor.ps1        # DMG download & extraction module
│       ├── Electron-Downloader.ps1  # Windows Electron binary downloader
│       ├── Native-Modules.ps1       # Native module rebuilder
│       ├── Node-Runtime.ps1         # Managed Node.js runtime installer
│       └── Plugin-Manager.ps1       # Plugin cache synchronization
│
├── packaging/
│   ├── codex-desktop.nsi            # NSIS installer script
│   └── codex-update-manager.xml     # Task Scheduler configuration
│
└── updater/
    ├── Cargo.toml                   # Rust updater dependencies
    └── src/
        └── main.rs                  # Rust update manager (→ .exe)
```

### Component Interaction

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   install.ps1   │────▶│  Dmg-Extractor  │────▶│    7-Zip       │
│  (Main Script)  │     │  (PowerShell)   │     │  (Extraction)  │
└────────┬────────┘     └─────────────────┘     └─────────────────┘
         │
         ├─────────────▶┌─────────────────┐     ┌─────────────────┐
         │              │ Electron-Down-   │────▶│  GitHub CDN     │
         │              │    loader       │     │  (Electron)     │
         │              └─────────────────┘     └─────────────────┘
         │
         ├─────────────▶┌─────────────────┐     ┌─────────────────┐
         │              │  patch-windows   │────▶│   app.asar      │
         │              │    (Node.js)     │     │  (Patched)      │
         │              └─────────────────┘     └─────────────────┘
         │
         ├─────────────▶┌─────────────────┐     ┌─────────────────┐
         │              │ Native-Modules   │────▶│ @electron/      │
         │              │  (Rebuilder)     │     │   rebuild       │
         │              └─────────────────┘     └─────────────────┘
         │
         └─────────────▶┌─────────────────┐     ┌─────────────────┐
                        │  Plugin-Manager  │────▶│  Plugin Cache   │
                        │  (Sync)          │     │  (%APPDATA%)    │
                        └─────────────────┘     └─────────────────┘

┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  codex-desktop- │────▶│ webview-server  │────▶│  Electron       │
│  launcher.exe   │     │   (Python)      │     │  (Windows)      │
│  (Rust)         │     │  (HTTP :5175)   │     │  (Renderer)     │
└─────────────────┘     └─────────────────┘     └─────────────────┘

┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  codex-update-  │────▶│  Task Scheduler │────▶│  OpenAI CDN     │
│  manager.exe    │     │  (Every 6hrs)   │     │  (Codex.dmg)    │
│  (Rust)         │     │                 │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

### Patch System

The `patch-windows.js` script applies seven categories of patches to the macOS app.asar:

| Patch | Purpose |
|---|---|
| Window Management | Removes macOS-specific APIs (titleBarStyle, vibrancy, traffic lights) |
| File Path Handling | Normalizes paths for Windows (backslash, USERPROFILE, APPDATA) |
| Single Instance Lock | Adds `app.requestSingleInstanceLock()` for Windows |
| System Tray | Windows-appropriate tray behavior and tooltips |
| Auto-Updater Bridge | Replaces macOS autoUpdater with Windows update manager integration |
| Desktop Name Rewrite | Adjusts .desktop → .lnk path references |
| Quit Guard | Ensures proper close/quit semantics on Windows |

### Update Flow

```
Task Scheduler → codex-update-manager.exe check
                              │
                    ┌─────────▼──────────┐
                    │  HEAD request to   │
                    │  Codex.dmg URL     │
                    └─────────┬──────────┘
                              │
                    ┌─────────▼──────────┐
                    │  Compare ETag with │
                    │  cached value      │
                    └─────────┬──────────┘
                              │
                 ┌────────────┼────────────┐
                 │ Same       │ Different   │
                 ▼            ▼            │
            No update   Download new DMG  │
                            │             │
                    ┌───────▼───────┐     │
                    │  Verify SHA   │     │
                    └───────┬───────┘     │
                    ┌───────▼───────┐     │
                    │ Create        │     │
                    │ Rollback Snap │     │
                    └───────┬───────┘     │
                    ┌───────▼───────┐     │
                    │ Rebuild       │     │
                    │ Pipeline      │     │
                    └───────┬───────┘     │
                    ┌───────▼───────┐     │
                    │ Toast         │     │
                    │ Notification  │─────┘
                    └───────────────┘
```

## License

This toolkit is provided as-is for the purpose of running the OpenAI Codex Desktop application on Windows. The Codex Desktop application itself is subject to OpenAI's terms of service.
