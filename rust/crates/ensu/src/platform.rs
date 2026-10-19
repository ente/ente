#[cfg(all(unix, not(target_os = "android")))]
#[expect(
    unsafe_code,
    reason = "sysconf reads process-independent constants without caller-owned pointers"
)]
pub(crate) fn total_memory_bytes() -> Option<u64> {
    let pages = unsafe { libc::sysconf(libc::_SC_PHYS_PAGES) };
    let page_size = unsafe { libc::sysconf(libc::_SC_PAGESIZE) };
    if pages <= 0 || page_size <= 0 {
        return None;
    }
    u64::try_from(pages)
        .ok()?
        .checked_mul(u64::try_from(page_size).ok()?)
}

#[cfg(windows)]
#[expect(
    unsafe_code,
    reason = "GlobalMemoryStatusEx receives an initialized, correctly sized struct borrowed for this call"
)]
pub(crate) fn total_memory_bytes() -> Option<u64> {
    use windows_sys::Win32::System::SystemInformation::{GlobalMemoryStatusEx, MEMORYSTATUSEX};

    let mut status = MEMORYSTATUSEX {
        dwLength: std::mem::size_of::<MEMORYSTATUSEX>() as u32,
        ..Default::default()
    };
    let ok = unsafe { GlobalMemoryStatusEx(&mut status) };
    (ok != 0 && status.ullTotalPhys > 0).then_some(status.ullTotalPhys)
}

#[cfg(not(any(unix, windows)))]
pub(crate) fn total_memory_bytes() -> Option<u64> {
    None
}

#[cfg(windows)]
#[expect(
    unsafe_code,
    reason = "The File keeps its handle live; the size query has no output buffer and the fill receives the initialized buffer's exact capacity"
)]
pub(crate) fn final_handle_path(file: &std::fs::File) -> std::io::Result<std::path::PathBuf> {
    use std::ffi::OsString;
    use std::io;
    use std::os::windows::ffi::OsStringExt;
    use std::os::windows::io::AsRawHandle;
    use std::path::PathBuf;
    use windows_sys::Win32::Storage::FileSystem::{
        FILE_NAME_NORMALIZED, GetFinalPathNameByHandleW, VOLUME_NAME_DOS,
    };

    let handle = file.as_raw_handle();
    let flags = FILE_NAME_NORMALIZED | VOLUME_NAME_DOS;
    let length = unsafe { GetFinalPathNameByHandleW(handle, std::ptr::null_mut(), 0, flags) };
    if length == 0 {
        return Err(io::Error::last_os_error());
    }
    let mut buffer = vec![0_u16; length as usize];
    let written = unsafe { GetFinalPathNameByHandleW(handle, buffer.as_mut_ptr(), length, flags) };
    if written == 0 {
        return Err(io::Error::last_os_error());
    }
    if written >= length {
        return Err(io::Error::other("Source path changed while being resolved"));
    }
    Ok(PathBuf::from(OsString::from_wide(
        &buffer[..written as usize],
    )))
}

#[cfg(target_os = "android")]
#[expect(
    unsafe_code,
    reason = "The optional libc mallopt symbol is called with its C signature while its library handle is live; M_PURGE releases only unused allocations"
)]
pub(crate) fn release_unused_memory() {
    use std::ffi::{c_char, c_int, c_void};

    #[link(name = "dl")]
    unsafe extern "C" {
        fn dlopen(filename: *const c_char, flags: c_int) -> *mut c_void;
        fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
        fn dlclose(handle: *mut c_void) -> c_int;
    }

    #[cfg(target_pointer_width = "64")]
    const RTLD_NOW: c_int = 2;
    #[cfg(target_pointer_width = "32")]
    const RTLD_NOW: c_int = 0;
    const M_PURGE: c_int = -101;

    let handle = unsafe { dlopen(c"libc.so".as_ptr(), RTLD_NOW) };
    if handle.is_null() {
        return;
    }
    let symbol = unsafe { dlsym(handle, c"mallopt".as_ptr()) };
    if !symbol.is_null() {
        let mallopt = unsafe {
            std::mem::transmute::<*mut c_void, unsafe extern "C" fn(c_int, c_int) -> c_int>(symbol)
        };
        unsafe { mallopt(M_PURGE, 0) };
    }
    unsafe { dlclose(handle) };
}
