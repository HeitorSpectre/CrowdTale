//! Local HTTP API for the mod's Lua. Always answers 200 + JSON (the game drops
//! other statuses) and echoes `rid`.
//!
//! Bound to 127.0.0.1; the Host header must match (DNS rebinding) and any
//! request with a browser Origin/Referer is refused.
//!
//!   /v1/hello                 {mode, steam, name, id}
//!   /v1/pending               {join: CODE|null, from}  (consumed once)
//!   /v1/host?code=ABC123      friends see "Join game"; invites carry the code
//!   /v1/invite                opens Steam's invite dialog
//!   /v1/leave                 clears the above
//!   /v1/peers?ids=a,b         players of the session (only they get through)
//!   /v1/send?to=all|ID&data=  one message (<= 1200 bytes, text)
//!   /v1/recv                  {msgs: [{from, data}]}

use crate::config::Config;
use crate::log;
use crate::net;
use crate::steam;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::time::Duration;

pub fn serve(cfg: &Config) {
    let listener = match TcpListener::bind(("127.0.0.1", cfg.port)) {
        Ok(l) => l,
        Err(e) => {
            log::line(&format!("cannot listen on 127.0.0.1:{} ({e})", cfg.port));
            return;
        }
    };
    log::line(&format!("listening on 127.0.0.1:{}", cfg.port));
    for stream in listener.incoming() {
        let Ok(stream) = stream else { continue };
        let port = cfg.port;
        let _ = std::panic::catch_unwind(move || handle(stream, port));
    }
}

fn handle(mut stream: TcpStream, port: u16) {
    let _ = stream.set_read_timeout(Some(Duration::from_secs(2)));
    let _ = stream.set_write_timeout(Some(Duration::from_secs(2)));
    let mut buf = Vec::with_capacity(2048);
    let mut chunk = [0u8; 1024];
    while !buf.windows(4).any(|w| w == b"\r\n\r\n") {
        match stream.read(&mut chunk) {
            Ok(0) | Err(_) => break,
            Ok(n) => buf.extend_from_slice(&chunk[..n]),
        }
        if buf.len() > 8192 {
            return;
        }
    }
    let text = String::from_utf8_lossy(&buf).into_owned();
    let mut lines = text.split("\r\n");
    let request = lines.next().unwrap_or("");
    let mut parts = request.split(' ');
    let method = parts.next().unwrap_or("");
    let target = parts.next().unwrap_or("");
    let mut host_ok = false;
    let mut browser = false;
    for line in lines {
        let Some((key, value)) = line.split_once(':') else { continue };
        let key = key.trim().to_ascii_lowercase();
        let value = value.trim();
        if key == "host" {
            host_ok = value == format!("127.0.0.1:{port}") || value == format!("localhost:{port}");
        } else if key == "origin" || key == "referer" {
            browser = true;
        }
    }
    let (path, query) = target.split_once('?').unwrap_or((target, ""));
    let params = parse_query(query);
    let rid = params.iter().find(|(k, _)| k == "rid").map(|(_, v)| v.clone()).unwrap_or_default();
    let rid: u64 = rid.parse().unwrap_or(0);
    let body = if method != "GET" || !host_ok || browser {
        format!("{{\"ok\":false,\"rid\":{rid},\"error\":\"refused\"}}")
    } else {
        route(path, &params, rid)
    };
    let response = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        body.len(),
        body
    );
    let _ = stream.write_all(response.as_bytes());
}

fn param<'a>(params: &'a [(String, String)], key: &str) -> Option<&'a str> {
    params.iter().find(|(k, _)| k == key).map(|(_, v)| v.as_str())
}

fn route(path: &str, params: &[(String, String)], rid: u64) -> String {
    match path {
        "/v1/hello" => {
            let name = steam::persona_name();
            let id = net::my_id();
            format!(
                "{{\"ok\":true,\"rid\":{rid},\"version\":\"{}\",\"mode\":\"{}\",\"steam\":{},\"name\":{},\"id\":{},\"autoqte\":{},\"relay\":{}}}",
                env!("CARGO_PKG_VERSION"),
                if net::is_local() { "local" } else { "steam" },
                steam::ready(),
                json_opt(name.as_deref()),
                json_opt(id.as_deref()),
                crate::config::auto_qte(),
                crate::relay::connected()
            )
        }
        "/v1/pending" => match steam::take_pending() {
            Some((code, from)) => format!("{{\"ok\":true,\"rid\":{rid},\"join\":\"{code}\",\"from\":\"{from}\"}}"),
            None => format!("{{\"ok\":true,\"rid\":{rid},\"join\":null}}"),
        },
        "/v1/host" => {
            let code = param(params, "code").unwrap_or("");
            let code: String = code.chars().filter(|c| c.is_ascii_alphanumeric()).collect::<String>().to_ascii_uppercase();
            if code.len() != 6 {
                return format!("{{\"ok\":false,\"rid\":{rid},\"error\":\"bad code\"}}");
            }
            let ok = steam::host(&code);
            format!("{{\"ok\":{ok},\"rid\":{rid}}}")
        }
        "/v1/invite" => {
            let ok = steam::invite();
            format!("{{\"ok\":{ok},\"rid\":{rid}}}")
        }
        "/v1/relay" => {
            let ok = crate::relay::start(
                param(params, "base").unwrap_or(""),
                param(params, "code").unwrap_or(""),
                param(params, "token").unwrap_or(""),
            );
            format!("{{\"ok\":{ok},\"rid\":{rid},\"connected\":{}}}", crate::relay::connected())
        }
        "/v1/savesend" => match crate::saves::send() {
            Ok((files, bytes)) => format!("{{\"ok\":true,\"rid\":{rid},\"files\":{files},\"bytes\":{bytes}}}"),
            Err(e) => format!("{{\"ok\":false,\"rid\":{rid},\"error\":{}}}", json_str(&e)),
        },
        "/v1/saveready" => {
            format!(
                "{{\"ok\":true,\"rid\":{rid},\"ready\":\"{}\",\"sending\":{}}}",
                crate::saves::ready(),
                crate::saves::sending()
            )
        }
        "/v1/leave" => {
            crate::relay::stop();
            steam::leave();
            format!("{{\"ok\":true,\"rid\":{rid}}}")
        }
        "/v1/peers" => {
            let ids: Vec<u64> = param(params, "ids")
                .unwrap_or("")
                .split(',')
                .filter_map(|s| s.trim().parse().ok())
                .collect();
            steam::set_allowed(&ids);
            format!("{{\"ok\":true,\"rid\":{rid},\"peers\":{}}}", ids.len())
        }
        "/v1/send" => {
            let to = param(params, "to").unwrap_or("all");
            let data = param(params, "data").unwrap_or("");
            let sent = net::send(to, data.as_bytes());
            format!("{{\"ok\":{},\"rid\":{rid},\"sent\":{sent}}}", sent > 0)
        }
        "/v1/recv" => {
            let msgs = net::receive(64);
            let items: Vec<String> = msgs
                .iter()
                .map(|(from, data)| format!("{{\"from\":{},\"data\":{}}}", json_str(from), json_str(data)))
                .collect();
            format!("{{\"ok\":true,\"rid\":{rid},\"msgs\":[{}]}}", items.join(","))
        }
        "/v1/log" => {
            let msg = param(params, "msg").unwrap_or("");
            let msg: String = msg.chars().filter(|c| !c.is_control()).take(300).collect();
            log::line(&format!("lua: {msg}"));
            format!("{{\"ok\":true,\"rid\":{rid}}}")
        }
        _ => format!("{{\"ok\":false,\"rid\":{rid},\"error\":\"unknown endpoint\"}}"),
    }
}

fn parse_query(query: &str) -> Vec<(String, String)> {
    query
        .split('&')
        .filter(|s| !s.is_empty())
        .take(16)
        .map(|pair| {
            let (k, v) = pair.split_once('=').unwrap_or((pair, ""));
            (decode(k), decode(v))
        })
        .collect()
}

fn decode(s: &str) -> String {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'+' => out.push(b' '),
            b'%' if i + 2 < bytes.len() => {
                let hex = std::str::from_utf8(&bytes[i + 1..i + 3]).unwrap_or("");
                match u8::from_str_radix(hex, 16) {
                    Ok(b) => {
                        out.push(b);
                        i += 2;
                    }
                    Err(_) => out.push(b'%'),
                }
            }
            b => out.push(b),
        }
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

pub fn json_str(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

fn json_opt(s: Option<&str>) -> String {
    match s {
        Some(s) => json_str(s),
        None => "null".to_string(),
    }
}
