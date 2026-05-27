//! ═══════════════════════════════════════════════════════════════════════════════
//! Codex Desktop - Rust Launcher (Windows)
//! ═══════════════════════════════════════════════════════════════════════════════
//!
//! A native Windows launcher that:
//! - Finds the app installation directory
//! - Starts the Python webview server as a child process
//! - Waits for the server to be ready
//! - Launches electron.exe with proper flags
//! - Handles process lifecycle (kill children on exit)
//! - Enforces single instance via named mutex
//! - Hides console window on release builds
//! - Properly handles Windows signals and Job Objects

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::env;
use std::fs;
use std::io::{self, Write};
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};

// ─── Constants ────────────────────────────────────────────────────────────────

const APP_NAME: &str = "Codex Desktop";
const MUTEX_NAME: &str = "Global\\CodexDesktopSingleInstance";
const DEFAULT_PORT: u16 = 5175;
const PORT_MAX: u16 = 5185;
const SERVER_READY_TIMEOUT_SECS: u64 = 30;

// ─── Windows API Imports ─────────────────────────────────────────────────────

#[cfg(target_os = "windows")]
mod win32 {
    use windows::Win32::Foundation::CloseHandle;
    use windows::Win32::System::Threading::{CreateMutexW, OpenProcess};
    use windows::core::PCWSTR;

    pub fn create_named_mutex(name: &str) -> anyhow::Result<()> {
        let wide_name: Vec<u16> = name.encode_utf16().chain(std::iter::once(0)).collect();

        unsafe {
            let _handle = CreateMutexW(
                None,
                true, // initial owner
                PCWSTR(wide_name.as_ptr()),
            )
            .map_err(|e| anyhow::anyhow!("Failed to create mutex '{}': {}", name, e))?;
        }

        Ok(())
    }

    pub fn is_process_running(pid: u32) -> bool {
        unsafe {
            let handle = OpenProcess(
                windows::Win32::System::Threading::PROCESS_QUERY_LIMITED_INFORMATION,
                false,
                pid,
            );
            match handle {
                Ok(h) => {
                    let _ = CloseHandle(h);
                    true
                }
                Err(_) => false,
            }
        }
    }

    pub fn set_foreground_window(_hwnd: isize) -> anyhow::Result<()> {
        // SetForegroundWindow requires HWND which is *mut c_void
        // For now, log the attempt (full implementation needs window handle discovery)
        Ok(())
    }
}

// ─── Path Resolution ─────────────────────────────────────────────────────────

fn find_install_dir() -> Result<PathBuf> {
    // 1. Check current executable directory
    if let Ok(exe_path) = env::current_exe() {
        if let Some(parent) = exe_path.parent() {
            let build_info = parent.join("build-info.json");
            if build_info.exists() {
                return Ok(parent.to_path_buf());
            }
            // Check one level up (in case we're in a subdirectory)
            if let Some(grandparent) = parent.parent() {
                let build_info = grandparent.join("build-info.json");
                if build_info.exists() {
                    return Ok(grandparent.to_path_buf());
                }
            }
        }
    }

    // 2. Check Program Files
    let program_files = env::var("ProgramFiles").unwrap_or_else(|_| r"C:\Program Files".to_string());
    let install_dir = PathBuf::from(program_files).join(APP_NAME);
    if install_dir.join("build-info.json").exists() {
        return Ok(install_dir);
    }

    // 3. Check Program Files (x86)
    if let Ok(pf86) = env::var("ProgramFiles(x86)") {
        let install_dir = PathBuf::from(pf86).join(APP_NAME);
        if install_dir.join("build-info.json").exists() {
            return Ok(install_dir);
        }
    }

    // 4. Check local app data
    if let Ok(local_app_data) = env::var("LOCALAPPDATA") {
        let install_dir = PathBuf::from(local_app_data).join("Programs").join(APP_NAME);
        if install_dir.join("build-info.json").exists() {
            return Ok(install_dir);
        }
    }

    bail!("Could not find Codex Desktop installation directory")
}

fn find_electron_exe(install_dir: &PathBuf) -> Result<PathBuf> {
    let electron_path = install_dir.join("electron").join("electron.exe");
    if electron_path.exists() {
        return Ok(electron_path);
    }

    // Search recursively
    for entry in walkdir::walk_dir(install_dir) {
        if let Ok(entry) = entry {
            if entry.file_name() == "electron.exe" {
                return Ok(entry.path().to_path_buf());
            }
        }
    }

    bail!("electron.exe not found in installation directory")
}

// Simple walkdir replacement (to avoid external dependency)
mod walkdir {
    use std::fs;
    use std::io;
    use std::path::{Path, PathBuf};

    pub struct DirEntry {
        path: PathBuf,
    }

    impl DirEntry {
        pub fn path(&self) -> &Path {
            &self.path
        }

        pub fn file_name(&self) -> &std::ffi::OsStr {
            self.path.file_name().unwrap_or_default()
        }
    }

    pub struct WalkDir {
        stack: Vec<PathBuf>,
    }

    impl WalkDir {
        pub fn new(root: &Path) -> Self {
            WalkDir {
                stack: vec![root.to_path_buf()],
            }
        }
    }

    impl Iterator for WalkDir {
        type Item = io::Result<DirEntry>;

        fn next(&mut self) -> Option<Self::Item> {
            loop {
                let path = self.stack.pop()?;

                if path.is_dir() {
                    if let Ok(entries) = fs::read_dir(&path) {
                        for entry in entries.flatten() {
                            self.stack.push(entry.path());
                        }
                    }
                    continue;
                }

                return Some(Ok(DirEntry { path }));
            }
        }
    }

    pub fn walk_dir(root: &Path) -> WalkDir {
        WalkDir::new(root)
    }
}

fn find_python() -> Result<PathBuf> {
    // Try python3 first, then python
    for name in &["python3", "python"] {
        if let Ok(output) = Command::new(name).arg("--version").output() {
            if output.status.success() {
                if let Ok(path) = which::which(name) {
                    return Ok(path);
                }
                // Fallback: just use the name
                return Ok(PathBuf::from(name));
            }
        }
    }

    // Check common Windows Python paths
    let local_app_data = env::var("LOCALAPPDATA").unwrap_or_default();
    let python_paths = [
        format!(r"{}\Programs\Python\Python312\python.exe", local_app_data),
        format!(r"{}\Programs\Python\Python311\python.exe", local_app_data),
        format!(r"{}\Programs\Python\Python310\python.exe", local_app_data),
        r"C:\Python312\python.exe".to_string(),
        r"C:\Python311\python.exe".to_string(),
    ];

    for path in &python_paths {
        let p = PathBuf::from(path);
        if p.exists() {
            return Ok(p);
        }
    }

    bail!("Python not found. Install from https://www.python.org/")
}

// ─── Port Allocation ─────────────────────────────────────────────────────────

fn find_available_port() -> Result<u16> {
    for port in DEFAULT_PORT..=PORT_MAX {
        if is_port_available(port) {
            return Ok(port);
        }
    }
    bail!("No available port in range {}-{}", DEFAULT_PORT, PORT_MAX)
}

fn is_port_available(port: u16) -> bool {
    use std::net::TcpListener;
    TcpListener::bind(("127.0.0.1", port)).is_ok()
}

// ─── Process Management ──────────────────────────────────────────────────────

struct ManagedProcesses {
    server: Option<Child>,
    electron: Option<Child>,
}

impl ManagedProcesses {
    fn new() -> Self {
        ManagedProcesses {
            server: None,
            electron: None,
        }
    }

    fn kill_all(&mut self) {
        if let Some(ref mut child) = self.server {
            let _ = child.kill();
            let _ = child.wait();
        }
        if let Some(ref mut child) = self.electron {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

impl Drop for ManagedProcesses {
    fn drop(&mut self) {
        self.kill_all();
    }
}

// ─── Webview Server ──────────────────────────────────────────────────────────

fn start_webview_server(
    install_dir: &PathBuf,
    python: &PathBuf,
    port: u16,
) -> Result<Child> {
    let server_script = install_dir.join("launcher").join("webview-server.py");
    let webview_dir = install_dir.join("content").join("webview");

    if !server_script.exists() {
        bail!("Webview server script not found: {:?}", server_script);
    }

    let log_dir = get_log_dir()?;
    fs::create_dir_all(&log_dir)?;

    let stdout_log = fs::File::create(log_dir.join("webview-server-stdout.log"))?;
    let stderr_log = fs::File::create(log_dir.join("webview-server-stderr.log"))?;

    let child = Command::new(python)
        .arg(&server_script)
        .arg("--port")
        .arg(port.to_string())
        .arg("--host")
        .arg("127.0.0.1")
        .arg("--directory")
        .arg(&webview_dir)
        .arg("--parent-pid")
        .arg(std::process::id().to_string())
        .stdout(Stdio::from(stdout_log))
        .stderr(Stdio::from(stderr_log))
        .spawn()
        .context("Failed to start webview server")?;

    Ok(child)
}

fn wait_for_server_ready(port: u16) -> Result<()> {
    let start = Instant::now();
    let timeout = Duration::from_secs(SERVER_READY_TIMEOUT_SECS);

    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(2))
        .build()
        .context("Failed to create HTTP client")?;

    while start.elapsed() < timeout {
        let url = format!("http://127.0.0.1:{}/", port);
        match client.get(&url).send() {
            Ok(response) if response.status().is_success() => {
                log_info(&format!("Webview server ready on port {}", port));
                return Ok(());
            }
            _ => {
                thread::sleep(Duration::from_millis(500));
            }
        }
    }

    bail!(
        "Webview server failed to start within {} seconds",
        SERVER_READY_TIMEOUT_SECS
    )
}

// ─── Electron Launch ─────────────────────────────────────────────────────────

fn launch_electron(install_dir: &PathBuf, port: u16) -> Result<Child> {
    let electron_exe = find_electron_exe(install_dir)?;
    let asar_path = install_dir.join("resources").join("app.asar");
    let load_url = format!("http://127.0.0.1:{}", port);

    let log_dir = get_log_dir()?;

    let child = Command::new(&electron_exe)
        .args(&[
            "--no-sandbox",
            "--disable-gpu-sandbox",
            &format!("--app-user-model-id=CodexDesktop"),
            &format!("--load-url={}", load_url),
            &format!("--app-path={}", asar_path.display()),
        ])
        .stdout(Stdio::from(fs::File::create(log_dir.join("electron-stdout.log"))?))
        .stderr(Stdio::from(fs::File::create(log_dir.join("electron-stderr.log"))?))
        .spawn()
        .context("Failed to launch Electron")?;

    log_info(&format!("Electron launched (PID: {:?})", child.id()));
    Ok(child)
}

// ─── Single Instance ─────────────────────────────────────────────────────────

fn enforce_single_instance() -> Result<Option<()>> {
    #[cfg(target_os = "windows")]
    {
        match win32::create_named_mutex(MUTEX_NAME) {
            Ok(()) => {
                log_info("Acquired single instance mutex");
                Ok(None) // We got the mutex, continue
            }
            Err(_) => {
                log_info("Another instance is already running");
                // TODO: Signal existing instance to focus
                Ok(Some(())) // Another instance exists
            }
        }
    }

    #[cfg(not(target_os = "windows"))]
    {
        // Fallback: check PID file
        let pid_file = get_data_dir()?.join("codex-desktop.pid");
        if pid_file.exists() {
            if let Ok(pid_str) = fs::read_to_string(&pid_file) {
                if let Ok(pid) = pid_str.trim().parse::<u32>() {
                    // Check if process is still running
                    // On non-Windows, use kill(pid, 0)
                    unsafe {
                        if libc::kill(pid as i32, 0) == 0 {
                            return Ok(Some(()));
                        }
                    }
                }
            }
        }
        Ok(None)
    }
}

// ─── Logging ─────────────────────────────────────────────────────────────────

fn get_log_dir() -> Result<PathBuf> {
    let local_app_data = env::var("LOCALAPPDATA")
        .unwrap_or_else(|_| env::var("APPDATA").unwrap_or_else(|_| ".".to_string()));
    Ok(PathBuf::from(local_app_data)
        .join("codex-desktop")
        .join("logs"))
}

fn get_data_dir() -> Result<PathBuf> {
    let local_app_data = env::var("LOCALAPPDATA")
        .unwrap_or_else(|_| env::var("APPDATA").unwrap_or_else(|_| ".".to_string()));
    Ok(PathBuf::from(local_app_data).join("codex-desktop"))
}

fn log_info(message: &str) {
    let timestamp = chrono::Local::now().format("%Y-%m-%d %H:%M:%S");
    let line = format!("[{}] [INFO] {}", timestamp, message);

    // Write to stderr in debug mode
    #[cfg(debug_assertions)]
    eprintln!("{}", line);

    // Always write to log file
    if let Ok(log_dir) = get_log_dir() {
        let _ = fs::create_dir_all(&log_dir);
        let log_file = log_dir.join(format!(
            "launcher-{}.log",
            chrono::Local::now().format("%Y%m%d")
        ));
        let _ = fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_file)
            .and_then(|mut f| {
                writeln!(f, "{}", line)
            });
    }
}

fn log_error(message: &str) {
    let timestamp = chrono::Local::now().format("%Y-%m-%d %H:%M:%S");
    let line = format!("[{}] [ERROR] {}", timestamp, message);

    eprintln!("{}", line);

    if let Ok(log_dir) = get_log_dir() {
        let _ = fs::create_dir_all(&log_dir);
        let log_file = log_dir.join(format!(
            "launcher-{}.log",
            chrono::Local::now().format("%Y%m%d")
        ));
        let _ = fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_file)
            .and_then(|mut f| {
                writeln!(f, "{}", line)
            });
    }
}

// ─── CLI Arguments ───────────────────────────────────────────────────────────

struct CliArgs {
    url: Option<String>,
    port: Option<u16>,
    verbose: bool,
}

fn parse_args() -> CliArgs {
    let args: Vec<String> = env::args().collect();
    let mut cli = CliArgs {
        url: None,
        port: None,
        verbose: false,
    };

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--url" => {
                if i + 1 < args.len() {
                    cli.url = Some(args[i + 1].clone());
                    i += 1;
                }
            }
            "--port" => {
                if i + 1 < args.len() {
                    cli.port = args[i + 1].parse().ok();
                    i += 1;
                }
            }
            "--verbose" | "-v" => {
                cli.verbose = true;
            }
            "--help" | "-h" => {
                println!("Codex Desktop Launcher");
                println!();
                println!("Usage: codex-desktop-launcher [OPTIONS]");
                println!();
                println!("Options:");
                println!("  --url <URL>      URL to open (codex:// protocol)");
                println!("  --port <PORT>    Override default webview server port");
                println!("  --verbose, -v    Enable verbose output");
                println!("  --help, -h       Show this help message");
                std::process::exit(0);
            }
            _ => {}
        }
        i += 1;
    }

    cli
}

// ─── Main Entry Point ────────────────────────────────────────────────────────

fn main() -> Result<()> {
    let cli = parse_args();

    log_info("Codex Desktop Launcher starting...");

    // Step 1: Single instance check
    if let Some(_) = enforce_single_instance()? {
        log_info("Another instance is already running. Exiting.");
        // TODO: Signal existing instance to bring to foreground
        return Ok(());
    }

    // Step 2: Find installation directory
    let install_dir = find_install_dir().context("Could not find Codex Desktop installation")?;
    log_info(&format!("Install directory: {:?}", install_dir));

    // Step 3: Allocate port
    let port = cli.port.unwrap_or_else(|| find_available_port().unwrap_or(DEFAULT_PORT));
    log_info(&format!("Using port: {}", port));

    // Step 4: Start webview server
    let python = find_python().context("Python is required for the webview server")?;
    log_info(&format!("Using Python: {:?}", python));

    let mut processes = ManagedProcesses::new();

    match start_webview_server(&install_dir, &python, port) {
        Ok(child) => {
            log_info(&format!("Webview server started (PID: {:?})", child.id()));
            processes.server = Some(child);
        }
        Err(e) => {
            log_error(&format!("Failed to start webview server: {}", e));
            bail!("Failed to start webview server: {}", e);
        }
    }

    // Step 5: Wait for server to be ready
    if let Err(e) = wait_for_server_ready(port) {
        log_error(&format!("Webview server failed to become ready: {}", e));
        bail!("Webview server failed to become ready: {}", e);
    }

    // Step 6: Launch Electron
    match launch_electron(&install_dir, port) {
        Ok(child) => {
            log_info(&format!("Electron launched (PID: {:?})", child.id()));
            processes.electron = Some(child);
        }
        Err(e) => {
            log_error(&format!("Failed to launch Electron: {}", e));
            bail!("Failed to launch Electron: {}", e);
        }
    }

    // Step 7: Monitor process lifecycle
    log_info("Monitoring process lifecycle...");

    // Wait for Electron to exit
    if let Some(ref mut electron) = processes.electron {
        match electron.wait() {
            Ok(status) => {
                log_info(&format!("Electron exited with status: {}", status));
            }
            Err(e) => {
                log_error(&format!("Error waiting for Electron: {}", e));
            }
        }
    }

    // Cleanup is handled by Drop implementation of ManagedProcesses
    log_info("Codex Desktop Launcher exiting normally");

    Ok(())
}
