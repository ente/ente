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
fn windows_memory_status() -> Option<windows_sys::Win32::System::SystemInformation::MEMORYSTATUSEX>
{
    use windows_sys::Win32::System::SystemInformation::{GlobalMemoryStatusEx, MEMORYSTATUSEX};

    let mut status = MEMORYSTATUSEX {
        dwLength: std::mem::size_of::<MEMORYSTATUSEX>() as u32,
        ..Default::default()
    };
    let ok = unsafe { GlobalMemoryStatusEx(&mut status) };
    (ok != 0).then_some(status)
}

#[cfg(windows)]
pub(crate) fn total_memory_bytes() -> Option<u64> {
    windows_memory_status()
        .and_then(|status| (status.ullTotalPhys > 0).then_some(status.ullTotalPhys))
}

#[cfg(not(any(unix, windows)))]
pub(crate) fn total_memory_bytes() -> Option<u64> {
    None
}

#[cfg(not(target_os = "android"))]
#[derive(Default)]
pub(crate) struct Memory {
    pub(crate) available: Option<u64>,
    pub(crate) pressure: bool,
}

#[cfg(target_os = "macos")]
#[expect(
    unsafe_code,
    reason = "Read-only Mach and sysctl queries receive initialized, correctly sized output buffers; the host send right is released"
)]
pub(crate) fn memory() -> Memory {
    unsafe extern "C" {
        fn mach_host_self() -> libc::mach_port_t;
        static mach_task_self_: libc::mach_port_t;
        fn mach_port_deallocate(
            task: libc::mach_port_t,
            name: libc::mach_port_t,
        ) -> libc::kern_return_t;
    }
    let mut statistics: libc::vm_statistics64 = unsafe { std::mem::zeroed() };
    let mut count = libc::HOST_VM_INFO64_COUNT;
    let host = unsafe { mach_host_self() };
    let result = unsafe {
        libc::host_statistics64(
            host,
            libc::HOST_VM_INFO64,
            (&mut statistics as *mut libc::vm_statistics64).cast(),
            &mut count,
        )
    };
    unsafe {
        mach_port_deallocate(mach_task_self_, host);
    }
    let page_size = unsafe { libc::sysconf(libc::_SC_PAGESIZE) };
    let available = (result == libc::KERN_SUCCESS && page_size > 0).then(|| {
        (u64::from(statistics.free_count) + u64::from(statistics.inactive_count)) * page_size as u64
    });
    let mut level = 0_u32;
    let mut size = std::mem::size_of_val(&level);
    let result = unsafe {
        libc::sysctlbyname(
            c"kern.memorystatus_vm_pressure_level".as_ptr(),
            (&mut level as *mut u32).cast(),
            &mut size,
            std::ptr::null_mut(),
            0,
        )
    };
    Memory {
        available,
        pressure: result == 0 && level & 6 != 0,
    }
}

#[cfg(target_os = "linux")]
pub(crate) fn memory() -> Memory {
    let available = std::fs::read_to_string("/proc/meminfo")
        .ok()
        .and_then(|text| {
            text.lines().find_map(|line| {
                line.strip_prefix("MemAvailable:")?
                    .split_whitespace()
                    .next()?
                    .parse::<u64>()
                    .ok()?
                    .checked_mul(1024)
            })
        });
    Memory {
        available,
        pressure: false,
    }
}

#[cfg(windows)]
pub(crate) fn memory() -> Memory {
    let Some(status) = windows_memory_status() else {
        return Memory::default();
    };
    Memory {
        available: Some(status.ullAvailPhys),
        pressure: status.dwMemoryLoad >= 90,
    }
}

#[cfg(not(any(
    target_os = "macos",
    target_os = "linux",
    target_os = "android",
    windows
)))]
pub(crate) fn memory() -> Memory {
    Memory::default()
}

#[cfg(target_os = "macos")]
#[expect(
    unsafe_code,
    reason = "The read-only sysctl receives a fixed, initialized output buffer and its exact capacity"
)]
pub(crate) fn macos_version() -> Option<(u32, u32)> {
    let mut version = [0_u8; 64];
    let mut size = version.len();
    let result = unsafe {
        libc::sysctlbyname(
            c"kern.osproductversion".as_ptr(),
            version.as_mut_ptr().cast(),
            &mut size,
            std::ptr::null_mut(),
            0,
        )
    };
    if result != 0 {
        return None;
    }
    let version = String::from_utf8_lossy(&version);
    let mut parts = version.trim_end_matches('\0').split('.');
    Some((parts.next()?.parse().ok()?, parts.next()?.parse().ok()?))
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
