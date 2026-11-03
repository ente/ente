#[derive(Default)]
pub(super) struct Memory {
    pub(super) available: Option<u64>,
    pub(super) pressure: bool,
}

#[cfg(target_os = "macos")]
#[expect(
    unsafe_code,
    reason = "Read-only Mach and sysctl queries receive initialized, correctly sized output buffers; the host send right is released"
)]
pub(super) fn memory() -> Memory {
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
pub(super) fn memory() -> Memory {
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
#[expect(
    unsafe_code,
    reason = "GlobalMemoryStatusEx receives an initialized, correctly sized output struct"
)]
pub(super) fn memory() -> Memory {
    use windows_sys::Win32::System::SystemInformation::{GlobalMemoryStatusEx, MEMORYSTATUSEX};
    let mut status = MEMORYSTATUSEX {
        dwLength: std::mem::size_of::<MEMORYSTATUSEX>() as u32,
        ..Default::default()
    };
    let ok = unsafe { GlobalMemoryStatusEx(&mut status) };
    Memory {
        available: (ok != 0).then_some(status.ullAvailPhys),
        pressure: ok != 0 && status.dwMemoryLoad >= 90,
    }
}

#[cfg(not(any(target_os = "macos", target_os = "linux", windows)))]
pub(super) fn memory() -> Memory {
    Memory::default()
}

#[cfg(target_os = "macos")]
#[expect(
    unsafe_code,
    reason = "The read-only sysctl receives a fixed, initialized output buffer and its exact capacity"
)]
pub(super) fn macos_version() -> Option<(u32, u32)> {
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
