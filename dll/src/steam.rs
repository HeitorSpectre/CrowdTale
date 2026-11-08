//! Steam via the game's own steam_api64.dll (flat API through GetProcAddress,
//! no SDK linked). Name/id, rich presence for invites, SteamNetworkingMessages.
//!
//! Callbacks: GameRichPresenceJoinRequested_t (invite accepted in-game) and
//! SteamNetworkingMessagesSessionRequest_t (only session players are accepted).

use crate::config::{self, Config};
use crate::log;
use crate::proxy::{wide, GetModuleHandleW, GetProcAddress};
use std::ffi::{c_char, c_void, CStr, CString};
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

type Ptr = *mut c_void;

struct Api {
    friends: usize,
    user: usize,
    msgs: usize,
    get_persona_name: extern "C" fn(Ptr) -> *const c_char,
    get_steam_id: extern "C" fn(Ptr) -> u64,
    set_rich_presence: extern "C" fn(Ptr, *const c_char, *const c_char) -> bool,
    clear_rich_presence: extern "C" fn(Ptr),
    invite_dialog: extern "C" fn(Ptr, *const c_char),
    identity_set: extern "C" fn(Ptr, u64),
    identity_get: extern "C" fn(Ptr) -> u64,
    send: extern "C" fn(Ptr, Ptr, *const c_void, u32, i32, i32) -> i32,
    receive: extern "C" fn(Ptr, i32, *mut Ptr, i32) -> i32,
    accept: extern "C" fn(Ptr, Ptr) -> bool,
    release: extern "C" fn(Ptr),
}

unsafe impl Send for Api {}
unsafe impl Sync for Api {}

static API: OnceLock<Api> = OnceLock::new();

struct State {
    pending_join: Option<String>,
    pending_from: u64,
    allowed: Vec<u64>,
    host_code: Option<String>,
}

static STATE: Mutex<State> = Mutex::new(State {
    pending_join: None,
    pending_from: 0,
    allowed: Vec::new(),
    host_code: None,
});

fn with_state<R>(f: impl FnOnce(&mut State) -> R) -> R {
    let mut guard = match STATE.lock() {
        Ok(g) => g,
        Err(poisoned) => poisoned.into_inner(),
    };
    f(&mut guard)
}

pub fn ready() -> bool {
    API.get().is_some()
}

fn api() -> Option<&'static Api> {
    API.get()
}

unsafe fn sym<T: Copy>(module: isize, name: &str) -> Option<T> {
    let c = CString::new(name).ok()?;
    let p = GetProcAddress(module, c.as_ptr() as *const u8);
    if p.is_null() {
        None
    } else {
        Some(std::mem::transmute_copy(&p))
    }
}

/// Waits for the game to init Steam, then resolves the API and registers callbacks.
pub fn start(cfg: &Config) {
    if let Some(code) = config::launch_join() {
        log::line("launched from a Steam invite");
        with_state(|s| s.pending_join = Some(code));
    }
    let cfg = cfg.clone();
    let _ = std::thread::Builder::new().name("crowdtale-steam-init".into()).spawn(move || {
        let _ = std::panic::catch_unwind(move || init_loop(&cfg));
    });
}

fn init_loop(_cfg: &Config) {
    let name = wide("steam_api64.dll");
    // Give up after ~10 minutes (non-Steam copies never init it).
    for _ in 0..1200 {
        std::thread::sleep(Duration::from_millis(500));
        let module = unsafe { GetModuleHandleW(name.as_ptr()) };
        if module == 0 {
            continue;
        }
        if let Some(api) = unsafe { resolve(module) } {
            let _ = API.set(api);
            unsafe { register_callbacks(module) };
            if let Some(utils) = unsafe { sym::<extern "C" fn() -> Ptr>(module, "SteamAPI_SteamNetworkingUtils_SteamAPI_v004") } {
                let utils = utils();
                if !utils.is_null() {
                    if let Some(init_relay) = unsafe { sym::<extern "C" fn(Ptr)>(module, "SteamAPI_ISteamNetworkingUtils_InitRelayNetworkAccess") } {
                        init_relay(utils);
                    }
                }
            }
            log::line("Steam ready");
            return;
        }
    }
    log::line("Steam not available (game started without Steam?)");
}

unsafe fn resolve(module: isize) -> Option<Api> {
    let friends_fn: extern "C" fn() -> Ptr = sym(module, "SteamAPI_SteamFriends_v018")?;
    let user_fn: extern "C" fn() -> Ptr = sym(module, "SteamAPI_SteamUser_v023")?;
    let msgs_fn: extern "C" fn() -> Ptr = sym(module, "SteamAPI_SteamNetworkingMessages_SteamAPI_v002")?;
    let friends = friends_fn();
    let user = user_fn();
    let msgs = msgs_fn();
    if friends.is_null() || user.is_null() || msgs.is_null() {
        return None; // the game has not initialised Steam yet
    }
    Some(Api {
        friends: friends as usize,
        user: user as usize,
        msgs: msgs as usize,
        get_persona_name: sym(module, "SteamAPI_ISteamFriends_GetPersonaName")?,
        get_steam_id: sym(module, "SteamAPI_ISteamUser_GetSteamID")?,
        set_rich_presence: sym(module, "SteamAPI_ISteamFriends_SetRichPresence")?,
        clear_rich_presence: sym(module, "SteamAPI_ISteamFriends_ClearRichPresence")?,
        invite_dialog: sym(module, "SteamAPI_ISteamFriends_ActivateGameOverlayInviteDialogConnectString")?,
        identity_set: sym(module, "SteamAPI_SteamNetworkingIdentity_SetSteamID64")?,
        identity_get: sym(module, "SteamAPI_SteamNetworkingIdentity_GetSteamID64")?,
        send: sym(module, "SteamAPI_ISteamNetworkingMessages_SendMessageToUser")?,
        receive: sym(module, "SteamAPI_ISteamNetworkingMessages_ReceiveMessagesOnChannel")?,
        accept: sym(module, "SteamAPI_ISteamNetworkingMessages_AcceptSessionWithUser")?,
        release: sym(module, "SteamAPI_SteamNetworkingMessage_t_Release")?,
    })
}

// ---- callbacks (CCallbackBase layout: vtable, u8 flags, i32 id) ----------

#[repr(C)]
struct CallbackObj {
    vtable: *const VTable,
    flags: u8,
    id: i32,
}

#[repr(C)]
struct VTable {
    // MSVC orders the two Run overloads in reverse; both use the same handler.
    run_a: extern "C" fn(*mut CallbackObj, Ptr),
    run_b: extern "C" fn(*mut CallbackObj, Ptr),
    size: extern "C" fn(*mut CallbackObj) -> i32,
}

const CB_JOIN_REQUESTED: i32 = 337; // GameRichPresenceJoinRequested_t
const CB_SESSION_REQUEST: i32 = 1251; // SteamNetworkingMessagesSessionRequest_t

extern "C" fn on_callback(this: *mut CallbackObj, param: Ptr) {
    let _ = std::panic::catch_unwind(|| unsafe {
        if this.is_null() || param.is_null() {
            return;
        }
        match (*this).id {
            CB_JOIN_REQUESTED => {
                // { CSteamID friend (8 bytes); char connect[256]; }
                let from = *(param as *const u64);
                let connect = CStr::from_ptr((param as *const u8).add(8) as *const c_char);
                if let Some(code) = config::parse_connect(&connect.to_string_lossy()) {
                    log::line("Steam join request received");
                    with_state(|s| {
                        s.pending_join = Some(code);
                        s.pending_from = from;
                        if !s.allowed.contains(&from) {
                            s.allowed.push(from);
                        }
                    });
                }
            }
            CB_SESSION_REQUEST => {
                // { SteamNetworkingIdentity remote; }
                if let Some(api) = api() {
                    let id = (api.identity_get)(param);
                    let ok = with_state(|s| s.allowed.contains(&id));
                    if ok {
                        (api.accept)(api.msgs as Ptr, param);
                    } else {
                        log::line("ignored a P2P session from a player outside the session");
                    }
                }
            }
            _ => {}
        }
    });
}

extern "C" fn size_join(_: *mut CallbackObj) -> i32 {
    8 + 256
}
extern "C" fn size_session(_: *mut CallbackObj) -> i32 {
    136
}

static VT_JOIN: VTable = VTable { run_a: on_callback, run_b: on_callback, size: size_join };
static VT_SESSION: VTable = VTable { run_a: on_callback, run_b: on_callback, size: size_session };

unsafe fn register_callbacks(module: isize) {
    let Some(register) = sym::<extern "C" fn(*mut CallbackObj, i32)>(module, "SteamAPI_RegisterCallback") else {
        log::line("SteamAPI_RegisterCallback missing");
        return;
    };
    for (vt, id) in [(&VT_JOIN as *const VTable, CB_JOIN_REQUESTED), (&VT_SESSION as *const VTable, CB_SESSION_REQUEST)] {
        // Leaked on purpose: Steam keeps the pointer.
        let obj = Box::leak(Box::new(CallbackObj { vtable: vt, flags: 0, id }));
        register(obj, id);
    }
}

// ---- queries used by the HTTP side ---------------------------------------

pub fn persona_name() -> Option<String> {
    let api = api()?;
    let p = (api.get_persona_name)(api.friends as Ptr);
    if p.is_null() {
        return None;
    }
    Some(unsafe { CStr::from_ptr(p) }.to_string_lossy().into_owned())
}

pub fn steam_id() -> Option<u64> {
    let api = api()?;
    let id = (api.get_steam_id)(api.user as Ptr);
    if id == 0 {
        None
    } else {
        Some(id)
    }
}

/// Pending invite code (consumed) and who sent it.
pub fn take_pending() -> Option<(String, u64)> {
    with_state(|s| s.pending_join.take().map(|c| (c, s.pending_from)))
}

/// Publishes `code` in rich presence so friends get "Join game".
pub fn host(code: &str) -> bool {
    with_state(|s| s.host_code = Some(code.to_string()));
    let Some(api) = api() else { return false };
    let connect = CString::new(format!("+wolfcoop {code}")).unwrap_or_default();
    let status = CString::new("CrowdTale").unwrap_or_default();
    let k_connect = CString::new("connect").unwrap_or_default();
    let k_status = CString::new("status").unwrap_or_default();
    (api.set_rich_presence)(api.friends as Ptr, k_status.as_ptr(), status.as_ptr());
    (api.set_rich_presence)(api.friends as Ptr, k_connect.as_ptr(), connect.as_ptr())
}

/// Opens Steam's invite dialog for the hosted session.
pub fn invite() -> bool {
    let Some(code) = with_state(|s| s.host_code.clone()) else { return false };
    let Some(api) = api() else { return false };
    let connect = CString::new(format!("+wolfcoop {code}")).unwrap_or_default();
    (api.invite_dialog)(api.friends as Ptr, connect.as_ptr());
    true
}

pub fn leave() {
    with_state(|s| {
        s.host_code = None;
        s.allowed.clear();
    });
    if let Some(api) = api() {
        (api.clear_rich_presence)(api.friends as Ptr);
    }
}

/// Session players; only they may open P2P sessions.
pub fn set_allowed(ids: &[u64]) {
    with_state(|s| {
        s.allowed = ids.iter().copied().filter(|i| *i != 0).take(16).collect();
    });
}

pub fn allowed() -> Vec<u64> {
    with_state(|s| s.allowed.clone())
}

const SEND_RELIABLE: i32 = 8;
const SEND_AUTO_RESTART: i32 = 32;

pub fn send(to: u64, data: &[u8]) -> bool {
    let Some(api) = api() else { return false };
    if !with_state(|s| s.allowed.contains(&to)) {
        return false;
    }
    let mut identity = [0u8; 136];
    (api.identity_set)(identity.as_mut_ptr() as Ptr, to);
    let result = (api.send)(
        api.msgs as Ptr,
        identity.as_mut_ptr() as Ptr,
        data.as_ptr() as *const c_void,
        data.len() as u32,
        SEND_RELIABLE | SEND_AUTO_RESTART,
        0,
    );
    result == 1 // k_EResultOK
}

/// Messages received on channel 0 from session players: (sender, bytes).
pub fn receive(max: usize) -> Vec<(u64, Vec<u8>)> {
    let mut out = Vec::new();
    let Some(api) = api() else { return out };
    let mut ptrs: Vec<Ptr> = vec![std::ptr::null_mut(); max.max(1)];
    let n = (api.receive)(api.msgs as Ptr, 0, ptrs.as_mut_ptr(), ptrs.len() as i32);
    for &msg in ptrs.iter().take(n.max(0) as usize) {
        if msg.is_null() {
            continue;
        }
        unsafe {
            // SteamNetworkingMessage_t: m_pData @0, m_cbSize @8, m_identityPeer @16
            let data = *(msg as *const *const u8);
            let size = *((msg as *const u8).add(8) as *const i32);
            let from = (api.identity_get)((msg as *mut u8).add(16) as Ptr);
            if with_state(|s| s.allowed.contains(&from)) && !data.is_null() && size > 0 && size <= 4096 {
                out.push((from, std::slice::from_raw_parts(data, size as usize).to_vec()));
            }
            (api.release)(msg);
        }
    }
    out
}
