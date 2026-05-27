<#
.SYNOPSIS
    Windows Electron Downloader for Codex Desktop Toolkit

.DESCRIPTION
    Downloads Windows Electron binaries from GitHub releases with SHA-256
    verification, supports x64 and arm64 architectures.

.EXAMPLE
    . .\Electron-Downloader.ps1
    $result = Download-ElectronBinary -Version "34.0.0" -Architecture "x64" -OutputDir "C:\temp\electron"
#>

[CmdletBinding()]
param()

# ─── Constants ────────────────────────────────────────────────────────────────

$ELECTRON_RELEASES_URL = "https://github.com/electron/electron/releases"
$ELECTRON_CDN_URL = "https://github.com/electron/electron/releases/download"
$CACHE_DIR = Join-Path $env:LOCALAPPDATA "codex-desktop\cache\electron"

# ─── Functions ────────────────────────────────────────────────────────────────

function Get-ElectronSha256 {
    <#
    .SYNOPSIS
        Get the expected SHA-256 hash for an Electron release binary.

    .PARAMETER Version
        Electron version string (e.g., "34.0.0")

    .PARAMETER Arch
        Architecture (x64 or arm64)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Version,

        [Parameter(Mandatory)]
        [string]$Arch
    )

    $zipName = "electron-v$Version-win32-$Arch.zip"
    $shaFile = "$zipName.sha256"
    $shaUrl = "$ELECTRON_CDN_URL/v$Version/$shaFile"

    try {
        Write-Verbose "Fetching SHA-256 from $shaUrl"
        $ProgressPreference = 'SilentlyContinue'
        $response = Invoke-WebRequest -Uri $shaUrl -UseBasicParsing
        $ProgressPreference = 'Continue'
        $shaContent = $response.Content

        # Parse SHA file: "<hash>  <filename>"
        if ($shaContent -match '^([a-fA-F0-9]{64})\s') {
            return $Matches[1].ToLower()
        }

        Write-Verbose "Could not parse SHA-256 file, returning empty"
        return $null
    }
    catch {
        Write-Verbose "Could not fetch SHA-256: $_"
        return $null
    }
}

function Get-SystemArchitecture {
    <#
    .SYNOPSIS
        Detect the system architecture for Electron download.
    #>
    [CmdletBinding()]
    param()

    # Check for ARM64 Windows
    $cpuArch = (Get-CimInstance -ClassName Win32_Processor).Architecture
    # Architecture values: 5 = ARM64, 12 = ARM64 (newer), 9 = x64
    if ($cpuArch -in @(5, 12)) {
        return "arm64"
    }

    # Check processor identifier
    $procId = $env:PROCESSOR_IDENTIFIER
    if ($procId -match "ARM64") {
        return "arm64"
    }

    # Default to x64 for 64-bit systems
    if ([Environment]::Is64BitOperatingSystem) {
        return "x64"
    }

    return "x64"  # Fallback
}

function Download-ElectronBinary {
    <#
    .SYNOPSIS
        Download and extract a Windows Electron binary.

    .PARAMETER Version
        Electron version string (e.g., "34.0.0")

    .PARAMETER Architecture
        Target architecture: x64 or arm64. Auto-detected if not provided.

    .PARAMETER OutputDir
        Directory where Electron should be extracted.

    .PARAMETER SkipVerify
        Skip SHA-256 verification.

    .OUTPUTS
        Hashtable with keys:
        - ElectronPath: Path to electron.exe
        - ElectronDir:  Directory containing Electron files
        - Version:      Electron version
        - Architecture: Architecture string
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Version,

        [string]$Architecture = "",

        [Parameter(Mandatory)]
        [string]$OutputDir,

        [switch]$SkipVerify
    )

    # Auto-detect architecture
    if (-not $Architecture) {
        $Architecture = Get-SystemArchitecture
    }

    # Validate architecture
    if ($Architecture -notin @("x64", "arm64")) {
        throw "Unsupported architecture: $Architecture. Must be 'x64' or 'arm64'."
    }

    Write-Verbose "Downloading Electron v$Version for Windows ($Architecture)"

    # Build download URL
    $zipName = "electron-v$Version-win32-$Architecture.zip"
    $downloadUrl = "$ELECTRON_CDN_URL/v$Version/$zipName"

    # Check cache
    if (-not (Test-Path $CACHE_DIR)) {
        New-Item -ItemType Directory -Path $CACHE_DIR -Force | Out-Null
    }

    $cachedZip = Join-Path $CACHE_DIR $zipName
    $needDownload = $true

    if (Test-Path $cachedZip) {
        $fileSize = (Get-Item $cachedZip).Length
        if ($fileSize -gt 50MB) {
            Write-Verbose "Using cached Electron zip: $cachedZip"

            # Verify cache
            if (-not $SkipVerify) {
                $expectedHash = Get-ElectronSha256 -Version $Version -Arch $Architecture
                if ($expectedHash) {
                    $actualHash = (Get-FileHash -Path $cachedZip -Algorithm SHA256).Hash.ToLower()
                    if ($actualHash -eq $expectedHash) {
                        $needDownload = $false
                        Write-Verbose "Cached file SHA-256 verified"
                    }
                    else {
                        Write-Verbose "Cached file SHA-256 mismatch, re-downloading"
                    }
                }
                else {
                    # No hash available, trust cache
                    $needDownload = $false
                }
            }
            else {
                $needDownload = $false
            }
        }
    }

    # Download
    if ($needDownload) {
        Write-Verbose "Downloading Electron from $downloadUrl"
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $downloadUrl -OutFile $cachedZip -UseBasicParsing
            $ProgressPreference = 'Continue'
        }
        catch {
            throw "Failed to download Electron v$Version ($Architecture): $_"
        }

        # Verify downloaded file
        if (-not $SkipVerify) {
            $expectedHash = Get-ElectronSha256 -Version $Version -Arch $Architecture
            if ($expectedHash) {
                $actualHash = (Get-FileHash -Path $cachedZip -Algorithm SHA256).Hash.ToLower()
                if ($actualHash -ne $expectedHash) {
                    Remove-Item $cachedZip -Force -ErrorAction SilentlyContinue
                    throw "SHA-256 verification failed for Electron download. Expected: $expectedHash, Got: $actualHash"
                }
                Write-Verbose "SHA-256 verification passed"
            }
            else {
                Write-Verbose "SHA-256 hash not available for verification"
            }
        }

        $fileSize = (Get-Item $cachedZip).Length
        Write-Verbose "Downloaded Electron ($([math]::Round($fileSize / 1MB, 1)) MB)"
    }

    # Extract
    if (Test-Path $OutputDir) {
        Remove-Item $OutputDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

    Write-Verbose "Extracting Electron to $OutputDir"

    # Find 7-Zip
    $7zipPath = $null
    $sevenZipCandidates = @(
        "${env:ProgramFiles}\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
        (Get-Command "7z" -ErrorAction SilentlyContinue)?.Source
    )
    foreach ($candidate in $sevenZipCandidates) {
        if ($candidate -and (Test-Path $candidate)) {
            $7zipPath = $candidate
            break
        }
    }

    if ($7zipPath) {
        & $7zipPath x $cachedZip -o"$OutputDir" -y 2>&1 | ForEach-Object { Write-Verbose $_ }
    }
    else {
        # Fallback: use Expand-Archive (slower but no dependency)
        Write-Verbose "7-Zip not found, using Expand-Archive"
        Expand-Archive -Path $cachedZip -DestinationPath $OutputDir -Force
    }

    # Find electron.exe
    $electronExe = Join-Path $OutputDir "electron.exe"
    if (-not (Test-Path $electronExe)) {
        # Search in subdirectories
        $found = Get-ChildItem -Path $OutputDir -Filter "electron.exe" -Recurse |
            Select-Object -First 1
        if ($found) {
            $electronExe = $found.FullName
            $OutputDir = $found.DirectoryName
        }
        else {
            throw "electron.exe not found after extraction"
        }
    }

    Write-Verbose "Electron binary: $electronExe"

    return @{
        ElectronPath = $electronExe
        ElectronDir  = $OutputDir
        Version      = $Version
        Architecture = $Architecture
    }
}

function Get-ElectronVersions {
    <#
    .SYNOPSIS
        List available Electron versions from GitHub releases.

    .PARAMETER Count
        Number of versions to return. Defaults to 10.
    #>
    [CmdletBinding()]
    param([int]$Count = 10)

    try {
        $ProgressPreference = 'SilentlyContinue'
        $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/electron/electron/releases" -UseBasicParsing
        $ProgressPreference = 'Continue'

        return $releases |
            Select-Object -First $Count |
            ForEach-Object { $_.tag_name -replace '^v', '' }
    }
    catch {
        Write-Verbose "Could not fetch Electron versions: $_"
        return @()
    }
}

# Export functions
Export-ModuleMember -Function @(
    "Download-ElectronBinary",
    "Get-ElectronSha256",
    "Get-SystemArchitecture",
    "Get-ElectronVersions"
)
