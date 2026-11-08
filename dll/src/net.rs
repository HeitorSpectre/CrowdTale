//! Game-to-game messages: relay link, Steam P2P, or localhost UDP in local mode.

use crate::config::{Config, Mode};
use crate::log;
use crate::steam;
use std::net::{SocketAddr, UdpSocket};
use std::sync::OnceLock;

struct Local {
    socket: UdpSocket,
    peer: SocketAddr,
    port: u16,
}

static LOCAL: OnceLock<Local> = OnceLock::new();
static MODE: OnceLock<Mode> = OnceLock::new();

pub const MAX_MESSAGE: usize = 1200;

pub fn init(cfg: &Config) {
    let _ = MODE.set(cfg.mode.clone());
    if cfg.mode == Mode::Local {
        match UdpSocket::bind(("127.0.0.1", cfg.local_port)) {
            Ok(socket) => {
                let _ = socket.set_nonblocking(true);
                let peer = SocketAddr::from(([127, 0, 0, 1], cfg.peer_port));
                let _ = LOCAL.set(Local { socket, peer, port: cfg.local_port });
                log::line(&format!("local test link on UDP {} -> {}", cfg.local_port, cfg.peer_port));
            }
            Err(e) => log::line(&format!("local test link failed: {e}")),
        }
    }
}

pub fn is_local() -> bool {
    matches!(MODE.get(), Some(Mode::Local))
}

/// This game's id for the other players: the Steam id, or "local-PORT".
pub fn my_id() -> Option<String> {
    if let Some(local) = LOCAL.get() {
        return Some(format!("local-{}", local.port));
    }
    steam::steam_id().map(|id| id.to_string())
}

/// Sends to one player (id) or to every player of the session ("all").
/// Returns how many players it went to.
pub fn send(to: &str, data: &[u8]) -> usize {
    if data.is_empty() || data.len() > MAX_MESSAGE {
        return 0;
    }
    // Prefer the relay link (works with non-Steam copies too).
    if crate::relay::connected() {
        return match std::str::from_utf8(data) {
            Ok(text) if crate::relay::send(text) => 1,
            _ => 0,
        };
    }
    if let Some(local) = LOCAL.get() {
        return local.socket.send_to(data, local.peer).map(|_| 1).unwrap_or(0);
    }
    if to == "all" {
        steam::allowed().into_iter().filter(|id| steam::send(*id, data)).count()
    } else {
        match to.parse::<u64>() {
            Ok(id) if steam::send(id, data) => 1,
            _ => 0,
        }
    }
}

/// Messages waiting for this game: (sender id, text). Non-UTF-8 is dropped.
pub fn receive(max: usize) -> Vec<(String, String)> {
    let mut out = crate::relay::receive(max);
    if let Some(local) = LOCAL.get() {
        let mut buf = [0u8; 2048];
        while out.len() < max {
            match local.socket.recv_from(&mut buf) {
                Ok((n, from)) => {
                    if from != local.peer || n == 0 || n > MAX_MESSAGE {
                        continue;
                    }
                    if let Ok(text) = String::from_utf8(buf[..n].to_vec()) {
                        out.push((format!("local-{}", local.peer.port()), text));
                    }
                }
                Err(_) => break,
            }
        }
        return out;
    }
    for (from, bytes) in steam::receive(max) {
        if let Ok(text) = String::from_utf8(bytes) {
            out.push((from.to_string(), text));
        }
    }
    out
}
