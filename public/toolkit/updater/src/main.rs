//! ═══════════════════════════════════════════════════════════════════════════════
//! Codex Desktop - Windows Updater (Rust)
//! ═══════════════════════════════════════════════════════════════════════════════
//!
//! Simplified Windows updater for Codex Desktop:
//! - Check upstream Codex.dmg for updates (ETag/If-None-Match)
//! - Download and verify new DMG
//! - Trigger rebuild pipeline
//! - Windows toast notifications
//! - Install update with UAC elevation
//! - Rollback support
//! - State persistence at %LOCALAPPDATA%\codex-update-manager\state.json
//! - Config at %APPDATA%\codex-update-manager\config.toml

#![cfg(target_os = "windows")]
#![windows_subsystem = "windows"]

use anyhow::{anyhow, bail, Context, Result};
use chrono::{DateTime, Utc};
use clap::{Arg, Command as ClapCommand};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use tokio::io::AsyncWriteExt;
use tracing::{error, info, warn, Level};
use tracing_subscriber::FmtSubscriber;

// ─── Constants ────────────────────────────────────────────────────────────────

const CODEX_DMG_URL: &str = "https://persistent.oaistatic.com/codex-app-prod/Codex.dmg";
const APP_NAME: &str = "Codex Desktop";
const UPDATER_NAME: &str = "codex-update-manager";

// ─── Configuration ───────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    /// URL to check for the Codex DMG
    pub dmg_url: String,
    /// How often to check for updates (in hours)
    pub check_interval_hours: u64,
    /// Whether auto-update is enabled
    pub auto_update: bool,
    /// Whether to show toast notifications
    pub show_notifications: bool,
    /// Whether to create rollback snapshots
    pub enable_rollback: bool,
    /// Maximum number of rollback snapshots to keep
    pub max_rollback_snapshots: usize,
}

impl Default for Config {
    fn default() -> Self {
        Config {
            dmg_url: CODEX_DMG_URL.to_string(),
            check_interval_hours: 6,
            auto_update: false,
            show_notifications: true,
            enable_rollback: true,
            max_rollback_snapshots: 3,
        }
    }
}

impl Config {
    fn config_dir() -> Result<PathBuf> {
        let app_data = std::env::var("APPDATA")
            .context("APPDATA environment variable not set")?;
        Ok(PathBuf::from(app_data).join(UPDATER_NAME))
    }

    fn config_path() -> Result<PathBuf> {
        Ok(Self::config_dir()?.join("config.toml"))
    }

    pub fn load() -> Result<Self> {
        let path = Self::config_path()?;
        if !path.exists() {
            let config = Self::default();
            config.save()?;
            return Ok(config);
        }

        let content = fs::read_to_string(&path)
            .context("Failed to read config file")?;
        let config: Config = toml::from_str(&content)
            .context("Failed to parse config file")?;
        Ok(config)
    }

    pub fn save(&self) -> Result<()> {
        let dir = Self::config_dir()?;
        fs::create_dir_all(&dir)?;

        let content = toml::to_string_pretty(self)
            .context("Failed to serialize config")?;
        fs::write(Self::config_path()?, content)
            .context("Failed to write config file")?;
        Ok(())
    }
}

// ─── Update State ─────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateState {
    /// Last known DMG ETag
    pub last_etag: Option<String>,
    /// Last known DMG SHA-256
    pub last_sha256: Option<String>,
    /// Last successful check time
    pub last_check: Option<DateTime<Utc>>,
    /// Last successful update time
    pub last_update: Option<DateTime<Utc>>,
    /// Current installed version
    pub installed_version: Option<String>,
    /// Current installed Electron version
    pub installed_electron_version: Option<String>,
    /// Current state
    pub state: UpdateStateEnum,
    /// Last error message
    pub last_error: Option<String>,
    /// Number of consecutive failures
    pub failure_count: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum UpdateStateEnum {
    Idle,
    Checking,
    Downloading,
    Verifying,
    Building,
    Installing,
    Installed,
    Failed,
    RolledBack,
}

impl Default for UpdateState {
    fn default() -> Self {
        UpdateState {
            last_etag: None,
            last_sha256: None,
            last_check: None,
            last_update: None,
            installed_version: None,
            installed_electron_version: None,
            state: UpdateStateEnum::Idle,
            last_error: None,
            failure_count: 0,
        }
    }
}

impl UpdateState {
    fn state_dir() -> Result<PathBuf> {
        let local_app_data = std::env::var("LOCALAPPDATA")
            .context("LOCALAPPDATA environment variable not set")?;
        Ok(PathBuf::from(local_app_data).join(UPDATER_NAME))
    }

    fn state_path() -> Result<PathBuf> {
        Ok(Self::state_dir()?.join("state.json"))
    }

    pub fn load() -> Result<Self> {
        let path = Self::state_path()?;
        if !path.exists() {
            return Ok(Self::default());
        }

        let content = fs::read_to_string(&path)
            .context("Failed to read state file")?;
        let state: UpdateState = serde_json::from_str(&content)
            .context("Failed to parse state file")?;
        Ok(state)
    }

    pub fn save(&self) -> Result<()> {
        let dir = Self::state_dir()?;
        fs::create_dir_all(&dir)?;

        let content = serde_json::to_string_pretty(self)
            .context("Failed to serialize state")?;

        // Use fs4 for safe file writes
        let path = Self::state_path()?;
        let temp_path = path.with_extension("json.tmp");

        fs::write(&temp_path, content)
            .context("Failed to write state file")?;
        fs::rename(&temp_path, &path)
            .context("Failed to rename state file")?;

        Ok(())
    }

    pub fn transition(&mut self, new_state: UpdateStateEnum) {
        info!("State transition: {:?} -> {:?}", self.state, new_state);
        self.state = new_state;
        if let Err(e) = self.save() {
            error!("Failed to save state: {}", e);
        }
    }
}

// ─── DMG Checker ─────────────────────────────────────────────────────────────

pub struct DmgChecker {
    client: reqwest::Client,
    config: Config,
}

impl DmgChecker {
    pub fn new(config: &Config) -> Result<Self> {
        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(30))
            .build()
            .context("Failed to create HTTP client")?;

        Ok(DmgChecker {
            client,
            config: config.clone(),
        })
    }

    /// Check if a new version of the DMG is available using ETag
    pub async fn check_for_update(&self, state: &mut UpdateState) -> Result<bool> {
        info!("Checking for updates at {}", self.config.dmg_url);
        state.transition(UpdateStateEnum::Checking);

        let mut request = self.client.head(&self.config.dmg_url);

        // Add If-None-Match header if we have a previous ETag
        if let Some(ref etag) = state.last_etag {
            request = request.header("If-None-Match", etag);
        }

        let response = request.send().await
            .context("Failed to check for updates")?;

        let status = response.status();
        info!("Update check response: {}", status);

        if status.as_u16() == 304 {
            // Not Modified
            info!("No update available (304 Not Modified)");
            state.last_check = Some(Utc::now());
            state.transition(UpdateStateEnum::Idle);
            return Ok(false);
        }

        if !status.is_success() {
            bail!("Update check failed with status: {}", status);
        }

        let new_etag = response.headers()
            .get("ETag")
            .and_then(|v| v.to_str().ok())
            .map(|s| s.to_string());

        let content_length = response.headers()
            .get("Content-Length")
            .and_then(|v| v.to_str().ok())
            .and_then(|s| s.parse::<u64>().ok());

        info!("ETag: {:?}, Content-Length: {:?}", new_etag, content_length);

        // Check if ETag changed
        let has_update = match (&state.last_etag, &new_etag) {
            (Some(old), Some(new)) => old != new,
            (None, Some(_)) => true,  // First check
            _ => false,
        };

        if has_update {
            info!("New version detected!");
            state.last_etag = new_etag;
            state.last_check = Some(Utc::now());

            if self.config.show_notifications {
                show_toast_notification(
                    "Codex Desktop Update Available",
                    "A new version of Codex Desktop is available. Click to update.",
                );
            }
        } else {
            info!("No update available");
            state.last_check = Some(Utc::now());
            state.transition(UpdateStateEnum::Idle);
        }

        Ok(has_update)
    }
}

// ─── DMG Downloader ──────────────────────────────────────────────────────────

pub struct DmgDownloader {
    client: reqwest::Client,
    config: Config,
}

impl DmgDownloader {
    pub fn new(config: &Config) -> Result<Self> {
        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(300))
            .build()
            .context("Failed to create HTTP client")?;

        Ok(DmgDownloader {
            client,
            config: config.clone(),
        })
    }

    /// Download the DMG file and verify its SHA-256 hash
    pub async fn download(&self, state: &mut UpdateState) -> Result<PathBuf> {
        info!("Downloading DMG from {}", self.config.dmg_url);
        state.transition(UpdateStateEnum::Downloading);

        let cache_dir = get_cache_dir()?;
        fs::create_dir_all(&cache_dir)?;

        let dmg_path = cache_dir.join("Codex.dmg");
        let temp_path = dmg_path.with_extension("dmg.downloading");

        // Download with progress
        let mut response = self.client.get(&self.config.dmg_url)
            .send()
            .await
            .context("Failed to download DMG")?;

        if !response.status().is_success() {
            bail!("DMG download failed with status: {}", response.status());
        }

        // Get ETag from response
        if let Some(etag) = response.headers().get("ETag").and_then(|v| v.to_str().ok()) {
            state.last_etag = Some(etag.to_string());
        }

        // Write to temp file
        let mut file = tokio::fs::File::create(&temp_path).await
            .context("Failed to create temp file")?;

        let mut total_bytes: u64 = 0;
        let mut hasher = Sha256::new();

        while let Some(chunk) = response.chunk().await
            .context("Error reading response chunk")?
        {
            hasher.update(&chunk);
            file.write_all(&chunk).await
                .context("Error writing chunk to file")?;
            total_bytes += chunk.len() as u64;
        }

        file.flush().await?;
        drop(file);

        // Compute SHA-256
        let hash = format!("{:x}", hasher.finalize());
        info!("Downloaded {} bytes, SHA-256: {}", total_bytes, hash);

        // Verify
        state.transition(UpdateStateEnum::Verifying);
        if let Some(ref expected_hash) = state.last_sha256 {
            if hash != *expected_hash {
                let _ = fs::remove_file(&temp_path);
                bail!("SHA-256 verification failed. Expected: {}, Got: {}", expected_hash, hash);
            }
        }

        state.last_sha256 = Some(hash);

        // Move temp to final path
        fs::rename(&temp_path, &dmg_path)
            .context("Failed to rename downloaded file")?;

        info!("DMG downloaded and verified: {:?}", dmg_path);
        Ok(dmg_path)
    }
}

// ─── Rebuild Pipeline ────────────────────────────────────────────────────────

pub struct RebuildPipeline;

impl RebuildPipeline {
    /// Trigger the rebuild pipeline to convert the new DMG to Windows
    pub fn run(dmg_path: &PathBuf, install_dir: &PathBuf) -> Result<()> {
        info!("Starting rebuild pipeline for {:?}", dmg_path);

        let install_script = install_dir.join("install.ps1");
        if !install_script.exists() {
            bail!("Install script not found: {:?}", install_script);
        }

        // Run the install script with the new DMG
        let output = Command::new("powershell")
            .args(&[
                "-NoProfile",
                "-ExecutionPolicy", "Bypass",
                "-File", &install_script.to_string_lossy(),
                "-DmgPath", &dmg_path.to_string_lossy(),
                "-InstallDir", &install_dir.to_string_lossy(),
            ])
            .output()
            .context("Failed to run rebuild pipeline")?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            bail!("Rebuild pipeline failed: {}", stderr);
        }

        info!("Rebuild pipeline completed successfully");
        Ok(())
    }
}

// ─── Rollback Support ────────────────────────────────────────────────────────

pub struct RollbackManager {
    config: Config,
}

impl RollbackManager {
    pub fn new(config: &Config) -> Self {
        RollbackManager { config: config.clone() }
    }

    /// Create a rollback snapshot of the current installation
    pub fn create_snapshot(&self, install_dir: &PathBuf) -> Result<String> {
        if !self.config.enable_rollback {
            info!("Rollback disabled, skipping snapshot");
            return Ok(String::new());
        }

        let snapshot_dir = get_cache_dir()?.join("snapshots");
        fs::create_dir_all(&snapshot_dir)?;

        let timestamp = Utc::now().format("%Y%m%d-%H%M%S");
        let snapshot_name = format!("snapshot-{}", timestamp);
        let snapshot_path = snapshot_dir.join(&snapshot_name);

        info!("Creating rollback snapshot: {:?}", snapshot_path);

        // Copy current installation to snapshot
        // (In practice, use hard links or a more efficient mechanism)
        self.copy_dir_recursive(install_dir, &snapshot_path)?;

        // Clean up old snapshots
        self.cleanup_old_snapshots(&snapshot_dir)?;

        Ok(snapshot_name)
    }

    /// Rollback to a previous snapshot
    pub fn rollback(&self, install_dir: &PathBuf, snapshot_name: &str) -> Result<()> {
        let snapshot_dir = get_cache_dir()?.join("snapshots");
        let snapshot_path = snapshot_dir.join(snapshot_name);

        if !snapshot_path.exists() {
            bail!("Snapshot not found: {:?}", snapshot_path);
        }

        info!("Rolling back to snapshot: {:?}", snapshot_path);

        // Remove current installation
        if install_dir.exists() {
            fs::remove_dir_all(install_dir)
                .context("Failed to remove current installation")?;
        }

        // Restore snapshot
        self.copy_dir_recursive(&snapshot_path, install_dir)?;

        info!("Rollback complete");
        Ok(())
    }

    fn copy_dir_recursive(&self, src: &PathBuf, dst: &PathBuf) -> Result<()> {
        if !dst.exists() {
            fs::create_dir_all(dst)?;
        }

        for entry in fs::read_dir(src).context("Failed to read directory")? {
            let entry = entry?;
            let src_path = entry.path();
            let dst_path = dst.join(entry.file_name());

            if src_path.is_dir() {
                self.copy_dir_recursive(&src_path, &dst_path)?;
            } else {
                fs::copy(&src_path, &dst_path)
                    .with_context(|| format!("Failed to copy {:?}", src_path))?;
            }
        }

        Ok(())
    }

    fn cleanup_old_snapshots(&self, snapshot_dir: &PathBuf) -> Result<()> {
        let mut snapshots: Vec<_> = fs::read_dir(snapshot_dir)?
            .filter_map(|e| e.ok())
            .filter(|e| e.file_name().to_string_lossy().starts_with("snapshot-"))
            .collect();

        snapshots.sort_by_key(|e| e.file_name());

        while snapshots.len() > self.config.max_rollback_snapshots {
            if let Some(old) = snapshots.first() {
                fs::remove_dir_all(old.path())?;
                snapshots.remove(0);
            }
        }

        Ok(())
    }
}

// ─── Toast Notifications ─────────────────────────────────────────────────────

fn show_toast_notification(title: &str, message: &str) {
    #[cfg(target_os = "windows")]
    {
        use windows::Data::Xml::Dom::XmlDocument;
        use windows::UI::Notifications::ToastNotificationManager;
        use windows::UI::Notifications::ToastTemplateType;
        use windows::UI::Notifications::ToastNotification;

        let toast_xml = ToastNotificationManager::GetTemplateContent(
            ToastTemplateType::ToastText02,
        ).ok();

        if let Some(xml) = toast_xml {
            if let Ok(xml_doc) = XmlDocument::new() {
                let template = format!(
                    r#"<toast>
                        <visual>
                            <binding template="ToastText02">
                                <text id="1">{}</text>
                                <text id="2">{}</text>
                            </binding>
                        </visual>
                    </toast>"#,
                    title, message
                );

                if xml_doc.LoadXml(&windows::core::HSTRING::from(&template)).is_ok() {
                    let toast = ToastNotification::CreateToastNotification(&xml_doc);
                    let _ = ToastNotificationManager::CreateToastNotifierWithId(
                        &windows::core::HSTRING::from("CodexDesktop"),
                    ).and_then(|notifier| notifier.Show(&toast));
                }
            }
        }
    }

    // Fallback: just log
    info!("Toast: {} - {}", title, message);
}

// ─── UAC Elevation ───────────────────────────────────────────────────────────

fn request_uac_elevation(command: &str, args: &[&str]) -> Result<()> {
    let output = Command::new("powershell")
        .args(&[
            "-NoProfile",
            "-Command",
            &format!(
                "Start-Process -FilePath '{}' -ArgumentList '{}' -Verb RunAs -Wait",
                command,
                args.join("' '")
            ),
        ])
        .output()
        .context("Failed to request UAC elevation")?;

    if !output.status.success() {
        bail!("UAC elevation failed or was denied");
    }

    Ok(())
}

// ─── Utility ─────────────────────────────────────────────────────────────────

fn get_cache_dir() -> Result<PathBuf> {
    let local_app_data = std::env::var("LOCALAPPDATA")
        .context("LOCALAPPDATA not set")?;
    Ok(PathBuf::from(local_app_data)
        .join(UPDATER_NAME)
        .join("cache"))
}

fn get_install_dir() -> Result<PathBuf> {
    // Check registry for install location
    let output = Command::new("reg")
        .args(&[
            "query",
            r"HKLM\SOFTWARE\Codex Desktop",
            "/v", "InstallDir",
        ])
        .output()
        .ok();

    if let Some(output) = output {
        if output.status.success() {
            let text = String::from_utf8_lossy(&output.stdout);
            if let Some(line) = text.lines().find(|l| l.contains("InstallDir")) {
                if let Some(path) = line.split("REG_SZ").nth(1) {
                    let path = path.trim();
                    let p = PathBuf::from(path);
                    if p.exists() {
                        return Ok(p);
                    }
                }
            }
        }
    }

    // Fallback: check default Program Files
    let program_files = std::env::var("ProgramFiles")
        .unwrap_or_else(|_| r"C:\Program Files".to_string());
    let install_dir = PathBuf::from(program_files).join(APP_NAME);

    if install_dir.exists() {
        Ok(install_dir)
    } else {
        bail!("Codex Desktop installation not found")
    }
}

// ─── Main Entry Point ────────────────────────────────────────────────────────

#[tokio::main]
async fn main() -> Result<()> {
    // Parse CLI arguments
    let matches = ClapCommand::new(UPDATER_NAME)
        .version("1.0.0")
        .about("Codex Desktop Update Manager for Windows")
        .subcommand_required(false)
        .arg(Arg::new("check")
            .long("check")
            .help("Check for updates"))
        .arg(Arg::new("update")
            .long("update")
            .help("Download and install updates"))
        .arg(Arg::new("rollback")
            .long("rollback")
            .value_name("SNAPSHOT")
            .help("Rollback to a specific snapshot"))
        .arg(Arg::new("quiet")
            .long("quiet")
            .help("Suppress notifications"))
        .arg(Arg::new("status")
            .long("status")
            .help("Show current update state"))
        .get_matches();

    // Initialize logging
    let log_dir = std::env::var("LOCALAPPDATA")
        .map(|p| PathBuf::from(p).join(UPDATER_NAME).join("logs"))
        .unwrap_or_else(|_| PathBuf::from("logs"));

    let _ = fs::create_dir_all(&log_dir);

    let subscriber = FmtSubscriber::builder()
        .with_max_level(Level::INFO)
        .with_writer(std::io::stderr)
        .finish();

    tracing::subscriber::set_global_default(subscriber)
        .context("Failed to set tracing subscriber")?;

    info!("{} starting...", UPDATER_NAME);

    // Load configuration
    let mut config = Config::load().context("Failed to load configuration")?;

    if matches.get_flag("quiet") {
        config.show_notifications = false;
    }

    // Load state
    let mut state = UpdateState::load().context("Failed to load update state")?;

    // Handle subcommands
    if matches.get_flag("status") {
        println!("{}", serde_json::to_string_pretty(&state)?);
        return Ok(());
    }

    if let Some(snapshot) = matches.get_one::<String>("rollback") {
        let rollback = RollbackManager::new(&config);
        let install_dir = get_install_dir()?;

        rollback.rollback(&install_dir, snapshot)?;
        state.transition(UpdateStateEnum::RolledBack);

        if config.show_notifications {
            show_toast_notification(
                "Codex Desktop Rollback",
                &format!("Rolled back to snapshot: {}", snapshot),
            );
        }

        return Ok(());
    }

    // Check for updates
    let checker = DmgChecker::new(&config)?;
    let has_update = checker.check_for_update(&mut state).await?;

    if !has_update {
        info!("No update available");
        return Ok(());
    }

    // Download and install if --update flag or auto_update enabled
    if matches.get_flag("update") || config.auto_update {
        let downloader = DmgDownloader::new(&config)?;
        let dmg_path = downloader.download(&mut state).await?;

        let install_dir = get_install_dir()?;

        // Create rollback snapshot before update
        let rollback = RollbackManager::new(&config);
        let snapshot_name = rollback.create_snapshot(&install_dir)?;

        // Trigger rebuild
        state.transition(UpdateStateEnum::Building);
        match RebuildPipeline::run(&dmg_path, &install_dir) {
            Ok(()) => {
                state.last_update = Some(Utc::now());
                state.failure_count = 0;
                state.transition(UpdateStateEnum::Installed);

                if config.show_notifications {
                    show_toast_notification(
                        "Codex Desktop Updated",
                        "Codex Desktop has been updated successfully.",
                    );
                }

                info!("Update completed successfully");
            }
            Err(e) => {
                state.failure_count += 1;
                state.last_error = Some(e.to_string());
                state.transition(UpdateStateEnum::Failed);

                error!("Update failed: {}", e);

                // Attempt rollback
                if config.enable_rollback && !snapshot_name.is_empty() {
                    info!("Attempting rollback...");
                    match rollback.rollback(&install_dir, &snapshot_name) {
                        Ok(()) => {
                            state.transition(UpdateStateEnum::RolledBack);
                            if config.show_notifications {
                                show_toast_notification(
                                    "Codex Desktop Update Rolled Back",
                                    "The update failed and was rolled back.",
                                );
                            }
                        }
                        Err(re) => {
                            error!("Rollback also failed: {}", re);
                        }
                    }
                }

                bail!("Update failed: {}", e);
            }
        }
    } else {
        // Just notify about available update
        info!("Update available but auto-update is disabled. Use --update to install.");
    }

    Ok(())
}
