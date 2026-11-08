//! `background=1` (local testing only): keeps the game running when its window
//! isn't in front, by swallowing the deactivation messages the engine pauses on.

use crate::log;
use std::sync::atomic::{AtomicIsize, Ordering};

type Hwnd = isize;
type WndProc = unsafe extern "system" fn(Hwnd, u32, usize, isize) -> isize;

#[link(name = "user32")]
extern "system" {
    fn EnumWindows(callback: unsafe extern "system" fn(Hwnd, isize) -> i32, param: isize) -> i32;
    fn GetWindowThreadProcessId(hwnd: Hwnd, pid: *mut u32) -> u32;
    fn IsWindowVisible(hwnd: Hwnd) -> i32;
    fn GetWindow(hwnd: Hwnd, cmd: u32) -> Hwnd;
    fn SetWindowLongPtrW(hwnd: Hwnd, index: i32, value: isize) -> isize;
    fn GetWindowLongPtrW(hwnd: Hwnd, index: i32) -> isize;
    fn CallWindowProcW(prev: isize, hwnd: Hwnd, msg: u32, wparam: usize, lparam: isize) -> isize;
}

#[link(name = "kernel32")]
extern "system" {
    fn GetCurrentProcessId() -> u32;
}

const GWLP_WNDPROC: i32 = -4;
const GW_OWNER: u32 = 4;
const WM_ACTIVATE: u32 = 0x0006;
const WM_KILLFOCUS: u32 = 0x0008;
const WM_ACTIVATEAPP: u32 = 0x001C;
const WM_NCACTIVATE: u32 = 0x0086;

static PREV: AtomicIsize = AtomicIsize::new(0);
static FOUND: AtomicIsize = AtomicIsize::new(0);

unsafe extern "system" fn find(hwnd: Hwnd, _param: isize) -> i32 {
    let mut pid = 0u32;
    GetWindowThreadProcessId(hwnd, &mut pid);
    if pid == GetCurrentProcessId() && IsWindowVisible(hwnd) != 0 && GetWindow(hwnd, GW_OWNER) == 0 {
        FOUND.store(hwnd, Ordering::SeqCst);
        return 0;
    }
    1
}

unsafe extern "system" fn wndproc(hwnd: Hwnd, msg: u32, wparam: usize, lparam: isize) -> isize {
    match msg {
        WM_ACTIVATEAPP if wparam == 0 => return 0,
        WM_ACTIVATE if (wparam & 0xFFFF) == 0 => return 0,
        WM_KILLFOCUS => return 0,
        WM_NCACTIVATE if wparam == 0 => return 1,
        // The engine only reacquires the mouse after a lost/gained pair, so
        // replay the deactivation we swallowed earlier.
        WM_ACTIVATEAPP => {
            let prev = PREV.load(Ordering::SeqCst);
            CallWindowProcW(prev, hwnd, WM_ACTIVATEAPP, 0, lparam);
        }
        WM_ACTIVATE => {
            let prev = PREV.load(Ordering::SeqCst);
            CallWindowProcW(prev, hwnd, WM_ACTIVATE, 0, lparam);
        }
        _ => {}
    }
    CallWindowProcW(PREV.load(Ordering::SeqCst), hwnd, msg, wparam, lparam)
}

#[link(name = "user32")]
extern "system" {
    fn GetForegroundWindow() -> Hwnd;
    #[link_name = "SetCursorPos"]
    fn RealSetCursorPos(x: i32, y: i32) -> i32;
    #[link_name = "ClipCursor"]
    fn RealClipCursor(rect: *const c_void) -> i32;
}

#[link(name = "kernel32")]
extern "system" {
    fn GetModuleHandleW(name: *const u16) -> isize;
    fn VirtualProtect(addr: *mut c_void, size: usize, new: u32, old: *mut u32) -> i32;
}

use std::ffi::c_void;

/// True when this copy's window is the one in front.
fn in_front() -> bool {
    let hwnd = FOUND.load(Ordering::SeqCst);
    hwnd == 0 || unsafe { GetForegroundWindow() } == hwnd
}

// With two "active" copies, only the one in front may recentre the cursor.
unsafe extern "system" fn set_cursor_pos(x: i32, y: i32) -> i32 {
    if in_front() { RealSetCursorPos(x, y) } else { 1 }
}

unsafe extern "system" fn clip_cursor(rect: *const c_void) -> i32 {
    if in_front() { RealClipCursor(rect) } else { 1 }
}

/// Points the game's own imports of these two functions at the ones above.
unsafe fn patch_imports() {
    let base = GetModuleHandleW(std::ptr::null()) as *const u8;
    if base.is_null() {
        return;
    }
    let rd32 = |off: usize| (base.add(off) as *const u32).read_unaligned() as usize;
    let nt = rd32(0x3C);
    // PE32+: optional header at nt+0x18, import directory = data directory 1.
    let imports = rd32(nt + 0x18 + 0x70 + 8);
    if imports == 0 {
        return;
    }
    let mut patched = 0;
    let mut desc = imports;
    loop {
        let names = rd32(desc);
        let thunks = rd32(desc + 16);
        if thunks == 0 {
            break;
        }
        let names = if names != 0 { names } else { thunks };
        let mut i = 0;
        loop {
            let entry = (base.add(names + i * 8) as *const u64).read_unaligned();
            if entry == 0 {
                break;
            }
            if entry & (1u64 << 63) == 0 {
                let name_ptr = base.add(entry as usize + 2);
                let name = std::ffi::CStr::from_ptr(name_ptr as *const i8).to_bytes();
                let target: Option<usize> = match name {
                    b"SetCursorPos" => Some(set_cursor_pos as *const () as usize),
                    b"ClipCursor" => Some(clip_cursor as *const () as usize),
                    _ => None,
                };
                if let Some(target) = target {
                    let slot = base.add(thunks + i * 8) as *mut usize;
                    let mut old = 0u32;
                    if VirtualProtect(slot as *mut c_void, 8, 0x04, &mut old) != 0 {
                        slot.write_unaligned(target);
                        VirtualProtect(slot as *mut c_void, 8, old, &mut old);
                        patched += 1;
                    }
                }
            }
            i += 1;
        }
        desc += 20;
    }
    log::line(&format!("background mode: mouse calls patched ({patched})"));
}

/// Waits for the game window to exist, then subclasses it.
pub fn keep_running() {
    let _ = std::thread::Builder::new().name("crowdtale-background".into()).spawn(|| {
        for _ in 0..240 {
            std::thread::sleep(std::time::Duration::from_millis(500));
            FOUND.store(0, Ordering::SeqCst);
            unsafe { EnumWindows(find, 0) };
            let hwnd = FOUND.load(Ordering::SeqCst);
            if hwnd != 0 {
                // Store the old proc first so the new one always has a target.
                let prev = unsafe { GetWindowLongPtrW(hwnd, GWLP_WNDPROC) };
                if prev == 0 {
                    continue;
                }
                PREV.store(prev, Ordering::SeqCst);
                unsafe { SetWindowLongPtrW(hwnd, GWLP_WNDPROC, wndproc as WndProc as isize) };
                log::line("background mode: game keeps running when not in front (local test)");
                unsafe { patch_imports() };
                return;
            }
        }
        log::line("background mode: game window not found");
    });
}
