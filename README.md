# Codex Desktop for Windows

> Run OpenAI's Codex Desktop on Windows — unofficial community port with native `.exe` launcher, PowerShell installer, and Rust-based auto-updater.

[![Windows](https://img.shields.io/badge/platform-Windows-0078D4?logo=windows)](https://github.com/roman-ryzenadvanced/codex-desktop-windows)
[![Rust](https://img.shields.io/badge/launcher-Rust-CE412B?logo=rust)](https://www.rust-lang.org/)
[![Electron](https://img.shields.io/badge/shell-Electron-47848F?logo=electron)](https://www.electronjs.org/)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

**Upstream:** [ilysenko/codex-desktop-linux](https://github.com/ilysenko/codex-desktop-linux) — the original Linux port that this project adapts for Windows.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [How It Works: Linux → Windows Conversion](#how-it-works-linux--windows-conversion)
  - [1. Shell Scripts → PowerShell](#1-shell-scripts--powershell)
  - [2. .desktop Files → Windows Registry & Shortcuts](#2-desktop-files--windows-registry--shortcuts)
  - [3. Path System Overhaul](#3-path-system-overhaul)
  - [4. Process Management](#4-process-management)
  - [5. Single Instance Enforcement](#5-single-instance-enforcement)
  - [6. DMG Extraction on Windows](#6-dmg-extraction-on-windows)
  - [7. Electron Flag Changes](#7-electron-flag-changes)
  - [8. ASAR Patch System](#8-asar-patch-system)
  - [9. Auto-Update System](#9-auto-update-system)
  - [10. Packaging & Distribution](#10-packaging--distribution)
  - [11. Computer Use & Accessibility](#11-computer-use--accessibility)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Building from Source](#building-from-source)
  - [Build the .exe Launcher](#build-the-exe-launcher)
  - [Build the NSIS Installer](#build-the-nsis-installer)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [Comparison: Linux vs Windows](#comparison-linux-vs-windows)
- [Contributing](#contributing)
- [License](#license)
- [Disclaimer](#disclaimer)

---

## Overview

The [codex-desktop-linux](https://github.com/ilysenko/codex-desktop-linux) project converts the macOS-only OpenAI Codex Desktop app (distributed as a `.dmg`) into a runnable Linux Electron application. It works by:

1. Downloading the macOS Codex Desktop DMG
2. Extracting the app bundle
3. Patching the `app.asar` for Linux compatibility
4. Downloading the matching Linux Electron binary
5. Rebuilding native Node modules for Linux
6. Creating a launcher script and system integration

**This project** takes the same concept and adapts it for **Windows**, converting every Linux-specific component to its Windows equivalent. The result is a fully functional Windows application launched via a native Rust `.exe`.

### Key Features

- 🖥️ **Windows Native** — Runs as a native Windows application with Rust `.exe` launcher
- 🔄 **Auto-Update** — Automatic updates with rollback support via Windows Task Scheduler
- 🔌 **Plugin System** — MCP plugin support (Computer Use, Read Aloud, Browser Use)
- 🛡️ **Single Instance** — Named mutex-based single instance enforcement
- 📦 **Easy Install** — PowerShell installer with one-command setup
- 🌐 **Webview Server** — Local Python HTTP server with Windows Job Object integration
- 📝 **NSIS Packaging** — Full Windows installer with shortcuts, URL protocol, and uninstaller

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                    Codex Desktop for Windows                     │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  codex-desktop.exe (Rust Launcher)                              │
│  ├── Finds installation directory                               │
│  ├── Starts Python webview-server.py on 127.0.0.1:5175          │
│  ├── Waits for server readiness (TCP connect)                   │
│  ├── Launches electron.exe with --load-url                      │
│  ├── Manages process lifecycle (kill children on exit)          │
│  └── Single instance via named mutex                            │
│                                                                  │
│  electron.exe (Windows Electron)                                │
│  ├── Loads patched app.asar                                     │
│  ├── Connects to webview server for UI assets                   │
│  └── Renders Codex Desktop interface                            │
│                                                                  │
│  webview-server.py (Python HTTP Server)                         │
│  ├── Serves content/webview/ on 127.0.0.1:5175                  │
│  ├── ThreadingHTTPServer with no-cache headers                  │
│  ├── SPA fallback routing                                       │
│  ├── Health & shutdown API endpoints                            │
│  └── Parent-death monitoring via Windows Job Objects             │
│                                                                  │
│  codex-update-manager.exe (Rust Updater)                        │
│  ├── ETag-based upstream DMG change detection                   │
│  ├── DMG download with SHA-256 verification                     │
│  ├── Rebuild pipeline orchestration                             │
│  ├── Windows toast notifications                                │
│  ├── UAC elevation for installs                                 │
│  └── Rollback snapshot management                               │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### Conversion Pipeline

```
  DMG Download ──► Extract ──► Patch ASAR ──► Download Win Electron ──► Rebuild Natives ──► Install ──► Launch
       │              │            │                    │                      │               │           │
   Curl/Invoke   7-Zip      patch-windows.js   GitHub Releases       @electron/rebuild    Plugin      .exe
   WebRequest    (HFS+)     (7 categories)     (x64/arm64)            (better-sqlite3)    Manager     Launcher
```

---

## How It Works: Linux → Windows Conversion

This section details every subsystem that was adapted from the Linux version to Windows.

### 1. Shell Scripts → PowerShell

Every `.sh` file was rewritten as a PowerShell equivalent with proper Windows conventions:

| Linux | Windows | Key Changes |
|-------|---------|-------------|
| `install.sh` | `install.ps1` | `param()` instead of `getopts`, `Write-Host` instead of `echo`, `[CmdletBinding()]` |
| `launcher/start.sh.template` | `launcher/start.ps1.template` | `$PSScriptRoot` instead of `$(dirname "$0")`, `Join-Path` instead of string concatenation |
| `scripts/lib/*.sh` | `scripts/lib/*.ps1` | `Test-Path` instead of `[ -f ]`, `Start-Process` instead of `&`, try/catch instead of `set -e` |
| `scripts/build-deb.sh` | `packaging/codex-desktop.nsi` | NSIS installer instead of dpkg-deb |

**PowerShell conventions used:**
```powershell
# Parameter declaration
param(
    [string]$InstallDir = "$env:LOCALAPPDATA\Programs\codex-desktop",
    [switch]$SkipUpdate = $false
)

# Path construction (never string concatenation)
$electronExe = Join-Path $InstallDir "electron\electron.exe"

# File existence check
if (Test-Path $electronExe) { ... }

# Process launch
$process = Start-Process -FilePath $electronExe -ArgumentList @(...) -PassThru

# Registry manipulation (URL protocol)
New-ItemProperty -Path "HKCU:\SOFTWARE\Classes\codex" -Name "URL Protocol" -Force
```

### 2. .desktop Files → Windows Registry & Shortcuts

The Linux `.desktop` file (freedesktop.org standard) was replaced with Windows equivalents:

| Linux (.desktop) | Windows Equivalent |
|------------------|-------------------|
| `Name=Codex Desktop` | Start Menu shortcut (`.lnk`) |
| `Exec=/usr/bin/codex-desktop %u` | Registry `HKCU:\SOFTWARE\Classes\codex\shell\open\command` |
| `Icon=codex-desktop` | Icon embedded in .exe / .ico file |
| `MimeType=x-scheme-handler/codex` | URL Protocol registration via Registry |
| `StartupWMClass=codex-desktop` | `--app-user-model-id=CodexDesktop` Electron flag |
| `Desktop Actions` | Jump lists / taskbar context menu |

**URL Protocol Registration (Windows):**
```powershell
# Register codex:// URL scheme
$regPath = "HKCU:\SOFTWARE\Classes\codex"
Set-ItemProperty -Path $regPath -Name "(Default)" -Value "URL:Codex Desktop Protocol"
Set-ItemProperty -Path $regPath -Name "URL Protocol" -Value ""
Set-ItemProperty -Path "$regPath\shell\open\command" -Name "(Default)" -Value "`"$exePath`" --url `"%1`""
```

### 3. Path System Overhaul

All Linux-specific paths were mapped to Windows conventions:

| Linux Path | Windows Equivalent | Environment Variable |
|-----------|-------------------|---------------------|
| `/opt/codex-desktop/` | `C:\Program Files\Codex Desktop\` | `%ProgramFiles%` |
| `~/.config/codex-desktop/` | `C:\Users\<user>\AppData\Roaming\codex-desktop\` | `%APPDATA%` |
| `~/.local/state/codex-update-manager/` | `C:\Users\<user>\AppData\Local\codex-update-manager\` | `%LOCALAPPDATA%` |
| `~/.cache/codex-desktop/` | `C:\Users\<user>\AppData\Local\codex-desktop\cache\` | `%LOCALAPPDATA%` |
| `~/.codex/` | `C:\Users\<user>\.codex\` | `%USERPROFILE%\.codex` |
| `/usr/bin/codex-desktop` | `C:\Program Files\Codex Desktop\codex-desktop.exe` | — |
| `/usr/share/applications/` | Start Menu folder | — |
| `/usr/share/icons/` | Embedded in .exe / `%ProgramData%` | — |
| `/tmp/` | `C:\Users\<user>\AppData\Local\Temp\` | `%TEMP%` |
| `/proc/<pid>/cmdline` | `Get-Process` / WMI | — |

### 4. Process Management

| Concept | Linux Implementation | Windows Implementation |
|---------|---------------------|----------------------|
| Parent-death detection | `prctl(PR_SET_PDEATHSIG, SIGKILL)` | Windows Job Objects with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` |
| Process tree kill | `kill -- -$PGID` | `Stop-Process -Id $pid -Force` + `Get-NetTCPConnection` cleanup |
| PID files | `/run/user/<uid>/codex-desktop.pid` | `%LOCALAPPDATA%\codex-desktop\codex-desktop.pid` |
| Orphan cleanup | Port check via `/proc/net/tcp` | `Get-NetTCPConnection -LocalPort $Port` |
| Background service | `systemctl --user` | Task Scheduler |

**Windows Job Object setup (Python):**
```python
import ctypes
from ctypes import wintypes

kernel32 = ctypes.windll.kernel32
JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000

job = kernel32.CreateJobObjectW(None, None)
info = JOBOBJECT_EXTENDED_LIMIT_INFORMATION()
info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
kernel32.SetInformationJobObject(job, 9, ctypes.byref(info), ctypes.sizeof(info))
kernel32.AssignProcessToJobObject(job, kernel32.GetCurrentProcess())
```

### 5. Single Instance Enforcement

| Linux | Windows |
|-------|---------|
| Unix domain socket (`/tmp/codex-desktop.sock`) | Named Mutex (`Global\CodexDesktopSingleInstance`) |
| `bind()` + `listen()` success = first instance | `CreateMutexW()` success = first instance |
| Connect to socket = second instance | `GetLastError() == ERROR_ALREADY_EXISTS` = second instance |

**Rust implementation (windows crate v0.58):**
```rust
const MUTEX_NAME: &str = "Global\\CodexDesktopSingleInstance";

fn create_named_mutex(name: &str) -> anyhow::Result<()> {
    let wide_name: Vec<u16> = name.encode_utf16().chain(std::iter::once(0)).collect();
    unsafe {
        CreateMutexW(None, true, PCWSTR(wide_name.as_ptr()))
            .map_err(|e| anyhow::anyhow!("Failed to create mutex '{}': {}", name, e))?;
    }
    Ok(())
}

fn enforce_single_instance() -> Result<Option<()>> {
    match create_named_mutex(MUTEX_NAME) {
        Ok(()) => Ok(None),     // We got the mutex, continue
        Err(_) => Ok(Some(())), // Another instance exists
    }
}
```

### 6. DMG Extraction on Windows

Linux uses `7z`/`7zz` to extract macOS DMGs. On Windows, 7-Zip also supports HFS+ and APFS:

```powershell
# Dmg-Extractor.ps1
function Expand-Dmg {
    param([string]$DmgPath, [string]$OutputPath)

    # Try 7-Zip first (supports HFS+ and APFS on Windows)
    $7zPaths = @(
        "${env:ProgramFiles}\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
        (Get-Command "7z" -ErrorAction SilentlyContinue)?.Source
    )

    foreach ($7z in $7zPaths) {
        if (Test-Path $7z) {
            & $7z x $DmgPath -o"$OutputPath" -y
            return $OutputPath
        }
    }

    throw "7-Zip is required for DMG extraction"
}
```

### 7. Electron Flag Changes

| Linux Flag | Windows Equivalent | Reason |
|-----------|-------------------|--------|
| `--ozone-platform=x11` | *(removed)* | Windows uses its own windowing system |
| `--ozone-platform-hint=auto` | *(removed)* | Not needed on Windows |
| `--enable-features=WaylandWindowDecorations` | *(removed)* | Wayland doesn't exist on Windows |
| `--class=codex-desktop` | `--app-user-model-id=CodexDesktop` | Windows uses AppUserModelID for taskbar grouping |
| `--no-sandbox` | `--no-sandbox` | Still needed |
| `--disable-gpu-sandbox` | `--disable-gpu-sandbox` | Still needed on some configs |
| *(not used)* | `--load-url=http://127.0.0.1:5175` | Explicit URL loading |

### 8. ASAR Patch System

The `patch-windows.js` script applies 7 categories of patches to the extracted `app.asar`:

1. **Window Management** — Replace `titleBarStyle: 'hiddenInset'` → `'default'`, remove `trafficLightPosition`, replace `vibrancy`
2. **File Path Handling** — `process.env.HOME` → `process.env.USERPROFILE || process.env.HOME`, `/tmp` → `os.tmpdir()`, `.split('/')` → `.split(path.sep)`
3. **Single Instance Lock** — Inject `app.requestSingleInstanceLock()` with `second-instance` handler
4. **System Tray** — Add `tray.setToolTip()`, `app.setAppUserModelId('CodexDesktop')`
5. **Auto-Updater Bridge** — Stub macOS `autoUpdater`, delegate to `codex-update-manager`
6. **Desktop Name Rewrite** — `.desktop` → `.lnk`, `/usr/share/applications` → `Start Menu`
7. **Quit Guard** — Always `app.quit()` on `window-all-closed` (not just `!== 'darwin'`)

### 9. Auto-Update System

| Component | Linux | Windows |
|-----------|-------|---------|
| Service manager | systemd user service | Task Scheduler (XML) |
| Check interval | 6 hours (systemd timer) | 6 hours (scheduled task) |
| Privileged install | `pkexec` (Polkit) | `runas /user:admin` (UAC) |
| Notifications | `notify-rust` (libnotify) | Windows Toast Notifications (`windows` crate) |
| Package format | `.deb` / `.rpm` / `.pkg.tar.zst` | NSIS `.exe` |
| Rollback | `apt/dnf/pacman` downgrade | Snapshot-based rollback |
| State file | `~/.local/state/codex-update-manager/state.json` | `%LOCALAPPDATA%\codex-update-manager\state.json` |
| Config file | `~/.config/codex-update-manager/config.toml` | `%APPDATA%\codex-update-manager\config.toml` |
| Lock file | `flock` (Linux) | `fs4` (cross-platform file locking) |

**Task Scheduler XML** (`codex-update-manager.xml`):
```xml
<Task>
  <Triggers>
    <TimeTrigger>
      <Repetition>
        <Interval>PT6H</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>2025-01-01T00:00:00</StartBoundary>
    </TimeTrigger>
    <LogonTrigger><Enabled>true</Enabled></LogonTrigger>
  </Triggers>
  <Actions>
    <Exec>
      <Command>C:\Program Files\Codex Desktop\codex-update-manager.exe</Command>
      <Arguments>--check --update</Arguments>
    </Exec>
  </Actions>
</Task>
```

### 10. Packaging & Distribution

| Linux Format | Tool | Windows Format | Tool |
|-------------|------|---------------|------|
| `.deb` | `dpkg-deb` | `.exe` installer | NSIS (Nullsoft Scriptable Install System) |
| `.rpm` | `rpmbuild` | `.msi` | WiX Toolset (optional) |
| `.pkg.tar.zst` | `makepkg` | Chocolatey `.nupkg` | choco pack (optional) |
| AppImage | `appimagetool` | Portable `.zip` | Archive (optional) |
| `PKGBUILD` | pacman | `winget` manifest | winget (optional) |

**NSIS Installer Features:**
- Install directory selection (`C:\Program Files\Codex Desktop`)
- Start Menu shortcuts
- Desktop shortcut (optional)
- URL protocol handler registration (`codex://`)
- Registry entries for Add/Remove Programs
- Uninstaller with clean removal

### 11. Computer Use & Accessibility

| Linux Backend | Windows Equivalent |
|--------------|-------------------|
| AT-SPI (Accessibility Toolkit) | Windows UI Automation |
| Wayland protocols | Windows Accessibility API |
| XDG Desktop Portal | Windows Shell APIs |
| GNOME Shell extension | Windows Shell extensions |
| `ydotool` / `uinput` | Win32 `SendInput` |
| `xdotool` | Windows UI Automation patterns |
| KWin scripting | Windows Automation |
| Hyprland IPC | Not applicable |
| i3 IPC + `xprop` | Not applicable |
| `evdev` input | Raw Input API |

> **Note:** The Computer Use plugin on Windows uses Windows UI Automation instead of AT-SPI. This requires a separate Rust backend compiled for Windows.

---

## Project Structure

```
codex-desktop-windows/
├── install.ps1                    # Main PowerShell installer
├── Cargo.toml                     # Rust workspace root (launcher + updater)
├── README.md                      # This file
│
├── launcher/
│   ├── Cargo.toml                 # Launcher crate config
│   ├── start.ps1.template         # Windows launcher template (generated at install)
│   ├── webview-server.py          # Cross-platform HTTP server for webview assets
│   └── src/
│       └── main.rs                # Rust .exe launcher source (2.2MB compiled with LTO+strip)
│
├── scripts/
│   ├── patch-windows.js           # ASAR patch system (7 categories of patches)
│   └── lib/
│       ├── Dmg-Extractor.ps1      # DMG download + extraction (7-Zip, SHA-256)
│       ├── Electron-Downloader.ps1 # Windows Electron binary downloader
│       ├── Native-Modules.ps1     # Native module rebuilder (@electron/rebuild)
│       ├── Node-Runtime.ps1       # Managed Node.js v22.22.2 runtime
│       └── Plugin-Manager.ps1     # Plugin cache sync + native messaging host
│
├── packaging/
│   ├── codex-desktop.nsi          # NSIS installer script
│   └── codex-update-manager.xml   # Task Scheduler XML for auto-updates
│
├── updater/
│   ├── Cargo.toml                 # Updater crate config
│   └── src/
│       └── main.rs                # Windows updater with toast notifications
│
└── src/                           # Next.js web showcase (this repository)
    ├── app/
    │   ├── page.tsx               # Main page
    │   └── api/toolkit/           # API route for file browsing
    └── components/                # UI components
```

---

## Prerequisites

### For Installation
- **Windows 10/11** (x64 or arm64)
- **PowerShell 5.1+** (included with Windows) or PowerShell 7+
- **Python 3.8+** — for the webview HTTP server
- **7-Zip** — for DMG extraction
- **Node.js 18+** — for native module rebuilds

### For Building from Source
- All of the above, plus:
- **Rust toolchain** — `rustup` with `x86_64-pc-windows-msvc` target
- **Visual Studio Build Tools** — for compiling native Node modules
- **NSIS 3.x** — for building the installer

---

## Installation

### Option 1: Quick Install (PowerShell)

```powershell
# Clone the repository
git clone https://github.com/roman-ryzenadvanced/codex-desktop-windows.git
cd codex-desktop-windows

# Run the installer
.\install.ps1

# Launch Codex Desktop
.\start.ps1
# or
.\codex-desktop.exe
```

### Option 2: Download Release

1. Go to [Releases](https://github.com/roman-ryzenadvanced/codex-desktop-windows/releases)
2. Download the latest `codex-desktop-launcher.exe`
3. Run the installer and follow the wizard
4. Launch from Start Menu or Desktop shortcut

### Option 3: Portable (No Install)

1. Download `codex-desktop.zip` from Releases
2. Extract to any directory
3. Run `codex-desktop.exe`

---

## Building from Source

### Build the .exe Launcher

```powershell
# Install Rust (if not already installed)
winget install Rustlang.Rustup

# Add Windows target
rustup target add x86_64-pc-windows-msvc

# Build
cd launcher
cargo build --release

# Output: target/release/codex-desktop-launcher.exe (2.2MB with LTO+strip)
```

#### Cross-Compile from Linux

```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Install Zig (cross-compilation toolchain)
curl -L https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz | tar -xJ
export PATH="$PWD/zig-linux-x86_64-0.13.0:$PATH"

# Install cargo-zigbuild
cargo install cargo-zigbuild

# Add Windows target
rustup target add x86_64-pc-windows-gnu

# Build from workspace root
cd toolkit  # (or codex-desktop-windows/public/toolkit)
cargo zigbuild --release --target x86_64-pc-windows-gnu -p codex-desktop-launcher

# Output: target/x86_64-pc-windows-gnu/release/codex-desktop-launcher.exe (2.2MB)
```

### Build the NSIS Installer

```powershell
# Install NSIS
winget install NSIS.NSIS

# Build the installer
cd packaging
makensis codex-desktop.nsi

# Output: codex-desktop-windows-installer.exe
```

---

## Configuration

### Updater Configuration

Location: `%APPDATA%\codex-update-manager\config.toml`

```toml
dmg_url = "https://persistent.oaistatic.com/codex-app-prod/Codex.dmg"
check_interval_hours = 6
auto_update = false
show_notifications = true
enable_rollback = true
max_rollback_snapshots = 3
```

### Launcher Configuration

The launcher reads template variables from `start.ps1` (set during installation):

| Variable | Default | Description |
|----------|---------|-------------|
| `$INSTALL_DIR` | `$env:LOCALAPPDATA\Programs\codex-desktop` | App installation directory |
| `$ELECTRON_VERSION` | Auto-detected | Electron version from DMG |
| `$DEFAULT_PORT` | `5175` | Webview server port |
| `$NODE_RUNTIME_DIR` | `<install>\resources\node-runtime` | Managed Node.js path |

---

## Troubleshooting

### "Python not found"
Install Python 3.8+ from [python.org](https://www.python.org/) or Microsoft Store. Ensure "Add to PATH" is checked during installation.

### "7-Zip not found"
Install 7-Zip from [7-zip.org](https://www.7-zip.org/). The installer checks both `Program Files` locations.

### "Port 5175 already in use"
The launcher automatically finds the next available port (5175-5185). If all are in use, use `--port` to specify a custom port:
```powershell
.\start.ps1 -Port 8080
# or
.\codex-desktop.exe --port 8080
```

### "Another instance is already running"
Only one instance of Codex Desktop can run at a time (enforced by named mutex). Check the system tray or use Task Manager to find the existing instance.

### "electron.exe not found"
The installer downloads the Windows Electron binary automatically. If it fails, re-run `.\install.ps1` with the `-Fresh` flag.

### Window doesn't appear
Check logs at `%LOCALAPPDATA%\codex-desktop\logs\`. Common issues:
- GPU driver incompatibility → add `--disable-gpu` flag
- Antivirus blocking → whitelist the installation directory

---

## Comparison: Linux vs Windows

| Feature | Linux | Windows |
|---------|-------|---------|
| **Installer** | `install.sh` | `install.ps1` |
| **Launcher** | `start.sh` | `start.ps1` + `codex-desktop.exe` |
| **Packaging** | `.deb` / `.rpm` / `pacman` | NSIS `.exe` installer |
| **Auto-update** | systemd user service | Task Scheduler |
| **Computer Use** | AT-SPI / Wayland / evdev | Windows UI Automation / SendInput |
| **Single Instance** | Unix domain socket | Named Mutex |
| **URL Handler** | `xdg-mime` | Registry (`HKCU:\SOFTWARE\Classes`) |
| **Notifications** | libnotify (`notify-rust`) | Windows Toast Notifications |
| **Privileged Install** | Polkit (`pkexec`) | UAC (`runas`) |
| **Process Cleanup** | `prctl(PR_SET_PDEATHSIG)` | Windows Job Objects |
| **Config Directory** | `~/.config/` | `%APPDATA%\` |
| **State Directory** | `~/.local/state/` | `%LOCALAPPDATA%\` |
| **Cache Directory** | `~/.cache/` | `%LOCALAPPDATA%\` |

---

## Contributing

Contributions are welcome! This is a community-driven project.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

The upstream project [codex-desktop-linux](https://github.com/ilysenko/codex-desktop-linux) is also MIT licensed.

---

## Disclaimer

This project is **not affiliated with, endorsed by, or connected to OpenAI**. Codex Desktop is a trademark of OpenAI. This is an unofficial community port that converts the macOS application to run on Windows.

This project does **not redistribute** OpenAI's software. It downloads the upstream DMG from OpenAI's public CDN and converts it locally on your machine, following the same approach as the Linux version.
