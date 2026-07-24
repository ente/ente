//! Device-side guards for the Android WebGPU execution provider: a durable
//! crash canary and a GPU adapter allowlist.
//!
//! The canary prevents an infinite crash loop on the rare device where
//! Dawn/Vulkan hard-crashes the process while a WebGPU session is built or
//! first dispatched. The allowlist only permits WebGPU on GPU vendors that
//! Chromium ships WebGPU to on Android, so Ente never runs Dawn on driver
//! stacks that Google's far larger fleet has not validated.
//!
//! Mechanics: immediately before a WebGPU session is built, a per-model
//! counter file next to the model is incremented and fsynced ("armed"). After
//! the session has been built *and* has survived one warm-up inference, the
//! file is removed ("disarmed"). A crash, kill, or soft failure in between
//! leaves the incremented counter behind. Once any model's counter reaches
//! [`MAX_CONSECUTIVE_FAILURES`], WebGPU is no longer attempted for models in
//! that directory — durably, across process restarts.
//!
//! A single interrupted attempt (e.g. Android killing the app mid-indexing)
//! is therefore tolerated: only consecutive failures with no intervening
//! success trip the breaker, which a genuine crash loop does deterministically
//! within a few launches.
//!
//! Everything here is called from `onnx::build_session` while the caller
//! holds the per-model slot lock, so accesses to one model's counter file are
//! already serialized and no in-memory state is needed beyond the enable flag.

#[cfg(target_os = "android")]
use std::sync::{
    OnceLock,
    atomic::{AtomicBool, Ordering},
};
#[cfg(any(target_os = "android", test))]
use std::{
    fs::{self, File, OpenOptions},
    io::{self, Write},
    path::{Path, PathBuf},
};

/// Bump the version to discard all previous canary state, e.g. after a major
/// ONNX Runtime or Dawn upgrade that warrants re-trialing quarantined devices.
#[cfg(any(target_os = "android", test))]
const CANARY_FILE_PREFIX: &str = ".ente-webgpu-canary-v1.";

/// Number of consecutive failed or interrupted WebGPU attempts for one model
/// after which WebGPU is durably disabled.
#[cfg(any(target_os = "android", test))]
const MAX_CONSECUTIVE_FAILURES: u32 = 3;

/// WebGPU is opt-in while the custom Android ONNX Runtime build is being
/// validated; the app-side policy also gates on device eligibility.
#[cfg(target_os = "android")]
static WEBGPU_ENABLED: AtomicBool = AtomicBool::new(false);

pub(crate) fn set_enabled(enabled: bool) {
    #[cfg(target_os = "android")]
    WEBGPU_ENABLED.store(enabled, Ordering::Relaxed);
    #[cfg(not(target_os = "android"))]
    let _ = enabled;
}

/// Whether a WebGPU session may be attempted for this model. False when the
/// app has not opted in, or when any model in the same directory has tripped
/// the crash canary. Fails closed on IO errors.
///
/// The GPU adapter allowlist is deliberately not checked here: probing the
/// adapter touches the Vulkan driver, so it must run inside the armed canary
/// window (see `onnx::build_webgpu_session_with_canary`), where a probe crash
/// is recorded like any other WebGPU crash.
#[cfg(target_os = "android")]
pub(crate) fn attempt_permitted(model_path: &str) -> bool {
    WEBGPU_ENABLED.load(Ordering::Relaxed)
        && model_dir(model_path).is_some_and(|dir| !quarantined(&dir))
}

/// Vulkan vendor IDs of GPUs for which Chromium ships WebGPU on Android 12+,
/// mirroring `gpu/config/webgpu_blocklist_impl.cc` (Chromium main, 2026-07).
/// Notably absent, matching Chromium: Imagination/PowerVR (allowed there only
/// on Android 16+), Samsung Xclipse (still work-in-progress), and everything
/// else. Revisit whenever the pinned ONNX Runtime/Dawn build is bumped.
#[cfg(any(target_os = "android", test))]
const ALLOWLISTED_VULKAN_VENDOR_IDS: [u32; 3] = [
    0x13B5, // ARM (Mali, Immortalis)
    0x5143, // Qualcomm (Adreno)
    0x8086, // Intel
];

/// WebGPU requires every enumerated adapter to be allowlisted: Dawn selects
/// its adapter independently of this probe, so a mixed set could otherwise
/// let Dawn pick a denied adapter. Android's Vulkan loader exposes a single
/// vendor driver in practice, so on real devices this is a single-adapter
/// check. An empty list fails closed.
#[cfg(any(target_os = "android", test))]
fn vendors_allowlisted(vendor_ids: &[u32]) -> bool {
    !vendor_ids.is_empty()
        && vendor_ids
            .iter()
            .all(|vendor_id| ALLOWLISTED_VULKAN_VENDOR_IDS.contains(vendor_id))
}

/// Outcome of the Vulkan adapter allowlist check. `Denied` means the probe
/// completed and the adapter is not allowlisted — a clean policy decision.
/// `Failed` means the probe itself did not complete, which callers must treat
/// as a failed WebGPU attempt (counted by the crash canary) rather than a
/// policy decision: a driver that cannot even create a Vulkan instance must
/// eventually quarantine instead of being re-probed on every launch.
#[cfg(target_os = "android")]
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub(crate) enum AdapterCheck {
    Allowed,
    Denied,
    Failed,
}

/// Checks the device's Vulkan adapters against the Chromium Android WebGPU
/// allowlist. Probes once per process. Keeping this inside the Rust
/// eligibility path ensures an unsupported adapter cannot be bypassed by any
/// Dart inference entry point.
///
/// Must only be called inside an armed canary window: the probe is the first
/// code in the process to touch the Vulkan driver.
#[cfg(target_os = "android")]
pub(crate) fn check_adapter() -> AdapterCheck {
    static VERDICT: OnceLock<AdapterCheck> = OnceLock::new();
    *VERDICT.get_or_init(|| match probe_vulkan_vendor_ids() {
        Ok(vendor_ids) => {
            let allowed = vendors_allowlisted(&vendor_ids);
            crate::ml::runtime::rt_log(&format!(
                "Vulkan adapter vendor IDs {vendor_ids:#06x?}; WebGPU allowlisted: {allowed}"
            ));
            if allowed {
                AdapterCheck::Allowed
            } else {
                AdapterCheck::Denied
            }
        }
        Err(error) => {
            crate::ml::runtime::rt_log(&format!("Vulkan adapter probe failed: {error}"));
            AdapterCheck::Failed
        }
    })
}

/// Enumerates the vendor IDs of all Vulkan physical devices via the system
/// Vulkan loader. Any failure (no loader, no driver, no devices) is an error
/// so that the caller fails closed.
#[cfg(target_os = "android")]
fn probe_vulkan_vendor_ids() -> Result<Vec<u32>, String> {
    use ash::vk;

    // SAFETY: loads the system Vulkan loader (`libvulkan.so`, present on all
    // Android 7+ devices); `entry` keeps the library loaded until it drops at
    // the end of this function, after the instance has been destroyed.
    let entry = unsafe { ash::Entry::load() }
        .map_err(|error| format!("loading Vulkan loader failed: {error}"))?;
    // SAFETY: a default `InstanceCreateInfo` (Vulkan 1.0, no layers or
    // extensions) is a valid instance description.
    let instance = unsafe { entry.create_instance(&vk::InstanceCreateInfo::default(), None) }
        .map_err(|error| format!("creating Vulkan instance failed: {error}"))?;
    // SAFETY: `instance` is a live instance; it is destroyed below on every
    // path and not used afterwards.
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

/// A durable record of an in-flight WebGPU attempt for one model. Dropping it
/// without calling [`ArmedCanary::disarm`] leaves the attempt recorded as
/// failed, which is exactly what a crash does implicitly.
#[cfg(any(target_os = "android", test))]
pub(crate) struct ArmedCanary {
    path: PathBuf,
}

/// Increments and fsyncs the model's consecutive-failure counter before a
/// WebGPU attempt. On error the caller must skip WebGPU (fail closed): without
/// a durable record, a crash during the attempt would go unnoticed.
#[cfg(any(target_os = "android", test))]
pub(crate) fn arm_canary(model_path: &str, model_namespace: &str) -> io::Result<ArmedCanary> {
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

#[cfg(any(target_os = "android", test))]
impl ArmedCanary {
    /// Marks the attempt as successful by removing the counter file, resetting
    /// the model's consecutive-failure count to zero.
    pub(crate) fn disarm(self) {
        if let Err(error) = remove_file_durably(&self.path) {
            crate::ml::runtime::rt_log(&format!(
                "failed to disarm WebGPU crash canary at '{}': {error}",
                self.path.display()
            ));
        }
    }
}

#[cfg(any(target_os = "android", test))]
fn model_dir(model_path: &str) -> Option<PathBuf> {
    if model_path.trim().is_empty() {
        return None;
    }
    Path::new(model_path)
        .parent()
        .filter(|dir| !dir.as_os_str().is_empty())
        .map(Path::to_path_buf)
}

/// True if any model's canary in this directory records too many consecutive
/// failures. Unreadable state fails closed.
#[cfg(any(target_os = "android", test))]
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

/// A missing file means zero consecutive failures. Unparseable contents are an
/// error so that callers fail closed.
#[cfg(any(target_os = "android", test))]
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

#[cfg(any(target_os = "android", test))]
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

#[cfg(any(target_os = "android", test))]
fn remove_file_durably(path: &Path) -> io::Result<()> {
    match fs::remove_file(path) {
        Ok(()) => sync_parent(path),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
    }
}

#[cfg(any(target_os = "android", test))]
fn sync_parent(path: &Path) -> io::Result<()> {
    let parent = path.parent().ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "WebGPU canary path has no parent directory",
        )
    })?;
    File::open(parent)?.sync_all()
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
        // Dawn selects its adapter independently of the probe, so a mixed
        // set must fail closed.
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

        // Dropped without disarming, as after a crash or background kill.
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
