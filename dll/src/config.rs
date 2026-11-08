//! Settings from `wolfcoop.cfg` next to the DLL (all optional):
//!
//!   port=47892         local HTTP port the mod's Lua talks to
//!   mode=steam|local   steam (default) or the two-copies-on-one-PC test
//!   local_port=48001   local mode: this copy's UDP port
//!   peer_port=48002    local mode: the other copy's UDP port
//!   log=1              write wolfcoop.log next to the DLL
//!   background=1       local test: keep running when the window is not in front
//!   autoqte=1          local test: the host's game hits its quick time events itself

use crate::proxy;
use std::path::PathBuf;
use std::sync::atomic::{AtomicIsize, Ordering};

static MODULE: AtomicIsize = AtomicIsize::new(0);
static AUTOQTE: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

pub fn auto_qte() -> bool {
    AUTOQTE.load(Ordering::SeqCst)
}

pub fn set_module(module: isize) {
    MODULE.store(module, Ordering::SeqCst);
}

#[derive(Clone, PartialEq)]
pub enum Mode {
    Steam,
    Local,
}

#[derive(Clone)]
pub struct Config {
    pub port: u16,
    pub mode: Mode,
    pub local_port: u16,
    pub peer_port: u16,
    pub log: bool,
    pub background: bool,
    pub folder: PathBuf,
}

impl Config {
    pub fn mode_name(&self) -> &'static str {
        match self.mode {
            Mode::Steam => "steam",
            Mode::Local => "local",
        }
    }
}

/// Folder of this DLL (the game folder).
pub fn folder() -> PathBuf {
    let module = MODULE.load(Ordering::SeqCst);
    let mut buf = vec![0u16; 1024];
    let n = unsafe { proxy::GetModuleFileNameW(module, buf.as_mut_ptr(), buf.len() as u32) } as usize;
    let path = String::from_utf16_lossy(&buf[..n.min(buf.len())]);
    PathBuf::from(path).parent().map(|p| p.to_path_buf()).unwrap_or_default()
}

pub fn load() -> Config {
    let folder = folder();
    let mut cfg = Config {
        port: 47892,
        mode: Mode::Steam,
        local_port: 48001,
        peer_port: 48002,
        log: true,
        background: false,
        folder: folder.clone(),
    };
    if let Ok(text) = std::fs::read_to_string(folder.join("wolfcoop.cfg")) {
        for line in text.lines() {
            let line = line.trim();
            if line.starts_with('#') {
                continue;
            }
            let Some((key, value)) = line.split_once('=') else { continue };
            let (key, value) = (key.trim(), value.trim());
            match key {
                "port" => cfg.port = value.parse().unwrap_or(cfg.port),
                "mode" => cfg.mode = if value == "local" { Mode::Local } else { Mode::Steam },
                "local_port" => cfg.local_port = value.parse().unwrap_or(cfg.local_port),
                "peer_port" => cfg.peer_port = value.parse().unwrap_or(cfg.peer_port),
                "log" => cfg.log = value != "0",
                "background" => cfg.background = value == "1",
                "autoqte" => AUTOQTE.store(value == "1", Ordering::SeqCst),
                _ => {}
            }
        }
    }
    if cfg.mode != Mode::Local {
        AUTOQTE.store(false, Ordering::SeqCst);
    }
    cfg
}

/// Session code from a Steam "Join game" launch (`+wolfcoop ABC123`).
pub fn launch_join() -> Option<String> {
    let ptr = unsafe { proxy::GetCommandLineW() };
    if ptr.is_null() {
        return None;
    }
    let mut len = 0usize;
    while unsafe { *ptr.add(len) } != 0 && len < 32768 {
        len += 1;
    }
    let line = String::from_utf16_lossy(unsafe { std::slice::from_raw_parts(ptr, len) });
    parse_connect(&line)
}

/// Parses `+wolfcoop CODE` (6 letters/digits) out of a command line.
pub fn parse_connect(text: &str) -> Option<String> {
    let mut words = text.split_whitespace();
    while let Some(word) = words.next() {
        if word.eq_ignore_ascii_case("+wolfcoop") {
            let code: String = words.next()?.chars().filter(|c| *c != '-').collect();
            let code = code.to_ascii_uppercase();
            if code.len() == 6 && code.chars().all(|c| c.is_ascii_alphanumeric()) {
                return Some(code);
            }
            return None;
        }
    }
    None
}
