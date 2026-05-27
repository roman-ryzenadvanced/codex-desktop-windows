<#
.SYNOPSIS
    Plugin Cache Manager for Codex Desktop Windows Toolkit

.DESCRIPTION
    Syncs and manages plugin cache directories for Codex Desktop on Windows.
    Handles Browser Use, Chrome, Computer Use, and Read Aloud plugins,
    including native messaging host registration and marketplace metadata.

.EXAMPLE
    . .\Plugin-Manager.ps1
    Sync-PluginCache -BuildDir "C:\temp\build"
#>

[CmdletBinding()]
param()

# ─── Constants ────────────────────────────────────────────────────────────────

$PLUGIN_CACHE_BASE = Join-Path $env:APPDATA ".codex\plugins\cache"
$NATIVE_MESSAGING_DIR = Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\NativeMessagingHosts"

$PLUGIN_DEFINITIONS = @(
    @{
        Name        = "browser-use"
        DisplayName = "Browser Use"
        Description = "Browser automation plugin for Codex"
        Version     = "1.0.0"
    },
    @{
        Name        = "chrome"
        DisplayName = "Chrome Integration"
        Description = "Chrome browser integration with native messaging"
        Version     = "1.0.0"
        HasNativeMessaging = $true
    },
    @{
        Name        = "computer-use"
        DisplayName = "Computer Use"
        Description = "Desktop automation plugin (Windows backend)"
        Version     = "1.0.0"
        Platform    = "win32"
    },
    @{
        Name        = "read-aloud"
        DisplayName = "Read Aloud"
        Description = "Text-to-speech plugin for accessibility"
        Version     = "1.0.0"
    }
)

# ─── Functions ────────────────────────────────────────────────────────────────

function Sync-PluginCache {
    <#
    .SYNOPSIS
        Sync all plugin caches from the build directory to the user's app data.

    .PARAMETER BuildDir
        Build directory containing plugin source files.

    .PARAMETER Force
        Force re-sync even if cache already exists.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BuildDir,

        [switch]$Force
    )

    Write-Verbose "Syncing plugin cache..."

    # Ensure base cache directory exists
    if (-not (Test-Path $PLUGIN_CACHE_BASE)) {
        New-Item -ItemType Directory -Path $PLUGIN_CACHE_BASE -Force | Out-Null
    }

    $syncResults = @()

    foreach ($plugin in $PLUGIN_DEFINITIONS) {
        Write-Verbose "Processing plugin: $($plugin.Name)"

        $pluginSource = Join-Path $BuildDir "plugins\$($plugin.Name)"
        $pluginDest = Join-Path $PLUGIN_CACHE_BASE $plugin.Name

        # Check if source exists
        if (-not (Test-Path $pluginSource)) {
            # Try alternative paths
            $altSource = Join-Path $BuildDir "resources\plugins\$($plugin.Name)"
            if (Test-Path $altSource) {
                $pluginSource = $altSource
            }
            else {
                Write-Verbose "  Source not found for $($plugin.Name), creating stub"
                $syncResults += Sync-PluginStub -Plugin $plugin -DestDir $pluginDest -Force:$Force
                continue
            }
        }

        # Check if destination exists and is up to date
        if ((Test-Path $pluginDest) -and -not $Force) {
            $sourceHash = Get-DirectoryHash $pluginSource
            $destHash = Get-DirectoryHash $pluginDest
            if ($sourceHash -eq $destHash) {
                Write-Verbose "  $($plugin.Name) cache is up to date"
                $syncResults += @{
                    Name    = $plugin.Name
                    Status  = "cached"
                    Path    = $pluginDest
                }
                continue
            }
        }

        # Sync
        try {
            if (Test-Path $pluginDest) {
                Remove-Item $pluginDest -Recurse -Force
            }

            Copy-Item $pluginSource $pluginDest -Recurse -Force
            Write-Verbose "  Synced $($plugin.Name) -> $pluginDest"

            # Handle native messaging registration
            if ($plugin.HasNativeMessaging) {
                Register-NativeMessagingHost -PluginDir $pluginDest -PluginName $plugin.Name
            }

            $syncResults += @{
                Name   = $plugin.Name
                Status = "synced"
                Path   = $pluginDest
            }
        }
        catch {
            Write-Verbose "  Failed to sync $($plugin.Name): $_"
            $syncResults += @{
                Name   = $plugin.Name
                Status = "failed"
                Error  = $_.ToString()
            }
        }
    }

    # Generate marketplace metadata
    New-MarketplaceMetadata -Results $syncResults

    Write-Verbose "Plugin cache sync complete"
    return $syncResults
}

function Sync-PluginStub {
    <#
    .SYNOPSIS
        Create a stub plugin directory when source is not available.

    .PARAMETER Plugin
        Plugin definition hashtable.

    .PARAMETER DestDir
        Destination directory for the stub.

    .PARAMETER Force
        Force overwrite existing stub.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Plugin,

        [Parameter(Mandatory)]
        [string]$DestDir,

        [switch]$Force
    )

    if ((Test-Path $DestDir) -and -not $Force) {
        return @{
            Name   = $Plugin.Name
            Status = "cached"
            Path   = $DestDir
        }
    }

    if (Test-Path $DestDir) {
        Remove-Item $DestDir -Recurse -Force
    }

    New-Item -ItemType Directory -Path $DestDir -Force | Out-Null

    # Create plugin manifest
    $manifest = @{
        name        = $Plugin.Name
        displayName = $Plugin.DisplayName
        description = $Plugin.Description
        version     = $Plugin.Version
        platform    = if ($Plugin.Platform) { $Plugin.Platform } else { "any" }
        enabled     = $true
        stub        = $true
    }
    $manifest | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $DestDir "manifest.json") -Force

    # Create empty index.js
    $indexContent = @"
// $($Plugin.DisplayName) - Stub Plugin
// This is a placeholder. The actual plugin will be populated during first run.

module.exports = {
  name: '$($Plugin.Name)',
  version: '$($Plugin.Version)',
  activate: () => console.log('$($Plugin.DisplayName) plugin activated (stub)'),
  deactivate: () => console.log('$($Plugin.DisplayName) plugin deactivated'),
};
"@
    Set-Content (Join-Path $DestDir "index.js") -Value $indexContent -Force

    Write-Verbose "  Created stub for $($Plugin.Name)"

    return @{
        Name   = $Plugin.Name
        Status = "stub"
        Path   = $DestDir
    }
}

function Register-NativeMessagingHost {
    <#
    .SYNOPSIS
        Register a Chrome native messaging host for a plugin.

    .PARAMETER PluginDir
        Directory containing the plugin with native messaging host manifest.

    .PARAMETER PluginName
        Name of the plugin (used for manifest filename).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PluginDir,
        [Parameter(Mandatory)][string]$PluginName
    )

    Write-Verbose "Registering native messaging host for $PluginName"

    # Ensure native messaging directory exists
    if (-not (Test-Path $NATIVE_MESSAGING_DIR)) {
        New-Item -ItemType Directory -Path $NATIVE_MESSAGING_DIR -Force | Out-Null
    }

    # Look for manifest file
    $manifestFile = Get-ChildItem -Path $PluginDir -Filter "com.codex.*.json" -File -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if (-not $manifestFile) {
        $manifestFile = Get-ChildItem -Path $PluginDir -Filter "*nmh*.json" -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
    }

    if ($manifestFile) {
        # Update paths in manifest for Windows
        $manifest = Get-Content $manifestFile.FullName -Raw | ConvertFrom-Json

        # Update the path to the native messaging host binary
        $hostBinary = Get-ChildItem -Path $PluginDir -Filter "*_nmh.exe" -File -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if (-not $hostBinary) {
            $hostBinary = Get-ChildItem -Path $PluginDir -Filter "*_nmh.cmd" -File -ErrorAction SilentlyContinue |
                Select-Object -First 1
        }

        if ($hostBinary) {
            $manifest.path = $hostBinary.FullName -replace '/', '\'
        }

        # Write updated manifest
        $destManifest = Join-Path $NATIVE_MESSAGING_DIR $manifestFile.Name
        $manifest | ConvertTo-Json -Depth 5 | Set-Content $destManifest -Force
        Write-Verbose "  Native messaging host registered: $destManifest"
    }
    else {
        # Create default manifest
        $defaultManifest = @{
            name          = "com.codex.$PluginName"
            description   = "Codex Desktop - $PluginName Native Messaging Host"
            path          = (Join-Path $PluginDir "$PluginName-nmh.cmd")
            type          = "stdio"
            allowed_origins = @("chrome-extension://*/")
        }

        $manifestName = "com.codex.$PluginName.json"
        $destManifest = Join-Path $NATIVE_MESSAGING_DIR $manifestName
        $defaultManifest | ConvertTo-Json -Depth 3 | Set-Content $destManifest -Force
        Write-Verbose "  Created default native messaging manifest: $destManifest"
    }
}

function New-MarketplaceMetadata {
    <#
    .SYNOPSIS
        Generate marketplace metadata for all synced plugins.

    .PARAMETER Results
        Array of sync result hashtables.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Results)

    $metadata = @{
        generatedAt = (Get-Date -Format "o")
        platform    = "win32"
        arch        = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "arm64" }
        plugins     = @()
    }

    foreach ($result in $Results) {
        $pluginDef = $PLUGIN_DEFINITIONS | Where-Object { $_.Name -eq $result.Name } | Select-Object -First 1

        $pluginMeta = @{
            name        = $result.Name
            displayName = if ($pluginDef) { $pluginDef.DisplayName } else { $result.Name }
            version     = if ($pluginDef) { $pluginDef.Version } else { "0.0.0" }
            status      = $result.Status
            path        = $result.Path
            platform    = if ($pluginDef -and $pluginDef.Platform) { $pluginDef.Platform } else { "any"
            }
        }

        $metadata.plugins += $pluginMeta
    }

    $metadataPath = Join-Path $PLUGIN_CACHE_BASE "marketplace.json"
    $metadata | ConvertTo-Json -Depth 5 | Set-Content $metadataPath -Force
    Write-Verbose "Marketplace metadata written to $metadataPath"
}

function Get-DirectoryHash {
    <#
    .SYNOPSIS
        Compute a simple hash of a directory's contents for comparison.
        Uses file names and sizes as a quick fingerprint.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path $Path)) { return "" }

    $files = Get-ChildItem -Path $Path -File -Recurse -ErrorAction SilentlyContinue
    $hashInput = ($files | Sort-Object FullName | ForEach-Object {
        "$($_.Name):$($_.Length):$($_.LastWriteTime.Ticks)"
    }) -join "|"

    # Simple hash using .NET
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($hashInput)
    $hash = $sha256.ComputeHash($bytes)
    return [BitConverter]::ToString($hash) -replace '-', '' | Select-Object -First 16
}

function Get-PluginStatus {
    <#
    .SYNOPSIS
        Get the current status of all installed plugins.
    #>
    [CmdletBinding()]
    param()

    $status = @()

    foreach ($plugin in $PLUGIN_DEFINITIONS) {
        $pluginDir = Join-Path $PLUGIN_CACHE_BASE $plugin.Name
        $manifestPath = Join-Path $pluginDir "manifest.json"

        $pluginStatus = @{
            Name        = $plugin.Name
            DisplayName = $plugin.DisplayName
            Installed   = Test-Path $pluginDir
            HasManifest = Test-Path $manifestPath
        }

        if (Test-Path $manifestPath) {
            try {
                $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
                $pluginStatus.Version = $manifest.version
                $pluginStatus.Enabled = $manifest.enabled
                $pluginStatus.IsStub = $manifest.stub -eq $true
            }
            catch {
                $pluginStatus.Version = "unknown"
            }
        }

        $status += $pluginStatus
    }

    return $status
}

# Export functions
Export-ModuleMember -Function @(
    "Sync-PluginCache",
    "Sync-PluginStub",
    "Register-NativeMessagingHost",
    "New-MarketplaceMetadata",
    "Get-PluginStatus"
)
