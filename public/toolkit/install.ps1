# install.ps1 - Main PowerShell Installer for Codex Desktop on Windows
# This script orchestrates the full installation process

param(
    [string]$InstallDir = "$env:LOCALAPPDATA\Programs\codex-desktop",
    [switch]$SkipUpdate = $false,
    [switch]$Verbose = $false
)

$ErrorActionPreference = "Stop"

# Import library modules
. "$PSScriptRoot\scripts\lib\Dmg-Extractor.ps1"
. "$PSScriptRoot\scripts\lib\Electron-Downloader.ps1"
. "$PSScriptRoot\scripts\lib\Native-Modules.ps1"
. "$PSScriptRoot\scripts\lib\Node-Runtime.ps1"
. "$PSScriptRoot\scripts\lib\Plugin-Manager.ps1"

Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Codex Desktop for Windows - Installer       ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Cyan

# Step 1: Create installation directory
Write-Host "`n[1/6] Creating installation directory..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

# Step 2: Download and extract macOS DMG
Write-Host "[2/6] Downloading Codex Desktop DMG..." -ForegroundColor Yellow
$dmgPath = Get-CodexDesktop -OutputPath "$InstallDir\temp"
$extractedPath = Expand-Dmg -DmgPath $dmgPath -OutputPath "$InstallDir\extracted"

# Step 3: Patch ASAR for Windows compatibility
Write-Host "[3/6] Patching ASAR for Windows..." -ForegroundColor Yellow
node "$PSScriptRoot\scripts\patch-windows.js" --input "$extractedPath\resources\app.asar" --output "$InstallDir\resources\app.asar"

# Step 4: Download Windows Electron runtime
Write-Host "[4/6] Downloading Windows Electron runtime..." -ForegroundColor Yellow
$electronPath = Get-ElectronRuntime -OutputPath "$InstallDir\electron"

# Step 5: Rebuild native modules
Write-Host "[5/6] Rebuilding native modules..." -ForegroundColor Yellow
Install-NodeRuntime -InstallDir $InstallDir
Build-NativeModules -AppPath "$InstallDir\resources\app.asar" -ElectronPath $electronPath

# Step 6: Configure plugins and launcher
Write-Host "[6/6] Installing plugins and creating launcher..." -ForegroundColor Yellow
Install-Plugins -InstallDir $InstallDir
Copy-Item "$PSScriptRoot\launcher\start.ps1.template" "$InstallDir\start.ps1"

# Compile Rust launcher
Push-Location "$PSScriptRoot\launcher"
cargo build --release --target x86_64-pc-windows-msvc
Copy-Item "target\release\codex-desktop.exe" "$InstallDir\codex-desktop.exe"
Pop-Location

# Register URL handler
New-ItemProperty -Path "HKCU:\SOFTWARE\Classes\codex" -Name "URL Protocol" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\SOFTWARE\Classes\codex\shell\open\command" -Name "(Default)" -Value "`"$InstallDir\codex-desktop.exe`" `"%1`""

# Cleanup
Remove-Item -Recurse -Force "$InstallDir\temp"

Write-Host "`n✅ Installation complete!" -ForegroundColor Green
Write-Host "   Launch with: $InstallDir\start.ps1" -ForegroundColor White
Write-Host "   Or use: codex-desktop.exe" -ForegroundColor White
