//! CrowdTale Steam link for The Wolf Among Us Remastered.
//!
//! Loaded by the game as `dinput8.dll`: DirectInput is forwarded to the system
//! DLL, and a small HTTP server on 127.0.0.1 gives the mod's Lua (which only
//! has HttpGetAsync) access to Steam through the game's own steam_api64.dll:
//! player name, invites / "Join game", and P2P messages.
//!
//! `mode=local` in wolfcoop.cfg swaps Steam for UDP on localhost so two copies
//! can be tested on one PC.

mod background;
mod config;
mod http;
mod log;
mod net;
mod proxy;
mod relay;
mod saves;
mod steam;

use std::ffi::c_void;

#[allow(non_snake_case)]
#[no_mangle]
pub extern "system" fn DllMain(module: isize, reason: u32, _reserved: *mut c_void) -> i32 {
    const DLL_PROCESS_ATTACH: u32 = 1;
    if reason == DLL_PROCESS_ATTACH {
        unsafe { proxy::DisableThreadLibraryCalls(module) };
        config::set_module(module);
        // Nothing heavy under the loader lock.
        let _ = std::thread::Builder::new()
            .name("crowdtale-steam".into())
            .spawn(|| {
                let result = std::panic::catch_unwind(run);
                if result.is_err() {
                    log::line("link stopped after an internal error");
                }
            });
    }
    1
}

fn run() {
    let cfg = config::load();
    log::init(&cfg);
    log::line(&format!(
        "CrowdTale Steam link {} starting (mode={}, port={})",
        env!("CARGO_PKG_VERSION"),
        cfg.mode_name(),
        cfg.port
    ));
    if cfg.background {
        background::keep_running();
    }
    net::init(&cfg);
    steam::start(&cfg);
    http::serve(&cfg);
}
