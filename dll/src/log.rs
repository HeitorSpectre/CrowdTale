//! wolfcoop.log next to the DLL. Size-capped; events only, no message contents.

use crate::config::Config;
use std::io::Write;
use std::path::PathBuf;
use std::sync::Mutex;

static PATH: Mutex<Option<PathBuf>> = Mutex::new(None);
const MAX_BYTES: u64 = 256 * 1024;

pub fn init(cfg: &Config) {
    if !cfg.log {
        return;
    }
    let path = cfg.folder.join("wolfcoop.log");
    if std::fs::metadata(&path).map(|m| m.len() > MAX_BYTES).unwrap_or(false) {
        let _ = std::fs::remove_file(&path);
    }
    if let Ok(mut guard) = PATH.lock() {
        *guard = Some(path);
    }
}

pub fn line(text: &str) {
    let path = match PATH.lock() {
        Ok(guard) => guard.clone(),
        Err(_) => None,
    };
    let Some(path) = path else { return };
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    if let Ok(mut file) = std::fs::OpenOptions::new().create(true).append(true).open(path) {
        let _ = writeln!(file, "[{secs}] {text}");
    }
}
