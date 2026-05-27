<#
.SYNOPSIS
    Native Module Rebuilder for Codex Desktop Windows Toolkit

.DESCRIPTION
    Rebuilds native Node.js modules (better-sqlite3, node-pty) for the
    Windows Electron target. Uses @electron/rebuild and handles V8 API
    compatibility patches.

.EXAMPLE
    . .\Native-Modules.ps1
    $result = Repair-NativeModules -ElectronVersion "34.0.0" -AppPath "C:\temp\app" -BuildDir "C:\temp\build"
#>

[CmdletBinding()]
param()

# ─── Constants ────────────────────────────────────────────────────────────────

$NATIVE_MODULES = @("better-sqlite3", "node-pty")
$ELECTRON_REBUILD_PACKAGE = "@electron/rebuild"

# ─── V8 API Compatibility Patches ────────────────────────────────────────────

# These patches handle V8 API changes between Electron versions that may
# cause native modules to fail to compile on Windows.

$V8_PATCHES = @{
    "better-sqlite3" = @(
        @{
            Description = "Fix V8::Object::Set deprecated API"
            File        = "src/better_sqlite3.cpp"
            Match       = 'Nan::Set\(([^,]+),\s*Nan::New\("([^"]+)"\)\.ToLocalChecked\(\),\s*([^)]+)\)'
            Replace     = 'Nan::DefineOwnProperty($1, Nan::New("$2").ToLocalChecked(), $3)'
        }
    )
    "node-pty"       = @(
        @{
            Description = "Fix Windows build: add WIN32_LEAN_AND_MEAN"
            File        = "src/win/conpty.cc"
            Match       = '#include <windows.h>'
            Replace     = '#ifndef WIN32_LEAN_AND_MEAN`n#define WIN32_LEAN_AND_MEAN`n#endif`n#include <windows.h>'
        }
    )
}

# ─── Functions ────────────────────────────────────────────────────────────────

function Find-NativeModules {
    <#
    .SYNOPSIS
        Find native Node.js modules in the extracted app.

    .PARAMETER AppPath
        Path to the extracted application.

    .OUTPUTS
        Array of hashtables with module info (Name, Path, HasBinding)
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$AppPath)

    $modules = @()

    $nodeModulesDir = Get-ChildItem -Path $AppPath -Filter "node_modules" -Directory -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if (-not $nodeModulesDir) {
        Write-Verbose "No node_modules directory found in $AppPath"
        return $modules
    }

    foreach ($modName in $NATIVE_MODULES) {
        $modPath = Join-Path $nodeModulesDir.FullName $modName
        if (Test-Path $modPath) {
            $bindingGyp = Join-Path $modPath "binding.gyp"
            $hasBinding = Test-Path $bindingGyp

            $modules += @{
                Name       = $modName
                Path       = $modPath
                HasBinding = $hasBinding
            }

            Write-Verbose "Found native module: $modName at $modPath (binding: $hasBinding)"
        }
        else {
            Write-Verbose "Native module not found: $modName"
        }
    }

    return $modules
}

function Invoke-V8CompatibilityPatch {
    <#
    .SYNOPSIS
        Apply V8 API compatibility patches to native module source files.

    .PARAMETER ModuleName
        Name of the native module.

    .PARAMETER ModulePath
        Path to the module directory.

    .PARAMETER ElectronVersion
        Target Electron version for compatibility assessment.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ModuleName,
        [Parameter(Mandatory)][string]$ModulePath,
        [Parameter(Mandatory)][string]$ElectronVersion
    )

    $patches = $V8_PATCHES[$ModuleName]
    if (-not $patches) {
        Write-Verbose "No V8 patches defined for $ModuleName"
        return
    }

    Write-Verbose "Applying V8 compatibility patches for $ModuleName (Electron $ElectronVersion)"

    foreach ($patch in $patches) {
        $filePath = Join-Path $ModulePath $patch.File
        if (-not (Test-Path $filePath)) {
            Write-Verbose "  Patch target not found: $($patch.File)"
            continue
        }

        $content = Get-Content $filePath -Raw -Encoding UTF8
        if ($content -match $patch.Match) {
            $newContent = $content -replace $patch.Match, $patch.Replace
            Set-Content -Path $filePath -Value $newContent -NoNewline -Encoding UTF8
            Write-Verbose "  Applied: $($patch.Description)"
        }
        else {
            Write-Verbose "  Pattern not matched (may already be patched): $($patch.Description)"
        }
    }
}

function Repair-NativeModules {
    <#
    .SYNOPSIS
        Main entry point: Rebuild native Node modules for Windows Electron.

    .PARAMETER ElectronVersion
        Target Electron version.

    .PARAMETER AppPath
        Path to the extracted app containing node_modules.

    .PARAMETER BuildDir
        Build directory for temporary files.

    .PARAMETER NpmPath
        Path to npm executable. Defaults to system npm.

    .OUTPUTS
        Hashtable with keys:
        - RebuiltModules: Array of module names that were rebuilt
        - FailedModules:   Array of module names that failed
        - SkippedModules:  Array of module names that were skipped
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ElectronVersion,

        [Parameter(Mandatory)]
        [string]$AppPath,

        [Parameter(Mandatory)]
        [string]$BuildDir,

        [string]$NpmPath = "npm"
    )

    Write-Verbose "Repair-NativeModules: Starting for Electron v$ElectronVersion"

    $rebuiltModules = @()
    $failedModules = @()
    $skippedModules = @()

    # Find native modules
    $modules = Find-NativeModules -AppPath $AppPath

    if ($modules.Count -eq 0) {
        Write-Verbose "No native modules found to rebuild"
        return @{
            RebuiltModules = $rebuiltModules
            FailedModules  = $failedModules
            SkippedModules = $skippedModules
        }
    }

    # Install @electron/rebuild in build directory
    Write-Verbose "Installing $ELECTRON_REBUILD_PACKAGE..."
    Push-Location $BuildDir
    try {
        & $NpmPath install $ELECTRON_REBUILD_PACKAGE --no-save --no-package-lock 2>&1 |
            ForEach-Object { Write-Verbose $_ }

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to install $ELECTRON_REBUILD_PACKAGE"
        }
    }
    finally {
        Pop-Location
    }

    $rebuildCmd = Join-Path $BuildDir "node_modules\.bin\electron-rebuild"
    if (-not (Test-Path $rebuildCmd)) {
        $rebuildCmd = Join-Path $BuildDir "node_modules\.bin\electron-rebuild.cmd"
    }

    # Rebuild each module
    foreach ($mod in $modules) {
        Write-Verbose "Rebuilding $($mod.Name) for Electron $ElectronVersion..."

        # Apply V8 compatibility patches first
        try {
            Invoke-V8CompatibilityPatch -ModuleName $mod.Name `
                -ModulePath $mod.Path `
                -ElectronVersion $ElectronVersion
        }
        catch {
            Write-Verbose "V8 patch application warning: $_"
        }

        # Run electron-rebuild
        try {
            $rebuildArgs = @(
                "-v", $ElectronVersion,
                "-m", $mod.Path,
                "--force"
            )

            $env:ELECTRON_RUN_AS_NODE = ""

            $result = Start-Process -FilePath $rebuildCmd `
                -ArgumentList $rebuildArgs `
                -NoNewWindow `
                -Wait `
                -PassThru `
                -RedirectStandardOutput (Join-Path $BuildDir "rebuild-$($mod.Name)-stdout.log") `
                -RedirectStandardError (Join-Path $BuildDir "rebuild-$($mod.Name)-stderr.log")

            if ($result.ExitCode -eq 0) {
                $rebuiltModules += $mod.Name
                Write-Verbose "  $($mod.Name) rebuilt successfully"
            }
            else {
                $failedModules += $mod.Name
                Write-Verbose "  $($mod.Name) rebuild failed (exit code: $($result.ExitCode))"

                # Check error log
                $errorLog = Join-Path $BuildDir "rebuild-$($mod.Name)-stderr.log"
                if (Test-Path $errorLog) {
                    $errors = Get-Content $errorLog -Tail 20
                    Write-Verbose "  Error output:"
                    $errors | ForEach-Object { Write-Verbose "    $_" }
                }
            }
        }
        catch {
            $failedModules += $mod.Name
            Write-Verbose "  $($mod.Name) rebuild failed: $_"
        }
    }

    # Report results
    Write-Verbose "Native module rebuild summary:"
    Write-Verbose "  Rebuilt: $($rebuiltModules -join ', ')"
    Write-Verbose "  Failed:  $($failedModules -join ', ')"
    Write-Verbose "  Skipped: $($skippedModules -join ', ')"

    return @{
        RebuiltModules = $rebuiltModules
        FailedModules  = $failedModules
        SkippedModules = $skippedModules
    }
}

# Export functions
Export-ModuleMember -Function @(
    "Repair-NativeModules",
    "Find-NativeModules",
    "Invoke-V8CompatibilityPatch"
)
