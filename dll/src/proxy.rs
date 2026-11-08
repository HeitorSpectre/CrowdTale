//! Forwards every dinput8 export to the system DLL (loaded lazily, by full path).

use std::ffi::c_void;
use std::sync::OnceLock;

#[link(name = "kernel32")]
extern "system" {
    pub fn DisableThreadLibraryCalls(module: isize) -> i32;
    pub fn GetModuleHandleW(name: *const u16) -> isize;
    pub fn GetProcAddress(module: isize, name: *const u8) -> *const c_void;
    pub fn LoadLibraryW(name: *const u16) -> isize;
    pub fn GetSystemDirectoryW(buffer: *mut u16, size: u32) -> u32;
    pub fn GetModuleFileNameW(module: isize, buffer: *mut u16, size: u32) -> u32;
    pub fn GetCommandLineW() -> *const u16;
}

pub fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

fn real_dinput8() -> isize {
    static REAL: OnceLock<isize> = OnceLock::new();
    *REAL.get_or_init(|| unsafe {
        let mut buf = [0u16; 520];
        let n = GetSystemDirectoryW(buf.as_mut_ptr(), buf.len() as u32) as usize;
        if n == 0 || n >= buf.len() {
            return 0;
        }
        let mut path: Vec<u16> = buf[..n].to_vec();
        path.extend("\\dinput8.dll".encode_utf16());
        path.push(0);
        LoadLibraryW(path.as_ptr())
    })
}

fn real(name: &[u8]) -> *const c_void {
    let module = real_dinput8();
    if module == 0 {
        return std::ptr::null();
    }
    unsafe { GetProcAddress(module, name.as_ptr()) }
}

const E_FAIL: i32 = 0x8000_4005u32 as i32;

#[allow(non_snake_case)]
#[no_mangle]
pub extern "system" fn DirectInput8Create(
    hinst: isize,
    version: u32,
    riid: *const c_void,
    out: *mut *mut c_void,
    outer: *mut c_void,
) -> i32 {
    type F = extern "system" fn(isize, u32, *const c_void, *mut *mut c_void, *mut c_void) -> i32;
    let f = real(b"DirectInput8Create\0");
    if f.is_null() {
        return E_FAIL;
    }
    let f: F = unsafe { std::mem::transmute(f) };
    f(hinst, version, riid, out, outer)
}

#[allow(non_snake_case)]
#[no_mangle]
pub extern "system" fn DllCanUnloadNow() -> i32 {
    type F = extern "system" fn() -> i32;
    let f = real(b"DllCanUnloadNow\0");
    if f.is_null() {
        return 1; // S_FALSE
    }
    let f: F = unsafe { std::mem::transmute(f) };
    f()
}

#[allow(non_snake_case)]
#[no_mangle]
pub extern "system" fn DllGetClassObject(clsid: *const c_void, riid: *const c_void, out: *mut *mut c_void) -> i32 {
    type F = extern "system" fn(*const c_void, *const c_void, *mut *mut c_void) -> i32;
    let f = real(b"DllGetClassObject\0");
    if f.is_null() {
        return E_FAIL;
    }
    let f: F = unsafe { std::mem::transmute(f) };
    f(clsid, riid, out)
}

#[allow(non_snake_case)]
#[no_mangle]
pub extern "system" fn DllRegisterServer() -> i32 {
    type F = extern "system" fn() -> i32;
    let f = real(b"DllRegisterServer\0");
    if f.is_null() {
        return E_FAIL;
    }
    let f: F = unsafe { std::mem::transmute(f) };
    f()
}

#[allow(non_snake_case)]
#[no_mangle]
pub extern "system" fn DllUnregisterServer() -> i32 {
    type F = extern "system" fn() -> i32;
    let f = real(b"DllUnregisterServer\0");
    if f.is_null() {
        return E_FAIL;
    }
    let f: F = unsafe { std::mem::transmute(f) };
    f()
}

#[allow(non_snake_case)]
#[no_mangle]
pub extern "system" fn GetdfDIJoystick() -> *const c_void {
    type F = extern "system" fn() -> *const c_void;
    let f = real(b"GetdfDIJoystick\0");
    if f.is_null() {
        return std::ptr::null();
    }
    let f: F = unsafe { std::mem::transmute(f) };
    f()
}
