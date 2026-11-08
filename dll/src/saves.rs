//! Sends the host's co-op save to the guests so everyone loads the exact same
//! point.
//!
//! Only slot 77 (`saveslot77.bundle`, `_saveslot77_*`) is ever read or
//! written; the player's own saves are never touched. Files travel over the
//! relay link in chunks ("X|...").

use crate::log;
use crate::relay;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;

pub const COOP_SLOT: &str = "saveslot77";
const CHUNK: usize = 900; // base64 characters per message (relay limit is 1200)
const MAX_TOTAL: usize = 8 * 1024 * 1024;

#[link(name = "shell32")]
extern "system" {
    fn SHGetFolderPathW(hwnd: isize, csidl: i32, token: isize, flags: u32, path: *mut u16) -> i32;
}

struct Incoming {
    count: usize,
    files: HashMap<usize, (String, usize, HashMap<usize, String>)>,
    bytes: usize,
}

static INCOMING: Mutex<Option<(u64, Incoming)>> = Mutex::new(None);
static READY: AtomicU64 = AtomicU64::new(0);
static SENDING: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

/// Host: a co-op save is still going out.
pub fn sending() -> bool {
    SENDING.load(Ordering::SeqCst)
}

fn documents() -> Option<PathBuf> {
    let mut buf = vec![0u16; 1024];
    let hr = unsafe { SHGetFolderPathW(0, 5, 0, 0, buf.as_mut_ptr()) }; // CSIDL_PERSONAL
    if hr != 0 {
        return None;
    }
    let n = buf.iter().position(|c| *c == 0).unwrap_or(0);
    Some(PathBuf::from(String::from_utf16_lossy(&buf[..n])))
}

/// Documents\Telltale Games\<game folder name>, or else the most recently
/// used folder there.
pub fn save_folder() -> Option<PathBuf> {
    let root = documents()?.join("Telltale Games");
    let game = crate::config::folder();
    if let Some(name) = game.file_name() {
        let dir = root.join(name);
        if dir.join("prefs.prop").exists() {
            return Some(dir);
        }
    }
    let mut best: Option<(std::time::SystemTime, PathBuf)> = None;
    for entry in std::fs::read_dir(&root).ok()?.flatten() {
        let dir = entry.path();
        let name = dir.file_name().map(|n| n.to_string_lossy().to_lowercase()).unwrap_or_default();
        if !name.contains("wolf") {
            continue;
        }
        if let Ok(meta) = std::fs::metadata(dir.join("prefs.prop")) {
            if let Ok(time) = meta.modified() {
                if best.as_ref().map(|(t, _)| time > *t).unwrap_or(true) {
                    best = Some((time, dir));
                }
            }
        }
    }
    best.map(|(_, dir)| dir)
}

/// True for co-op slot files only.
fn is_coop_file(name: &str) -> bool {
    if name == format!("{COOP_SLOT}.bundle") {
        return true;
    }
    let Some(rest) = name.strip_prefix(&format!("_{COOP_SLOT}_")) else { return false };
    let (stem, ext) = match rest.rsplit_once('.') {
        Some(x) => x,
        None => return false,
    };
    (ext == "bundle" || ext == "estore")
        && !stem.is_empty()
        && stem.len() <= 40
        && stem.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
}

fn coop_files(dir: &PathBuf) -> Vec<(String, PathBuf)> {
    let mut out = Vec::new();
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            if is_coop_file(&name) && entry.path().is_file() {
                out.push((name, entry.path()));
            }
        }
    }
    out.sort();
    out
}

const B64: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

fn b64_encode(data: &[u8]) -> String {
    let mut out = String::with_capacity((data.len() + 2) / 3 * 4);
    for chunk in data.chunks(3) {
        let b = [chunk[0], *chunk.get(1).unwrap_or(&0), *chunk.get(2).unwrap_or(&0)];
        let n = ((b[0] as u32) << 16) | ((b[1] as u32) << 8) | b[2] as u32;
        out.push(B64[(n >> 18) as usize & 63] as char);
        out.push(B64[(n >> 12) as usize & 63] as char);
        out.push(if chunk.len() > 1 { B64[(n >> 6) as usize & 63] as char } else { '=' });
        out.push(if chunk.len() > 2 { B64[n as usize & 63] as char } else { '=' });
    }
    out
}

fn b64_decode(text: &str) -> Option<Vec<u8>> {
    let mut out = Vec::with_capacity(text.len() / 4 * 3);
    let mut acc = 0u32;
    let mut bits = 0;
    for c in text.bytes() {
        let v = match c {
            b'A'..=b'Z' => c - b'A',
            b'a'..=b'z' => c - b'a' + 26,
            b'0'..=b'9' => c - b'0' + 52,
            b'+' => 62,
            b'/' => 63,
            b'=' => break,
            _ => return None,
        } as u32;
        acc = (acc << 6) | v;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((acc >> bits) as u8);
        }
    }
    Some(out)
}

/// Host: sends the co-op slot to the other games, paced under the relay's
/// rate limit. Returns (files, bytes).
pub fn send() -> Result<(usize, usize), String> {
    if !relay::connected() {
        return Err("no relay link".into());
    }
    let dir = save_folder().ok_or("save folder not found")?;
    let files = coop_files(&dir);
    if files.is_empty() {
        return Err("no co-op save yet".into());
    }
    let mut loaded = Vec::new();
    let mut total = 0usize;
    for (name, path) in &files {
        let data = std::fs::read(path).map_err(|e| format!("{name}: {e}"))?;
        total += data.len();
        if total > MAX_TOTAL {
            return Err("co-op save too big".into());
        }
        loaded.push((name.clone(), b64_encode(&data)));
    }
    let id = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(1);
    let count = loaded.len();
    log::line(&format!("co-op save: sending {count} files ({total} bytes)"));
    SENDING.store(true, Ordering::SeqCst);
    std::thread::spawn(move || {
        for (index, (name, text)) in loaded.iter().enumerate() {
            let pieces: Vec<&str> = text
                .as_bytes()
                .chunks(CHUNK)
                .map(|c| std::str::from_utf8(c).unwrap_or(""))
                .collect();
            let pieces = if pieces.is_empty() { vec![""] } else { pieces };
            for (i, piece) in pieces.iter().enumerate() {
                let msg = format!("X|{id}|{index}|{count}|{name}|{i}|{}|{piece}", pieces.len());
                let mut tries = 0;
                while !relay::send(&msg) && tries < 50 {
                    tries += 1;
                    std::thread::sleep(std::time::Duration::from_millis(100));
                }
                std::thread::sleep(std::time::Duration::from_millis(40));
            }
        }
        log::line("co-op save: sent");
        SENDING.store(false, Ordering::SeqCst);
    });
    Ok((count, total))
}

/// Guest: one chunk of the host's save; a finished transfer replaces slot 77.
pub fn receive_piece(text: &str) {
    let parts: Vec<&str> = text.splitn(8, '|').collect();
    if parts.len() != 8 || parts[0] != "X" {
        return;
    }
    let (Ok(id), Ok(index), Ok(count), name, Ok(piece), Ok(pieces), data) = (
        parts[1].parse::<u64>(),
        parts[2].parse::<usize>(),
        parts[3].parse::<usize>(),
        parts[4],
        parts[5].parse::<usize>(),
        parts[6].parse::<usize>(),
        parts[7],
    ) else {
        return;
    };
    if !is_coop_file(name) || count == 0 || count > 64 || index >= count || pieces == 0 || pieces > 20_000 || piece >= pieces {
        return;
    }
    let mut guard = INCOMING.lock().unwrap_or_else(|e| e.into_inner());
    if guard.as_ref().map(|(current, _)| *current != id).unwrap_or(true) {
        *guard = Some((id, Incoming { count, files: HashMap::new(), bytes: 0 }));
    }
    let Some((_, incoming)) = guard.as_mut() else { return };
    incoming.bytes += data.len();
    if incoming.bytes > MAX_TOTAL * 2 {
        *guard = None;
        return;
    }
    let entry = incoming.files.entry(index).or_insert_with(|| (name.to_string(), pieces, HashMap::new()));
    entry.2.insert(piece, data.to_string());
    let complete = incoming.files.len() == incoming.count
        && incoming.files.values().all(|(_, n, got)| got.len() == *n);
    if !complete {
        return;
    }
    let incoming = guard.take().map(|(_, inc)| inc);
    drop(guard);
    if let Some(incoming) = incoming {
        match write(incoming) {
            Ok(n) => {
                READY.store(id, Ordering::SeqCst);
                log::line(&format!("co-op save: received {n} files from the host"));
            }
            Err(e) => log::line(&format!("co-op save: could not write ({e})")),
        }
    }
}

fn write(incoming: Incoming) -> Result<usize, String> {
    let dir = save_folder().ok_or("save folder not found")?;
    let mut decoded = Vec::new();
    for (_, (name, n, pieces)) in incoming.files.iter() {
        let mut text = String::new();
        for i in 0..*n {
            text.push_str(pieces.get(&i).ok_or("missing piece")?);
        }
        decoded.push((name.clone(), b64_decode(&text).ok_or("bad data")?));
    }
    for (_, path) in coop_files(&dir) {
        let _ = std::fs::remove_file(path);
    }
    for (name, data) in &decoded {
        std::fs::write(dir.join(name), data).map_err(|e| format!("{name}: {e}"))?;
    }
    Ok(decoded.len())
}

/// Id of the last complete transfer written here (0 = none).
pub fn ready() -> u64 {
    READY.load(Ordering::SeqCst)
}
