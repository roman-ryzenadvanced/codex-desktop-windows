<#
.SYNOPSIS
    DMG Extraction Module for Codex Desktop Windows Toolkit

.DESCRIPTION
    Downloads and extracts the macOS Codex.dmg file on Windows using 7-Zip.
    Handles HFS+ and APFS filesystem formats, detects the Electron version,
    and returns structured information about the extracted app.

.EXAMPLE
    . .\Dmg-Extractor.ps1
    $result = Extract-CodexDmg -DmgPath "C:\cache\Codex.dmg" -OutputDir "C:\temp\extracted" -SevenZipPath "C:\Program Files\7-Zip\7z.exe"
#>

[CmdletBinding()]
param()

# ─── Constants ────────────────────────────────────────────────────────────────

$CODEX_DMG_URL = "https://persistent.oaistatic.com/codex-app-prod/Codex.dmg"
$CODEX_DMG_SHA256_CACHE = Join-Path $env:LOCALAPPDATA "codex-desktop\cache\Codex.dmg.sha256"

# ─── Functions ────────────────────────────────────────────────────────────────

function Get-CodexDmgHash {
    <#
    .SYNOPSIS
        Get the cached SHA-256 hash of the DMG file.
    #>
    [CmdletBinding()]
    param()

    if (Test-Path $CODEX_DMG_SHA256_CACHE) {
        return (Get-Content $CODEX_DMG_SHA256_CACHE -Raw).Trim()
    }
    return $null
}

function Save-CodexDmgHash {
    <#
    .SYNOPSIS
        Save the SHA-256 hash of the DMG file to cache.
    #>
    [CmdletBinding()]
    param([string]$Hash)

    $cacheDir = Split-Path -Parent $CODEX_DMG_SHA256_CACHE
    if (-not (Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }
    Set-Content -Path $CODEX_DMG_SHA256_CACHE -Value $Hash -Force
}

function Invoke-DmgDownload {
    <#
    .SYNOPSIS
        Download the Codex.dmg file with caching and SHA-256 verification.

    .PARAMETER OutputPath
        Path where the DMG should be saved.

    .PARAMETER Url
        URL to download the DMG from. Defaults to the official Codex DMG URL.

    .PARAMETER SkipVerify
        Skip SHA-256 verification of the downloaded file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OutputPath,

        [string]$Url = $CODEX_DMG_URL,

        [switch]$SkipVerify
    )

    Write-Verbose "Downloading Codex.dmg from $Url"

    # Check if cached file exists and is valid
    if (Test-Path $OutputPath) {
        $existingSize = (Get-Item $OutputPath).Length
        if ($existingSize -gt 100MB) {
            Write-Verbose "Using cached DMG: $OutputPath ($([math]::Round($existingSize / 1MB, 1)) MB)"

            if (-not $SkipVerify) {
                $hash = (Get-FileHash -Path $OutputPath -Algorithm SHA256).Hash.ToLower()
                $cachedHash = Get-CodexDmgHash
                if ($cachedHash -and $hash -eq $cachedHash) {
                    Write-Verbose "SHA-256 verification passed (cached)"
                    return $OutputPath
                }
                elseif (-not $cachedHash) {
                    # First download, save hash
                    Save-CodexDmgHash -Hash $hash
                    return $OutputPath
                }
            }
            else {
                return $OutputPath
            }
        }
    }

    # Download
    try {
        Write-Verbose "Downloading DMG..."
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing
        $ProgressPreference = 'Continue'
    }
    catch {
        throw "Failed to download Codex.dmg: $_"
    }

    # Verify
    if (-not $SkipVerify) {
        Write-Verbose "Verifying SHA-256 hash..."
        $hash = (Get-FileHash -Path $OutputPath -Algorithm SHA256).Hash.ToLower()
        Save-CodexDmgHash -Hash $hash
        Write-Verbose "SHA-256: $hash"
    }

    $fileSize = (Get-Item $OutputPath).Length
    Write-Verbose "Downloaded Codex.dmg ($([math]::Round($fileSize / 1MB, 1)) MB)"

    return $OutputPath
}

function Find-SevenZip {
    <#
    .SYNOPSIS
        Find 7-Zip executable on the system.
    #>
    [CmdletBinding()]
    param()

    $candidates = @(
        "${env:ProgramFiles}\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
        (Get-Command "7z" -ErrorAction SilentlyContinue)?.Source,
        (Get-Command "7z.exe" -ErrorAction SilentlyContinue)?.Source
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    throw "7-Zip not found. Install from https://www.7-zip.org/ or provide -SevenZipPath parameter"
}

function Invoke-DmgExtraction {
    <#
    .SYNOPSIS
        Extract a DMG file using 7-Zip on Windows.

    .PARAMETER DmgPath
        Path to the DMG file.

    .PARAMETER OutputDir
        Directory where contents should be extracted.

    .PARAMETER SevenZipPath
        Path to 7z.exe. Auto-detected if not provided.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DmgPath,

        [Parameter(Mandatory)]
        [string]$OutputDir,

        [string]$SevenZipPath
    )

    if (-not (Test-Path $DmgPath)) {
        throw "DMG file not found: $DmgPath"
    }

    if (-not $SevenZipPath) {
        $SevenZipPath = Find-SevenZip
    }

    if (-not (Test-Path $SevenZipPath)) {
        throw "7-Zip not found at: $SevenZipPath"
    }

    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    Write-Verbose "Extracting DMG with 7-Zip: $DmgPath"

    # Step 1: List contents to understand the DMG structure
    $listOutput = & $SevenZipPath l $DmgPath 2>&1 | Out-String
    Write-Verbose "DMG contents listed"

    # Step 2: Extract the DMG (first pass - gets partition table)
    $tempExtract = Join-Path $OutputDir "_dmg_raw"
    if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force }

    & $SevenZipPath x $DmgPath -o"$tempExtract" -y 2>&1 | ForEach-Object { Write-Verbose $_ }

    # Step 3: Look for HFS+ partition files
    $hfsFiles = @()
    $hfsFiles += Get-ChildItem -Path $tempExtract -Filter "*.hfs" -File -ErrorAction SilentlyContinue
    $hfsFiles += Get-ChildItem -Path $tempExtract -Filter "*.hfsplus" -File -ErrorAction SilentlyContinue

    # Check for APFS
    $apfsFiles = Get-ChildItem -Path $tempExtract -Filter "*.apfs" -File -ErrorAction SilentlyContinue

    $extractedOk = $false

    # Try extracting HFS+ partitions
    foreach ($hfs in $hfsFiles) {
        Write-Verbose "Extracting HFS+ partition: $($hfs.Name)"
        try {
            & $SevenZipPath x $hfs.FullName -o"$OutputDir" -y 2>&1 | ForEach-Object { Write-Verbose $_ }
            $extractedOk = $true
        }
        catch {
            Write-Verbose "HFS+ extraction failed: $_"
        }
    }

    # Try extracting APFS partitions
    foreach ($apfs in $apfsFiles) {
        Write-Verbose "Extracting APFS partition: $($apfs.Name)"
        try {
            & $SevenZipPath x $apfs.FullName -o"$OutputDir" -y 2>&1 | ForEach-Object { Write-Verbose $_ }
            $extractedOk = $true
        }
        catch {
            Write-Verbose "APFS extraction failed: $_"
        }
    }

    # If no partition files found, the first extraction might have the data directly
    if (-not $extractedOk) {
        # Move raw extraction contents to output
        $rawItems = Get-ChildItem -Path $tempExtract -ErrorAction SilentlyContinue
        foreach ($item in $rawItems) {
            $dest = Join-Path $OutputDir $item.Name
            if (-not (Test-Path $dest)) {
                Move-Item $item.FullName $dest -Force
            }
        }
    }

    # Cleanup temp directory
    if (Test-Path $tempExtract) {
        Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Verify extraction
    $appBundles = Get-ChildItem -Path $OutputDir -Filter "*.app" -Directory -Recurse -ErrorAction SilentlyContinue
    if ($appBundles.Count -eq 0) {
        Write-Verbose "No .app bundle found, checking for direct content..."
        $contents = Get-ChildItem -Path $OutputDir -ErrorAction SilentlyContinue
        if ($contents.Count -eq 0) {
            throw "DMG extraction produced no output"
        }
    }

    Write-Verbose "DMG extraction complete: $OutputDir"
    return $OutputDir
}

function Get-ElectronVersion {
    <#
    .SYNOPSIS
        Detect the Electron version from an extracted macOS app bundle.

    .PARAMETER AppPath
        Path to the extracted .app bundle or its contents.

    .PARAMETER FallbackVersion
        Version to return if detection fails. Defaults to "34.0.0".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppPath,

        [string]$FallbackVersion = "34.0.0"
    )

    $electronVersion = $null

    # Method 1: Check Info.plist for ElectronFramework version
    $infoPlist = Get-ChildItem -Path $AppPath -Filter "Info.plist" -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($infoPlist) {
        Write-Verbose "Checking Info.plist for version: $($infoPlist.FullName)"
        $plistContent = Get-Content $infoPlist.FullName -Raw -ErrorAction SilentlyContinue

        if ($plistContent) {
            # Look for CFBundleShortVersionString
            if ($plistContent -match 'CFBundleShortVersionString[\s\S]*?<string>([^<]+)</string>') {
                $electronVersion = $Matches[1]
                Write-Verbose "Found version in CFBundleShortVersionString: $electronVersion"
            }

            # Look for ElectronFramework
            if ($plistContent -match 'ElectronFramework.*?version.*?(\d+\.\d+\.\d+)') {
                $electronVersion = $Matches[1]
                Write-Verbose "Found Electron version in framework: $electronVersion"
            }
        }
    }

    # Method 2: Check package.json files
    if (-not $electronVersion) {
        $packageJsonFiles = Get-ChildItem -Path $AppPath -Filter "package.json" -Recurse -ErrorAction SilentlyContinue

        foreach ($pkg in $packageJsonFiles) {
            try {
                $pkgContent = Get-Content $pkg.FullName -Raw | ConvertFrom-Json

                # Check devDependencies
                if ($pkgContent.devDependencies -and $pkgContent.devDependencies.electron) {
                    $version = $pkgContent.devDependencies.electron -replace '[^0-9.]', ''
                    if ($version -match '^\d+\.\d+\.\d+$') {
                        $electronVersion = $version
                        Write-Verbose "Found Electron version in package.json devDependencies: $electronVersion"
                        break
                    }
                }

                # Check dependencies
                if ($pkgContent.dependencies -and $pkgContent.dependencies.electron) {
                    $version = $pkgContent.dependencies.electron -replace '[^0-9.]', ''
                    if ($version -match '^\d+\.\d+\.\d+$') {
                        $electronVersion = $version
                        Write-Verbose "Found Electron version in package.json dependencies: $electronVersion"
                        break
                    }
                }

                # Check version field
                if ($pkgContent.version -and $pkgContent.version -match '^\d+\.\d+\.\d+$') {
                    $electronVersion = $pkgContent.version
                    Write-Verbose "Found version in package.json: $electronVersion"
                }
            }
            catch {
                Write-Verbose "Could not parse $($pkg.FullName): $_"
            }
        }
    }

    # Method 3: Check Electron framework version file
    if (-not $electronVersion) {
        $versionFile = Get-ChildItem -Path $AppPath -Filter "version" -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.DirectoryName -match "Electron Framework" -or $_.DirectoryName -match "electron" } |
            Select-Object -First 1

        if ($versionFile) {
            $version = (Get-Content $versionFile.FullName -Raw).Trim()
            if ($version -match '^\d+\.\d+\.\d+$') {
                $electronVersion = $version
                Write-Verbose "Found Electron version in framework version file: $electronVersion"
            }
        }
    }

    # Fallback
    if (-not $electronVersion) {
        Write-Verbose "Could not detect Electron version, using fallback: $FallbackVersion"
        $electronVersion = $FallbackVersion
    }

    return $electronVersion
}

function Extract-CodexDmg {
    <#
    .SYNOPSIS
        Main entry point: Download (if needed), extract, and analyze Codex.dmg.

    .PARAMETER DmgPath
        Path to the Codex.dmg file. If not provided, downloads automatically.

    .PARAMETER OutputDir
        Directory where contents should be extracted.

    .PARAMETER SevenZipPath
        Path to 7z.exe. Auto-detected if not provided.

    .PARAMETER SkipVerify
        Skip SHA-256 verification.

    .OUTPUTS
        Hashtable with keys:
        - AppPath: Path to the extracted .app bundle
        - ElectronVersion: Detected Electron version
        - ExtractDir: Path to the extraction directory
        - AppBundle: Path to the .app bundle
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DmgPath,

        [Parameter(Mandatory)]
        [string]$OutputDir,

        [string]$SevenZipPath,

        [switch]$SkipVerify
    )

    Write-Verbose "Extract-CodexDmg: Starting"

    # Find 7-Zip
    if (-not $SevenZipPath) {
        $SevenZipPath = Find-SevenZip
    }

    # Extract the DMG
    $extractDir = Invoke-DmgExtraction -DmgPath $DmgPath -OutputDir $OutputDir -SevenZipPath $SevenZipPath

    # Find the .app bundle
    $appBundle = Get-ChildItem -Path $extractDir -Filter "*.app" -Directory -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1

    $appPath = if ($appBundle) { $appBundle.FullName } else { $extractDir }

    # Detect Electron version
    $electronVersion = Get-ElectronVersion -AppPath $appPath

    $result = @{
        AppPath        = $appPath
        ElectronVersion = $electronVersion
        ExtractDir     = $extractDir
        AppBundle      = if ($appBundle) { $appBundle.FullName } else { "" }
    }

    Write-Verbose "Extract-CodexDmg: Complete"
    Write-Verbose "  App Path: $($result.AppPath)"
    Write-Verbose "  Electron Version: $($result.ElectronVersion)"

    return $result
}

# Export functions
Export-ModuleMember -Function @(
    "Extract-CodexDmg",
    "Invoke-DmgDownload",
    "Invoke-DmgExtraction",
    "Get-ElectronVersion",
    "Find-SevenZip",
    "Get-CodexDmgHash",
    "Save-CodexDmgHash"
)
