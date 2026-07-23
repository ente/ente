use serde::Serialize;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SystemInfo {
    platform: String,
    total_memory_bytes: Option<u64>,
}

#[cfg(unix)]
fn total_memory_bytes() -> Option<u64> {
    let pages = unsafe { libc::sysconf(libc::_SC_PHYS_PAGES) };
    let page_size = unsafe { libc::sysconf(libc::_SC_PAGESIZE) };
    if pages <= 0 || page_size <= 0 {
        return None;
    }

    u64::try_from(pages)
        .ok()?
        .checked_mul(u64::try_from(page_size).ok()?)
}

#[cfg(target_os = "windows")]
fn total_memory_bytes() -> Option<u64> {
    use windows_sys::Win32::System::SystemInformation::{GlobalMemoryStatusEx, MEMORYSTATUSEX};

    let mut status = MEMORYSTATUSEX {
        dwLength: std::mem::size_of::<MEMORYSTATUSEX>() as u32,
        ..Default::default()
    };

    let ok = unsafe { GlobalMemoryStatusEx(&mut status) };
    if ok == 0 {
        None
    } else {
        Some(status.ullTotalPhys)
    }
}

#[cfg(not(any(unix, target_os = "windows")))]
fn total_memory_bytes() -> Option<u64> {
    None
}

#[tauri::command]
pub fn system_info() -> SystemInfo {
    SystemInfo {
        platform: std::env::consts::OS.to_string(),
        total_memory_bytes: total_memory_bytes(),
    }
}
