#!/usr/bin/env node
/**
 * patch-windows.js - ASAR Patch System for Windows Compatibility
 *
 * This script patches the extracted app.asar from the macOS Codex Desktop app
 * to make it compatible with Windows Electron. It handles:
 *
 *   1. Window management - Remove macOS-specific APIs (titlebar style, traffic lights)
 *   2. File path handling - Normalize backslash paths, convert macOS paths
 *   3. Single instance lock - Ensure only one instance runs on Windows
 *   4. System tray support - Windows-appropriate tray behavior
 *   5. Auto-updater bridge - Stub macOS auto-updater, add Windows equivalent
 *   6. Desktop name rewrite - .desktop → .lnk adjustments
 *   7. Quit guard - Handle Windows close/quit semantics
 *
 * Usage:
 *   node patch-windows.js --input <path-to-app.asar> --output <output-path> [--build-dir <dir>]
 */

const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

// ─── CLI Argument Parsing ────────────────────────────────────────────────────

function parseArgs() {
  const args = process.argv.slice(2);
  const parsed = {
    input: "",
    output: "",
    buildDir: "",
    dryRun: false,
    verbose: false,
  };

  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--input":
        parsed.input = args[++i];
        break;
      case "--output":
        parsed.output = args[++i];
        break;
      case "--build-dir":
        parsed.buildDir = args[++i];
        break;
      case "--dry-run":
        parsed.dryRun = true;
        break;
      case "--verbose":
      case "-v":
        parsed.verbose = true;
        break;
      case "--help":
      case "-h":
        printHelp();
        process.exit(0);
        break;
    }
  }

  if (!parsed.input) {
    console.error("Error: --input is required");
    process.exit(1);
  }
  if (!parsed.output) {
    parsed.output = parsed.input;
  }
  if (!parsed.buildDir) {
    parsed.buildDir = path.dirname(parsed.output);
  }

  return parsed;
}

function printHelp() {
  console.log(`
patch-windows.js - Patch macOS Codex app.asar for Windows

Usage:
  node patch-windows.js --input <app.asar> --output <patched.asar> [options]

Options:
  --input <path>       Path to the input app.asar file (required)
  --output <path>      Path for the patched output (default: same as input)
  --build-dir <dir>    Build directory for intermediate files
  --dry-run            Show what would be patched without making changes
  --verbose, -v        Enable verbose output
  --help, -h           Show this help message
`);
}

// ─── ASAR Utilities ──────────────────────────────────────────────────────────

function extractAsar(asarPath, outputDir) {
  log(`Extracting asar: ${asarPath} -> ${outputDir}`);

  // Try using @electron/asar CLI
  try {
    const asarCmd = findAsarCommand();
    if (asarCmd) {
      execSync(`"${asarCmd}" extract "${asarPath}" "${outputDir}"`, {
        stdio: "pipe",
      });
      return;
    }
  } catch (e) {
    log("asar CLI extraction failed, trying npm package...");
  }

  // Fallback: use asar Node API
  try {
    let asarPkg;
    try {
      asarPkg = require("@electron/asar");
    } catch {
      // Install it
      execSync("npm install @electron/asar --no-save", {
        cwd: outputDir,
        stdio: "pipe",
      });
      asarPkg = require("@electron/asar");
    }
    asarPkg.extractAll(asarPath, outputDir);
  } catch (e) {
    throw new Error(`Failed to extract asar: ${e.message}`);
  }
}

function packAsar(sourceDir, outputPath) {
  log(`Packing asar: ${sourceDir} -> ${outputPath}`);

  try {
    const asarCmd = findAsarCommand();
    if (asarCmd) {
      execSync(`"${asarCmd}" pack "${sourceDir}" "${outputPath}"`, {
        stdio: "pipe",
      });
      return;
    }
  } catch (e) {
    log("asar CLI packing failed, trying npm package...");
  }

  try {
    let asarPkg;
    try {
      asarPkg = require("@electron/asar");
    } catch {
      asarPkg = require(path.join(sourceDir, "node_modules", "@electron", "asar"));
    }
    asarPkg.createPackage(sourceDir, outputPath);
  } catch (e) {
    throw new Error(`Failed to pack asar: ${e.message}`);
  }
}

function findAsarCommand() {
  const candidates = [
    path.join("node_modules", ".bin", "asar"),
    path.join(process.env.APPDATA || "", "npm", "asar.cmd"),
    "asar",
  ];
  for (const cmd of candidates) {
    try {
      execSync(`"${cmd}" --version`, { stdio: "pipe" });
      return cmd;
    } catch {
      continue;
    }
  }
  return null;
}

// ─── Patch Definitions ───────────────────────────────────────────────────────

const PATCHES = [
  {
    name: "window-management",
    description: "Remove macOS-specific window APIs (titlebar style, traffic lights)",
    patterns: [
      // Replace macOS titlebar style options
      {
        match: /titleBarStyle:\s*['"]hiddenInset['"]/g,
        replace: "titleBarStyle: 'default'",
      },
      {
        match: /titleBarStyle:\s*['"]hidden['"]/g,
        replace: "titleBarStyle: 'default'",
      },
      // Remove traffic light positioning
      {
        match: /trafficLightPosition.*?[,\n]/g,
        replace: "// [Windows] Removed trafficLightPosition\n",
      },
      // Remove transparent titlebar for macOS
      {
        match: /transparent:\s*true\s*,?\s*\/\/\s*macOS/g,
        replace: "transparent: false, // [Windows] Disabled transparent\n",
      },
      // Replace vibrancy (macOS-only)
      {
        match: /vibrancy:\s*['"](sidebar|titlebar|window|menu|selection|popover|fullscreen-ui)[^'"]*['"]/g,
        replace: "// [Windows] vibrancy not supported",
      },
      // Remove setWindowButtonVisibility
      {
        match: /\.setWindowButtonVisibility\([^)]*\)/g,
        replace: "/* [Windows] setWindowButtonVisibility removed */",
      },
    ],
  },
  {
    name: "file-path-handling",
    description: "Normalize file paths for Windows (backslash support)",
    patterns: [
      // Convert POSIX paths to platform-aware
      {
        match: /path\.join\(['"]\/Users\/[^'"]+['"]/g,
        replace: "path.join(process.env.USERPROFILE || process.env.HOME,",
      },
      // Replace macOS home directory references
      {
        match: /process\.env\.HOME(?!\s*\|\|)/g,
        replace: "process.env.USERPROFILE || process.env.HOME",
      },
      // Replace macOS-specific config paths
      {
        match: /path\.join\(process\.env\.HOME,\s*['"]\.config['"]/g,
        replace: "path.join(process.env.APPDATA",
      },
      // Replace /tmp with os.tmpdir()
      {
        match: /['"]\/tmp['"]/g,
        replace: "require('os').tmpdir()",
      },
      // Fix path separator assumptions
      {
        match: /\.split\(['"]\/['"]\)/g,
        replace: ".split(path.sep)",
      },
      {
        match: /\.join\(['"]\/['"]\)/g,
        replace: ".join(path.sep)",
      },
    ],
  },
  {
    name: "single-instance-lock",
    description: "Add single instance enforcement for Windows",
    inject: `
// [Windows Patch] Single Instance Lock
const gotTheLock = app.requestSingleInstanceLock();
if (!gotTheLock) {
  app.quit();
} else {
  app.on('second-instance', (event, commandLine, workingDirectory) => {
    // Someone tried to run a second instance, focus our window instead
    const win = BrowserWindow.getAllWindows()[0];
    if (win) {
      if (win.isMinimized()) win.restore();
      win.focus();
    }
  });
}
`,
    injectLocation: "after-app-ready",
  },
  {
    name: "system-tray",
    description: "Windows-appropriate system tray behavior",
    patterns: [
      // Ensure tray icon shows on Windows
      {
        match: /new Tray\(([^)]+)\)/g,
        replace: `new Tray($1) /* [Windows] Using native tray */`,
      },
      // Add Windows-specific tray click behavior
      {
        match: /tray\.on\(['"]click['"]/g,
        replace: `tray.on('click'`,
      },
      // SetToolTip for Windows tray
      {
        match: /\/\/\s*tray\s+tooltip/g,
        replace: `tray.setToolTip('Codex Desktop'); // [Windows] Added tray tooltip`,
      },
    ],
    inject: `
// [Windows Patch] System Tray Support
if (process.platform === 'win32') {
  app.setAppUserModelId('CodexDesktop');
}
`,
    injectLocation: "after-app-ready",
  },
  {
    name: "auto-updater-bridge",
    description: "Stub macOS auto-updater, add Windows equivalent",
    patterns: [
      // Replace macOS autoUpdater with Windows-compatible stub
      {
        match: /autoUpdater\.checkForUpdates\(\)/g,
        replace: `// [Windows Patch] autoUpdater.checkForUpdates() - delegated to codex-update-manager`,
      },
      {
        match: /autoUpdater\.downloadUpdate\(\)/g,
        replace: `// [Windows Patch] autoUpdater.downloadUpdate() - delegated to codex-update-manager`,
      },
      {
        match: /autoUpdater\.quitAndInstall\(\)/g,
        replace: `// [Windows Patch] autoUpdater.quitAndInstall() - delegated to codex-update-manager`,
      },
      // Replace darwin-only updater checks
      {
        match: /process\.platform\s*===\s*['"]darwin['"]\s*&&\s*autoUpdater/g,
        replace: `false && autoUpdater // [Windows Patch] Disabled macOS autoUpdater`,
      },
    ],
    inject: `
// [Windows Patch] Auto-Updater Bridge
// On Windows, updates are managed by codex-update-manager service
// which monitors for new DMG releases and triggers rebuild
const windowsUpdater = {
  checkForUpdates: () => {
    // Notify codex-update-manager to check for updates
    const { net } = require('electron');
    const request = net.request('http://127.0.0.1:5180/api/check-update');
    request.on('response', (response) => { /* handle response */ });
    request.end();
  },
  downloadUpdate: () => Promise.resolve([]),
  quitAndInstall: () => app.quit(),
};
`,
    injectLocation: "after-app-ready",
  },
  {
    name: "desktop-name-rewrite",
    description: "Adjust .desktop references for Windows (.lnk)",
    patterns: [
      // Replace .desktop file references
      {
        match: /\.desktop/g,
        replace: ".lnk",
      },
      // Replace XDG desktop paths
      {
        match: /\/usr\/share\/applications/g,
        replace: "Start Menu",
      },
      {
        match: /~\/\.local\/share\/applications/g,
        replace: "%APPDATA%\\Microsoft\\Windows\\Start Menu\\Programs",
      },
      // Replace macOS .app bundle references
      {
        match: /\.app\/Contents\//g,
        replace: "\\",
      },
    ],
  },
  {
    name: "quit-guard",
    description: "Handle Windows close/quit semantics properly",
    patterns: [
      // Ensure all windows close triggers app quit on Windows
      {
        match: /app\.on\(['"]window-all-closed['"]\s*,\s*\(\)\s*=>\s*\{[^}]*if\s*\(\s*process\.platform\s*!==\s*['"]darwin['"]\s*\)\s*app\.quit\(\)/g,
        replace: `app.on('window-all-closed', () => {
  // [Windows Patch] Always quit on Windows when all windows are closed
  app.quit();`,
      },
    ],
    inject: `
// [Windows Patch] Quit Guard
// On Windows, closing all windows should quit the app
app.on('window-all-closed', () => {
  app.quit();
});

// Prevent premature quit during updates
app.on('before-quit', (event) => {
  // Allow quit to proceed normally on Windows
});
`,
    injectLocation: "after-app-ready",
  },
];

// ─── Patch Application ───────────────────────────────────────────────────────

const patchReport = {
  timestamp: new Date().toISOString(),
  patchesApplied: 0,
  patches: [],
  filesModified: 0,
  filesScanned: 0,
  errors: [],
};

function log(message) {
  console.log(`[patch-windows] ${message}`);
}

function logVerbose(message) {
  // Could be enabled with --verbose flag
}

function applyPatternPatches(filePath, patch) {
  let content = fs.readFileSync(filePath, "utf-8");
  let patchCount = 0;

  for (const pattern of patch.patterns) {
    const matches = content.match(pattern.match);
    if (matches && matches.length > 0) {
      content = content.replace(pattern.match, pattern.replace);
      patchCount += matches.length;
    }
  }

  if (patchCount > 0) {
    fs.writeFileSync(filePath, content, "utf-8");
    patchReport.patches.push({
      name: patch.name,
      file: filePath,
      count: patchCount,
    });
    patchReport.patchesApplied += patchCount;
    patchReport.filesModified++;
    log(`  Applied ${patchCount} ${patch.name} patches in ${path.basename(filePath)}`);
  }

  return patchCount;
}

function applyInjectPatches(filePath, patch) {
  if (!patch.inject) return 0;

  let content = fs.readFileSync(filePath, "utf-8");
  let insertPosition = -1;

  switch (patch.injectLocation) {
    case "after-app-ready": {
      // Find app.on('ready' or app.whenReady
      const readyMatch = content.search(/app\.(on\(['"]ready['"]|whenReady)/);
      if (readyMatch !== -1) {
        // Find the end of the callback/function
        const afterReady = content.indexOf("\n", readyMatch);
        insertPosition = afterReady !== -1 ? afterReady + 1 : content.length;
      }
      break;
    }
    case "top-of-file": {
      insertPosition = 0;
      break;
    }
    default: {
      // Append to end of file
      insertPosition = content.length;
    }
  }

  if (insertPosition >= 0) {
    const header = `\n// ─── Begin Patch: ${patch.name} ───\n`;
    const footer = `\n// ─── End Patch: ${patch.name} ───\n`;
    content =
      content.slice(0, insertPosition) +
      header +
      patch.inject +
      footer +
      content.slice(insertPosition);

    fs.writeFileSync(filePath, content, "utf-8");
    patchReport.patches.push({
      name: patch.name,
      file: filePath,
      type: "inject",
    });
    patchReport.patchesApplied++;
    patchReport.filesModified++;
    log(`  Injected ${patch.name} patch into ${path.basename(filePath)}`);
    return 1;
  }

  return 0;
}

function processFile(filePath, patches) {
  const ext = path.extname(filePath);
  if (![".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs"].includes(ext)) {
    return;
  }

  patchReport.filesScanned++;

  for (const patch of patches) {
    try {
      if (patch.patterns && patch.patterns.length > 0) {
        applyPatternPatches(filePath, patch);
      }
      if (patch.inject) {
        applyInjectPatches(filePath, patch);
      }
    } catch (err) {
      const errorInfo = {
        patch: patch.name,
        file: filePath,
        error: err.message,
      };
      patchReport.errors.push(errorInfo);
      log(`  Error applying ${patch.name} to ${path.basename(filePath)}: ${err.message}`);
    }
  }
}

function walkDir(dir, callback) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      // Skip node_modules and .git
      if (entry.name !== "node_modules" && entry.name !== ".git") {
        walkDir(fullPath, callback);
      }
    } else if (entry.isFile()) {
      callback(fullPath);
    }
  }
}

// ─── Main ────────────────────────────────────────────────────────────────────

function main() {
  const args = parseArgs();

  log("════════════════════════════════════════════════════════");
  log("  Codex Desktop - ASAR Patch System for Windows");
  log("════════════════════════════════════════════════════════");
  log("");

  if (!fs.existsSync(args.input)) {
    console.error(`Error: Input asar not found: ${args.input}`);
    process.exit(1);
  }

  const extractDir = path.join(args.buildDir, "asar-extracted");

  // Clean previous extraction
  if (fs.existsSync(extractDir)) {
    fs.rmSync(extractDir, { recursive: true, force: true });
  }
  fs.mkdirSync(extractDir, { recursive: true });

  // Step 1: Extract asar
  log("Step 1: Extracting app.asar...");
  extractAsar(args.input, extractDir);
  log(`  Extracted to: ${extractDir}`);

  // Step 2: Apply patches
  log("");
  log("Step 2: Applying Windows compatibility patches...");
  walkDir(extractDir, (filePath) => processFile(filePath, PATCHES));

  // Step 3: Repack asar
  log("");
  log("Step 3: Repacking app.asar...");
  if (args.dryRun) {
    log("  [DRY RUN] Skipping repack");
  } else {
    packAsar(extractDir, args.output);
    log(`  Packed to: ${args.output}`);
  }

  // Step 4: Generate patch report
  log("");
  log("Step 4: Generating patch report...");
  const reportPath = path.join(args.buildDir, "patch-report.json");
  patchReport.inputAsar = args.input;
  patchReport.outputAsar = args.output;

  fs.writeFileSync(reportPath, JSON.stringify(patchReport, null, 2), "utf-8");
  log(`  Report: ${reportPath}`);

  // Summary
  log("");
  log("════════════════════════════════════════════════════════");
  log("  Patch Summary");
  log("════════════════════════════════════════════════════════");
  log(`  Files scanned:   ${patchReport.filesScanned}`);
  log(`  Files modified:  ${patchReport.filesModified}`);
  log(`  Patches applied: ${patchReport.patchesApplied}`);
  log(`  Errors:          ${patchReport.errors.length}`);

  if (patchReport.errors.length > 0) {
    log("");
    log("  Errors:");
    for (const err of patchReport.errors) {
      log(`    - ${err.patch}: ${err.error} (${path.basename(err.file)})`);
    }
  }

  if (patchReport.errors.length > 0) {
    process.exit(1);
  }
}

main();
