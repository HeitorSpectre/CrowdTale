//! WebSocket link to the room's `/v1/link` on the relay, used when Steam P2P
//! isn't available. Uses WinHTTP for TLS and WebSockets.
//!
//! Only `allowed_base` hosts can be reached, so the local API can't be used to
//! point the game anywhere else.

use crate::log;
use std::ffi::c_void;
use std::sync::atomic::{AtomicBool, AtomicIsize, AtomicU64, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

type Handle = isize;

#[link(name = "winhttp")]
extern "system" {
    fn WinHttpOpen(agent: *const u16, access: u32, proxy: *const u16, bypass: *const u16, flags: u32) -> Handle;
    fn WinHttpConnect(session: Handle, server: *const u16, port: u16, reserved: u32) -> Handle;
    fn WinHttpOpenRequest(
        connect: Handle,
        verb: *const u16,
        object: *const u16,
        version: *const u16,
        referrer: *const u16,
        accept: *const *const u16,
        flags: u32,
    ) -> Handle;
    fn WinHttpSetOption(h: Handle, option: u32, buffer: *const c_void, len: u32) -> i32;
    fn WinHttpSetTimeouts(h: Handle, resolve: i32, connect: i32, send: i32, receive: i32) -> i32;
    fn WinHttpSendRequest(
        h: Handle,
        headers: *const u16,
        headers_len: u32,
        optional: *const c_void,
        optional_len: u32,
        total: u32,
        context: usize,
    ) -> i32;
    fn WinHttpReceiveResponse(h: Handle, reserved: *mut c_void) -> i32;
    fn WinHttpQueryHeaders(h: Handle, info: u32, name: *const u16, buffer: *mut c_void, len: *mut u32, index: *mut u32) -> i32;
    fn WinHttpWebSocketCompleteUpgrade(h: Handle, context: usize) -> Handle;
    fn WinHttpWebSocketSend(ws: Handle, kind: u32, buffer: *const c_void, len: u32) -> u32;
    fn WinHttpWebSocketReceive(ws: Handle, buffer: *mut c_void, len: u32, read: *mut u32, kind: *mut u32) -> u32;
    fn WinHttpWebSocketClose(ws: Handle, status: u16, reason: *const c_void, len: u32) -> u32;
    fn WinHttpCloseHandle(h: Handle) -> i32;
}

const ACCESS_DEFAULT_PROXY: u32 = 0;
const FLAG_SECURE: u32 = 0x0080_0000;
const OPTION_UPGRADE_TO_WEB_SOCKET: u32 = 114;
const QUERY_STATUS_CODE: u32 = 19;
const QUERY_FLAG_NUMBER: u32 = 0x2000_0000;
const WS_UTF8_MESSAGE: u32 = 2;
const WS_UTF8_FRAGMENT: u32 = 3;
const WS_CLOSE: u32 = 4;

const PING_EVERY: Duration = Duration::from_secs(25);
const MAX_INBOX: usize = 512;

#[derive(Clone, PartialEq)]
struct Target {
    secure: bool,
    host: String,
    port: u16,
    path: String, // "/v1/link?code=...&token=..."
}

static TARGET: Mutex<Option<Target>> = Mutex::new(None);
static GENERATION: AtomicU64 = AtomicU64::new(0);
static SOCKET: AtomicIsize = AtomicIsize::new(0);
static CONNECTED: AtomicBool = AtomicBool::new(false);
static SEND_LOCK: Mutex<()> = Mutex::new(());
static INBOX: Mutex<Vec<(String, String)>> = Mutex::new(Vec::new());

fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

/// The production relay, or wrangler dev on localhost.
fn allowed_base(base: &str) -> Option<(bool, String, u16)> {
    let base = base.trim_end_matches('/');
    match base {
        "https://crowdtale.crowdtale.workers.dev" => Some((true, "crowdtale.crowdtale.workers.dev".into(), 443)),
        "http://127.0.0.1:8787" => Some((false, "127.0.0.1".into(), 8787)),
        _ => None,
    }
}

fn clean_code(code: &str) -> Option<String> {
    let code: String = code.chars().filter(|c| *c != '-').collect::<String>().to_ascii_uppercase();
    (code.len() == 6 && code.chars().all(|c| c.is_ascii_alphanumeric())).then_some(code)
}

fn clean_token(token: &str) -> Option<String> {
    (token.len() == 32 && token.chars().all(|c| c.is_ascii_hexdigit())).then(|| token.to_ascii_lowercase())
}

/// Starts (or keeps) the link to this room. Same room and token again: no-op.
pub fn start(base: &str, code: &str, token: &str) -> bool {
    let (Some((secure, host, port)), Some(code), Some(token)) = (allowed_base(base), clean_code(code), clean_token(token)) else {
        return false;
    };
    let target = Target { secure, host, port, path: format!("/v1/link?code={code}&token={token}") };
    {
        let mut current = TARGET.lock().unwrap_or_else(|e| e.into_inner());
        if current.as_ref() == Some(&target) {
            return true;
        }
        *current = Some(target);
    }
    let generation = GENERATION.fetch_add(1, Ordering::SeqCst) + 1;
    close_socket();
    let _ = std::thread::Builder::new().name("crowdtale-relay".into()).spawn(move || {
        let _ = std::panic::catch_unwind(|| run(generation));
    });
    log::line("relay link: starting");
    true
}

/// Leaves the room's link.
pub fn stop() {
    let had = TARGET.lock().unwrap_or_else(|e| e.into_inner()).take().is_some();
    GENERATION.fetch_add(1, Ordering::SeqCst);
    close_socket();
    INBOX.lock().unwrap_or_else(|e| e.into_inner()).clear();
    if had {
        log::line("relay link: stopped");
    }
}

pub fn connected() -> bool {
    CONNECTED.load(Ordering::SeqCst)
}

fn current(generation: u64) -> Option<Target> {
    if GENERATION.load(Ordering::SeqCst) != generation {
        return None;
    }
    TARGET.lock().unwrap_or_else(|e| e.into_inner()).clone()
}

fn close_socket() {
    CONNECTED.store(false, Ordering::SeqCst);
    let ws = SOCKET.swap(0, Ordering::SeqCst);
    if ws != 0 {
        unsafe {
            WinHttpWebSocketClose(ws, 1000, std::ptr::null(), 0);
            WinHttpCloseHandle(ws);
        }
    }
}

fn run(generation: u64) {
    let mut wait = Duration::from_secs(1);
    let mut announced_failure = false;
    while let Some(target) = current(generation) {
        match unsafe { connect(&target) } {
            Ok((session, connection, ws)) => {
                if current(generation).is_none() {
                    unsafe {
                        WinHttpWebSocketClose(ws, 1000, std::ptr::null(), 0);
                        WinHttpCloseHandle(ws);
                        WinHttpCloseHandle(connection);
                        WinHttpCloseHandle(session);
                    }
                    return;
                }
                SOCKET.store(ws, Ordering::SeqCst);
                CONNECTED.store(true, Ordering::SeqCst);
                log::line("relay link: connected");
                announced_failure = false;
                wait = Duration::from_secs(1);
                spawn_pinger(generation, ws);
                unsafe { receive_loop(ws) };
                CONNECTED.store(false, Ordering::SeqCst);
                if SOCKET.compare_exchange(ws, 0, Ordering::SeqCst, Ordering::SeqCst).is_ok() {
                    unsafe {
                        WinHttpWebSocketClose(ws, 1000, std::ptr::null(), 0);
                        WinHttpCloseHandle(ws);
                    }
                }
                unsafe {
                    WinHttpCloseHandle(connection);
                    WinHttpCloseHandle(session);
                }
                if current(generation).is_some() {
                    log::line("relay link: lost, reconnecting");
                }
            }
            Err(why) => {
                if !announced_failure {
                    log::line(&format!("relay link: cannot connect ({why}), retrying"));
                    announced_failure = true;
                }
                // 403: no longer in the room.
                if why.contains("403") {
                    return;
                }
            }
        }
        std::thread::sleep(wait);
        wait = (wait * 2).min(Duration::from_secs(15));
    }
}

unsafe fn connect(t: &Target) -> Result<(Handle, Handle, Handle), String> {
    let agent = wide("WolfCoop/0.1");
    let session = WinHttpOpen(agent.as_ptr(), ACCESS_DEFAULT_PROXY, std::ptr::null(), std::ptr::null(), 0);
    if session == 0 {
        return Err("open".into());
    }
    WinHttpSetTimeouts(session, 10_000, 10_000, 10_000, 0);
    let host = wide(&t.host);
    let connection = WinHttpConnect(session, host.as_ptr(), t.port, 0);
    if connection == 0 {
        WinHttpCloseHandle(session);
        return Err("connect".into());
    }
    let verb = wide("GET");
    let path = wide(&t.path);
    let request = WinHttpOpenRequest(
        connection,
        verb.as_ptr(),
        path.as_ptr(),
        std::ptr::null(),
        std::ptr::null(),
        std::ptr::null(),
        if t.secure { FLAG_SECURE } else { 0 },
    );
    let fail = |what: String| {
        WinHttpCloseHandle(connection);
        WinHttpCloseHandle(session);
        Err(what)
    };
    if request == 0 {
        return fail("request".into());
    }
    let ok = WinHttpSetOption(request, OPTION_UPGRADE_TO_WEB_SOCKET, std::ptr::null(), 0) != 0
        && WinHttpSendRequest(request, std::ptr::null(), 0, std::ptr::null(), 0, 0, 0) != 0
        && WinHttpReceiveResponse(request, std::ptr::null_mut()) != 0;
    if !ok {
        WinHttpCloseHandle(request);
        return fail("no answer".into());
    }
    let mut status: u32 = 0;
    let mut len = 4u32;
    WinHttpQueryHeaders(
        request,
        QUERY_STATUS_CODE | QUERY_FLAG_NUMBER,
        std::ptr::null(),
        &mut status as *mut u32 as *mut c_void,
        &mut len,
        std::ptr::null_mut(),
    );
    if status != 101 {
        WinHttpCloseHandle(request);
        return fail(format!("HTTP {status}"));
    }
    let ws = WinHttpWebSocketCompleteUpgrade(request, 0);
    WinHttpCloseHandle(request);
    if ws == 0 {
        return fail("upgrade".into());
    }
    Ok((session, connection, ws))
}

unsafe fn receive_loop(ws: Handle) {
    let mut buf = vec![0u8; 8192];
    let mut message: Vec<u8> = Vec::new();
    loop {
        let mut read = 0u32;
        let mut kind = 0u32;
        let err = WinHttpWebSocketReceive(ws, buf.as_mut_ptr() as *mut c_void, buf.len() as u32, &mut read, &mut kind);
        if err != 0 || kind == WS_CLOSE {
            return;
        }
        message.extend_from_slice(&buf[..read as usize]);
        if message.len() > 16 * 1024 {
            message.clear(); // nothing that big is ever sent; drop it
            continue;
        }
        if kind == WS_UTF8_FRAGMENT {
            continue;
        }
        if kind == WS_UTF8_MESSAGE {
            if let Ok(text) = String::from_utf8(std::mem::take(&mut message)) {
                // "<sender id>\t<text>" from the relay.
                if let Some((from, data)) = text.split_once('\t') {
                    if data.starts_with("X|") {
                        // Save transfer chunk, handled here.
                        crate::saves::receive_piece(data);
                    } else if from.chars().all(|c| c.is_ascii_digit()) && !from.is_empty() {
                        let mut inbox = INBOX.lock().unwrap_or_else(|e| e.into_inner());
                        if inbox.len() < MAX_INBOX {
                            inbox.push((format!("r{from}"), data.to_string()));
                        }
                    }
                }
            }
        }
        message.clear();
    }
}

/// Keep-alive for idle links.
fn spawn_pinger(generation: u64, ws: Handle) {
    let _ = std::thread::Builder::new().name("crowdtale-relay-ping".into()).spawn(move || {
        let mut last = Instant::now();
        loop {
            std::thread::sleep(Duration::from_secs(1));
            if GENERATION.load(Ordering::SeqCst) != generation || SOCKET.load(Ordering::SeqCst) != ws {
                return;
            }
            if last.elapsed() >= PING_EVERY {
                last = Instant::now();
                send_raw(".");
            }
        }
    });
}

fn send_raw(text: &str) -> bool {
    let _guard = SEND_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let ws = SOCKET.load(Ordering::SeqCst);
    if ws == 0 {
        return false;
    }
    unsafe { WinHttpWebSocketSend(ws, WS_UTF8_MESSAGE, text.as_ptr() as *const c_void, text.len() as u32) == 0 }
}

/// To every other game of the room. False when the link is not up.
pub fn send(text: &str) -> bool {
    if text == "." || !connected() {
        return false;
    }
    send_raw(text)
}

/// Messages from the other games: (sender "rN", text).
pub fn receive(max: usize) -> Vec<(String, String)> {
    let mut inbox = INBOX.lock().unwrap_or_else(|e| e.into_inner());
    let n = inbox.len().min(max);
    inbox.drain(..n).collect()
}
