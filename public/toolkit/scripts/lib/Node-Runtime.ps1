<#
.SYNOPSIS
    Managed Node.js Runtime for Codex Desktop Windows Toolkit

.DESCRIPTION
    Downloads and configures a pinned Node.js runtime (v22.22.2) for Windows.
    This ensures consistent behavior regardless of the system Node.js version.
    Provides node.exe, npm, and npx from the managed runtime.

.EXAMPLE
    . .\Node-Runtime.ps1
    $result = Install-NodeRuntime -Version "22.22.2" -OutputDir "C:\temp\node-runtime"
#>

[CmdletBinding()]
param()

# ─── Constants ────────────────────────────────────────────────────────────────

$DEFAULT_NODE_VERSION = "22.22.2"
$NODE_DIST_URL = "https://nodejs.org/dist"
$CACHE_DIR = Join-Path $env:LOCALAPPDATA "codex-desktop\cache\node-runtime"

# Known SHA-256 hashes for Node.js releases (update when new versions are pinned)
$KNOWN_HASHES = @{
    "22.22.2-x64"   = ""  # Populated on first download/verify
    "22.22.2-arm64" = ""  # Populated on first download/verify
}

# ─── Functions ────────────────────────────────────────────────────────────────

function Get-NodeSha256 {
    <#
    .SYNOPSIS
        Fetch the SHA-256 hash for a Node.js release from the official dist.

    .PARAMETER Version
        Node.js version string.

    .PARAMETER Arch
        Architecture (x64 or arm64).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$Arch
    )

    $sha256Url = "$NODE_DIST_URL/v$Version/SHASUMS256.txt"

    try {
        Write-Verbose "Fetching SHASUMS256.txt from $sha256Url"
        $ProgressPreference = 'SilentlyContinue'
        $response = Invoke-WebRequest -Uri $sha256Url -UseBasicParsing
        $ProgressPreference = 'Continue'

        $zipName = "node-v$Version-win-$Arch.zip"
        $lines = $response.Content -split "`n"

        foreach ($line in $lines) {
            if ($line -match "^([a-fA-F0-9]{64})\s+$([regex]::Escape($zipName))") {
                return $Matches[1].ToLower()
            }
        }

        Write-Verbose "SHA-256 not found for $zipName in SHASUMS256.txt"
        return $null
    }
    catch {
        Write-Verbose "Could not fetch SHA-256: $_"
        return $null
    }
}

function Get-RuntimeArchitecture {
    <#
    .SYNOPSIS
        Detect the appropriate architecture for Node.js download.
    #>
    [CmdletBinding()]
    param()

    $cpuArch = (Get-CimInstance -ClassName Win32_Processor).Architecture
    if ($cpuArch -in @(5, 12)) {
        return "arm64"
    }

    if ($env:PROCESSOR_IDENTIFIER -match "ARM64") {
        return "arm64"
    }

    if ([Environment]::Is64BitOperatingSystem) {
        return "x64"
    }

    return "x64"
}

function Install-NodeRuntime {
    <#
    .SYNOPSIS
        Download and extract a managed Node.js runtime for Windows.

    .PARAMETER Version
        Node.js version to install. Defaults to 22.22.2.

    .PARAMETER OutputDir
        Directory where the runtime should be extracted.

    .PARAMETER Arch
        Architecture override. Auto-detected if not provided.

    .PARAMETER SkipVerify
        Skip SHA-256 verification.

    .OUTPUTS
        Hashtable with keys:
        - NodePath:   Path to node.exe
        - NpmPath:    Path to npm.cmd
        - NpxPath:    Path to npx.cmd
        - RuntimeDir: Root directory of the runtime
        - IsManaged:  Always true for managed runtime
        - Version:    Installed version
    #>
    [CmdletBinding()]
    param(
        [string]$Version = $DEFAULT_NODE_VERSION,

        [Parameter(Mandatory)]
        [string]$OutputDir,

        [string]$Arch = "",

        [switch]$SkipVerify
    )

    # Auto-detect architecture
    if (-not $Arch) {
        $Arch = Get-RuntimeArchitecture
    }

    if ($Arch -notin @("x64", "arm64")) {
        throw "Unsupported architecture: $Arch. Must be 'x64' or 'arm64'."
    }

    Write-Verbose "Installing managed Node.js v$Version ($Arch)"

    # Build download URL
    $zipName = "node-v$Version-win-$Arch.zip"
    $downloadUrl = "$NODE_DIST_URL/v$Version/$zipName"

    # Check cache
    if (-not (Test-Path $CACHE_DIR)) {
        New-Item -ItemType Directory -Path $CACHE_DIR -Force | Out-Null
    }

    $cachedZip = Join-Path $CACHE_DIR $zipName
    $needDownload = $true

    if (Test-Path $cachedZip) {
        $fileSize = (Get-Item $cachedZip).Length
        if ($fileSize -gt 20MB) {
            Write-Verbose "Using cached Node.js zip: $cachedZip"

            if (-not $SkipVerify) {
                $expectedHash = Get-NodeSha256 -Version $Version -Arch $Arch
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
        Write-Verbose "Downloading Node.js from $downloadUrl"
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $downloadUrl -OutFile $cachedZip -UseBasicParsing
            $ProgressPreference = 'Continue'
        }
        catch {
            throw "Failed to download Node.js v$Version ($Arch): $_"
        }

        # Verify
        if (-not $SkipVerify) {
            $expectedHash = Get-NodeSha256 -Version $Version -Arch $Arch
            if ($expectedHash) {
                $actualHash = (Get-FileHash -Path $cachedZip -Algorithm SHA256).Hash.ToLower()
                if ($actualHash -ne $expectedHash) {
                    Remove-Item $cachedZip -Force -ErrorAction SilentlyContinue
                    throw "SHA-256 verification failed. Expected: $expectedHash, Got: $actualHash"
                }
                Write-Verbose "SHA-256 verification passed"

                # Cache the hash
                $KNOWN_HASHES["$Version-$Arch"] = $actualHash
            }
        }

        $fileSize = (Get-Item $cachedZip).Length
        Write-Verbose "Downloaded Node.js ($([math]::Round($fileSize / 1MB, 1)) MB)"
    }

    # Extract
    if (Test-Path $OutputDir) {
        Remove-Item $OutputDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

    Write-Verbose "Extracting Node.js to $OutputDir"

    # Try 7-Zip first (faster)
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
        # Extract to temp, then move contents (zip contains a root folder)
        $tempExtract = Join-Path $OutputDir "_temp_extract"
        & $7zipPath x $cachedZip -o"$tempExtract" -y 2>&1 | ForEach-Object { Write-Verbose $_ }

        # Move contents from nested folder
        $nestedDir = Get-ChildItem -Path $tempExtract -Directory | Select-Object -First 1
        if ($nestedDir) {
            Get-ChildItem -Path $nestedDir.FullName | ForEach-Object {
                Move-Item $_.FullName (Join-Path $OutputDir $_.Name) -Force
            }
        }

        Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
    }
    else {
        # Fallback to Expand-Archive
        $tempExtract = Join-Path $OutputDir "_temp_extract"
        Expand-Archive -Path $cachedZip -DestinationPath $tempExtract -Force

        $nestedDir = Get-ChildItem -Path $tempExtract -Directory | Select-Object -First 1
        if ($nestedDir) {
            Get-ChildItem -Path $nestedDir.FullName | ForEach-Object {
                Move-Item $_.FullName (Join-Path $OutputDir $_.Name) -Force
            }
        }

        Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Verify extraction
    $nodeExe = Join-Path $OutputDir "node.exe"
    if (-not (Test-Path $nodeExe)) {
        # Search recursively
        $found = Get-ChildItem -Path $OutputDir -Filter "node.exe" -Recurse |
            Select-Object -First 1
        if ($found) {
            # Flatten structure
            $runtimeRoot = $found.DirectoryName
            Write-Verbose "Node.exe found in subdirectory, adjusting paths"
        }
        else {
            throw "node.exe not found after extraction"
        }
    }

    # Verify node.exe works
    $nodeVersion = & $nodeExe --version 2>&1
    Write-Verbose "Node.js runtime version: $nodeVersion"

    $npmCmd = Join-Path $OutputDir "npm.cmd"
    $npxCmd = Join-Path $OutputDir "npx.cmd"

    # If npm.cmd doesn't exist, check for npm in subdirectory
    if (-not (Test-Path $npmCmd)) {
        $npmFound = Get-ChildItem -Path $OutputDir -Filter "npm.cmd" -Recurse |
            Select-Object -First 1
        if ($npmFound) {
            $npmCmd = $npmFound.FullName
            $npxCmd = $npmCmd -replace "npm\.cmd", "npx.cmd"
        }
    }

    Write-Verbose "Node.js runtime installed:"
    Write-Verbose "  node: $nodeExe"
    Write-Verbose "  npm:  $npmCmd"
    Write-Verbose "  npx:  $npxCmd"

    return @{
        NodePath   = $nodeExe
        NpmPath    = $npmCmd
        NpxPath    = $npxCmd
        RuntimeDir = $OutputDir
        IsManaged  = $true
        Version    = $Version
        Arch       = $Arch
    }
}

function Test-NodeRuntime {
    <#
    .SYNOPSIS
        Verify a managed Node.js runtime installation.

    .PARAMETER RuntimeDir
        Directory containing the managed Node.js runtime.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RuntimeDir)

    $nodeExe = Join-Path $RuntimeDir "node.exe"
    $npmCmd = Join-Path $RuntimeDir "npm.cmd"

    $nodeOk = Test-Path $nodeExe
    $npmOk = Test-Path $npmCmd

    if ($nodeOk) {
        $version = & $nodeExe --version 2>&1
        Write-Verbose "Node.js: $version"
    }

    if ($npmOk) {
        $npmVersion = & $npmCmd --version 2>&1
        Write-Verbose "npm: $npmVersion"
    }

    return @{
        NodeAvailable = $nodeOk
        NpmAvailable  = $npmOk
        NodePath      = $nodeExe
        NpmPath       = $npmCmd
    }
}

# Export functions
Export-ModuleMember -Function @(
    "Install-NodeRuntime",
    "Test-NodeRuntime",
    "Get-NodeSha256",
    "Get-RuntimeArchitecture"
)
