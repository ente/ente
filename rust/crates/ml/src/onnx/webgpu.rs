// Arm the durable canary before touching the driver and disarm it only after
// session construction and warm-up. Three recorded failures quarantine the
// model directory across restarts. The caller's model-slot lock serializes
// access.

#[cfg(all(
    not(target_os = "windows"),
    any(target_os = "android", target_os = "linux", test)
))]
use std::fs::File;
#[cfg(target_os = "android")]
use std::sync::OnceLock;
#[cfg(any(target_os = "android", target_os = "linux", target_os = "windows"))]
use std::sync::atomic::{AtomicBool, Ordering};
#[cfg(any(
    target_os = "android",
    target_os = "linux",
    target_os = "windows",
    test
))]
use std::{
    fs::{self, OpenOptions},
    io::{self, Write},
    path::{Path, PathBuf},
};

// Bump to retry quarantined devices after major ONNX Runtime or Dawn changes.
#[cfg(any(
    target_os = "android",
    target_os = "linux",
    target_os = "windows",
    test
))]
const CANARY_FILE_PREFIX: &str = ".ente-webgpu-canary-v1.";

#[cfg(any(
    target_os = "android",
    target_os = "linux",
    target_os = "windows",
    test
))]
const MAX_CONSECUTIVE_FAILURES: u32 = 3;

#[cfg(any(target_os = "android", target_os = "linux", target_os = "windows"))]
static WEBGPU_ENABLED: AtomicBool = AtomicBool::new(false);

pub(super) fn set_enabled(enabled: bool) {
    #[cfg(any(target_os = "android", target_os = "linux", target_os = "windows"))]
    WEBGPU_ENABLED.store(enabled, Ordering::Relaxed);
    #[cfg(not(any(target_os = "android", target_os = "linux", target_os = "windows")))]
    let _ = enabled;
}

// Adapter probing touches Vulkan and therefore happens after arming, not here.
#[cfg(any(target_os = "android", target_os = "linux", target_os = "windows"))]
pub(super) fn attempt_permitted(model_path: &str) -> bool {
    WEBGPU_ENABLED.load(Ordering::Relaxed)
        && model_dir(model_path).is_some_and(|dir| !quarantined(&dir))
}

// Mirrors Chromium's `gpu/config/webgpu_blocklist_impl.cc` Android 12+ policy
// as of 2026-07; revisit with pinned ONNX Runtime or Dawn upgrades.
#[cfg(any(target_os = "android", test))]
const ALLOWLISTED_VULKAN_VENDOR_IDS: [u32; 3] = [
    0x13B5, // ARM (Mali, Immortalis)
    0x5143, // Qualcomm (Adreno)
    0x8086, // Intel
];

// Dawn chooses independently, so every enumerated adapter must be allowlisted.
#[cfg(any(target_os = "android", test))]
fn vendors_allowlisted(vendor_ids: &[u32]) -> bool {
    !vendor_ids.is_empty()
        && vendor_ids
            .iter()
            .all(|vendor_id| ALLOWLISTED_VULKAN_VENDOR_IDS.contains(vendor_id))
}

#[cfg(target_os = "android")]
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub(super) enum AdapterCheck {
    Allowed,
    Denied,
    // Probe failures count toward quarantine; policy denials do not.
    Failed,
}

// Must run inside an armed canary because this is the first Vulkan driver
// access.
#[cfg(target_os = "android")]
pub(super) fn check_adapter() -> AdapterCheck {
    static VERDICT: OnceLock<AdapterCheck> = OnceLock::new();
    *VERDICT.get_or_init(|| match probe_vulkan_vendor_ids() {
        Ok(vendor_ids) => {
            let allowed = vendors_allowlisted(&vendor_ids);
            log::info!(
                "Vulkan adapter vendor IDs {vendor_ids:#06x?}; WebGPU allowlisted: {allowed}"
            );
            if allowed {
                AdapterCheck::Allowed
            } else {
                AdapterCheck::Denied
            }
        }
        Err(error) => {
            log::warn!("Vulkan adapter probe failed: {error}");
            AdapterCheck::Failed
        }
    })
}

#[cfg(target_os = "android")]
fn probe_vulkan_vendor_ids() -> Result<Vec<u32>, String> {
    use ash::vk;

    // SAFETY: loads Android's system Vulkan loader and keeps it alive through
    // instance destruction.
    let entry = unsafe { ash::Entry::load() }
        .map_err(|error| format!("loading Vulkan loader failed: {error}"))?;
    // SAFETY: the default Vulkan 1.0 instance description is valid.
    let instance = unsafe { entry.create_instance(&vk::InstanceCreateInfo::default(), None) }
        .map_err(|error| format!("creating Vulkan instance failed: {error}"))?;
    // SAFETY: `instance` is live and is destroyed below before returning.
    let vendor_ids = unsafe { instance.enumerate_physical_devices() }
        .map(|devices| {
            devices
                .iter()
                // SAFETY: each handle was just enumerated from `instance`.
                .map(|&device| unsafe { instance.get_physical_device_properties(device) }.vendor_id)
                .collect::<Vec<u32>>()
        })
        .map_err(|error| format!("enumerating Vulkan devices failed: {error}"));
    // SAFETY: created above, no child objects outlive it.
    unsafe { instance.destroy_instance(None) };
    vendor_ids
}

// Dropping without disarming intentionally preserves the failed-attempt record.
#[cfg(any(
    target_os = "android",
    target_os = "linux",
    target_os = "windows",
    test
))]
pub(super) struct ArmedCanary {
    path: PathBuf,
}

#[cfg(any(
    target_os = "android",
    target_os = "linux",
    target_os = "windows",
    test
))]
pub(super) fn arm_canary(model_path: &str, model_namespace: &str) -> io::Result<ArmedCanary> {
    let dir = model_dir(model_path).ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "cannot derive WebGPU canary directory from model path",
        )
    })?;
    let path = dir.join(format!("{CANARY_FILE_PREFIX}{model_namespace}"));
    let failures = read_failure_count(&path)?;
    persist_failure_count(&path, failures.saturating_add(1))?;
    Ok(ArmedCanary { path })
}

#[cfg(any(
    target_os = "android",
    target_os = "linux",
    target_os = "windows",
    test
))]
impl ArmedCanary {
    pub(super) fn disarm(self) {
        if let Err(error) = remove_file_durably(&self.path) {
            log::warn!(
                "failed to disarm WebGPU crash canary at '{}': {error}",
                self.path.display()
            );
        }
    }
}

#[cfg(any(
    target_os = "android",
    target_os = "linux",
    target_os = "windows",
    test
))]
fn model_dir(model_path: &str) -> Option<PathBuf> {
    if model_path.trim().is_empty() {
        return None;
    }
    Path::new(model_path)
        .parent()
        .filter(|dir| !dir.as_os_str().is_empty())
        .map(Path::to_path_buf)
}

#[cfg(any(
    target_os = "android",
    target_os = "linux",
    target_os = "windows",
    test
))]
fn quarantined(dir: &Path) -> bool {
    let entries = match fs::read_dir(dir) {
        Ok(entries) => entries,
        Err(_) => return true,
    };
    for entry in entries {
        let Ok(entry) = entry else {
            return true;
        };
        let file_name = entry.file_name();
        let Some(name) = file_name.to_str() else {
            continue;
        };
        if !name.starts_with(CANARY_FILE_PREFIX) {
            continue;
        }
        match read_failure_count(&entry.path()) {
            Ok(failures) if failures < MAX_CONSECUTIVE_FAILURES => {}
            _ => return true,
        }
    }
    false
}

#[cfg(any(
    target_os = "android",
    target_os = "linux",
    target_os = "windows",
    test
))]
fn read_failure_count(path: &Path) -> io::Result<u32> {
    let contents = match fs::read_to_string(path) {
        Ok(contents) => contents,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(0),
        Err(error) => return Err(error),
    };
    contents.trim().parse::<u32>().map_err(|_| {
        io::Error::new(
            io::ErrorKind::InvalidData,
            format!("invalid WebGPU canary contents at '{}'", path.display()),
        )
    })
}

#[cfg(any(
    target_os = "android",
    target_os = "linux",
    target_os = "windows",
    test
))]
fn persist_failure_count(path: &Path, failures: u32) -> io::Result<()> {
    let mut file = OpenOptions::new()
        .create(true)
        .truncate(true)
        .write(true)
        .open(path)?;
    file.write_all(format!("{failures}\n").as_bytes())?;
    file.sync_all()?;
    sync_parent(path)
}

#[cfg(any(
    target_os = "android",
    target_os = "linux",
    target_os = "windows",
    test
))]
fn remove_file_durably(path: &Path) -> io::Result<()> {
    match fs::remove_file(path) {
        Ok(()) => sync_parent(path),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
    }
}

#[cfg(any(
    target_os = "android",
    target_os = "linux",
    target_os = "windows",
    test
))]
fn sync_parent(path: &Path) -> io::Result<()> {
    let parent = path.parent().ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "WebGPU canary path has no parent directory",
        )
    })?;
    // std cannot fsync directories on Windows.
    #[cfg(not(target_os = "windows"))]
    return File::open(parent)?.sync_all();
    #[cfg(target_os = "windows")]
    {
        let _ = parent;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::{MAX_CONSECUTIVE_FAILURES, arm_canary, quarantined, vendors_allowlisted};

    #[test]
    fn allowlists_the_vendors_chromium_ships_webgpu_to_on_android_12() {
        assert!(vendors_allowlisted(&[0x13B5]), "ARM");
        assert!(vendors_allowlisted(&[0x5143]), "Qualcomm");
        assert!(vendors_allowlisted(&[0x8086]), "Intel");
    }

    #[test]
    fn denies_vendors_chromium_does_not_ship_webgpu_to_on_android_12() {
        assert!(!vendors_allowlisted(&[0x1010]), "Imagination/PowerVR");
        assert!(!vendors_allowlisted(&[0x144D]), "Samsung Xclipse");
        assert!(!vendors_allowlisted(&[0x10DE]), "NVIDIA");
        assert!(!vendors_allowlisted(&[0x1AE0]), "Google SwiftShader");
        assert!(!vendors_allowlisted(&[0x10005]), "Mesa llvmpipe");
        assert!(!vendors_allowlisted(&[0]));
    }

    #[test]
    fn denies_when_any_adapter_is_not_allowlisted() {
        assert!(!vendors_allowlisted(&[0x5143, 0x1AE0]));
        assert!(!vendors_allowlisted(&[0x1010, 0x13B5]));
    }

    #[test]
    fn allows_when_every_adapter_is_allowlisted() {
        assert!(vendors_allowlisted(&[0x13B5, 0x8086]));
    }

    #[test]
    fn denies_when_no_adapters_are_enumerated() {
        assert!(!vendors_allowlisted(&[]));
    }

    fn model_path(dir: &std::path::Path) -> String {
        dir.join("model.onnx").to_string_lossy().into_owned()
    }

    #[test]
    fn single_interrupted_attempt_does_not_quarantine() {
        let dir = tempfile::tempdir().unwrap();
        let model = model_path(dir.path());

        drop(arm_canary(&model, "clip-image").unwrap());

        assert!(!quarantined(dir.path()));
    }

    #[test]
    fn consecutive_interrupted_attempts_quarantine() {
        let dir = tempfile::tempdir().unwrap();
        let model = model_path(dir.path());

        for attempt in 1..=MAX_CONSECUTIVE_FAILURES {
            assert!(
                !quarantined(dir.path()),
                "quarantined before attempt {attempt}"
            );
            drop(arm_canary(&model, "clip-image").unwrap());
        }

        assert!(quarantined(dir.path()));
    }

    #[test]
    fn successful_attempt_resets_consecutive_failures() {
        let dir = tempfile::tempdir().unwrap();
        let model = model_path(dir.path());

        drop(arm_canary(&model, "clip-image").unwrap());
        drop(arm_canary(&model, "clip-image").unwrap());
        arm_canary(&model, "clip-image").unwrap().disarm();

        assert!(!quarantined(dir.path()));
        drop(arm_canary(&model, "clip-image").unwrap());
        assert!(!quarantined(dir.path()));
    }

    #[test]
    fn failures_do_not_accumulate_across_models() {
        let dir = tempfile::tempdir().unwrap();
        let model = model_path(dir.path());

        drop(arm_canary(&model, "clip-image").unwrap());
        drop(arm_canary(&model, "face-detection").unwrap());
        drop(arm_canary(&model, "face-embedding").unwrap());

        assert!(!quarantined(dir.path()));
    }

    #[test]
    fn one_tripped_model_quarantines_the_whole_directory() {
        let dir = tempfile::tempdir().unwrap();
        let model = model_path(dir.path());

        for _ in 0..MAX_CONSECUTIVE_FAILURES {
            drop(arm_canary(&model, "clip-image").unwrap());
        }
        arm_canary(&model, "face-detection").unwrap().disarm();

        assert!(quarantined(dir.path()));
    }

    #[test]
    fn unreadable_canary_state_fails_closed() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(
            dir.path()
                .join(format!("{}clip-image", super::CANARY_FILE_PREFIX)),
            b"not a number",
        )
        .unwrap();

        assert!(quarantined(dir.path()));
    }
}
