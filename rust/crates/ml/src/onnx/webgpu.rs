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
    collections::BTreeMap,
    fs::{self, OpenOptions},
    io::{self, Write},
    path::{Path, PathBuf},
    sync::{Mutex, PoisonError},
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

#[cfg(any(
    target_os = "android",
    target_os = "linux",
    target_os = "windows",
    test
))]
static ACTIVE_CANARIES: Mutex<BTreeMap<PathBuf, u32>> = Mutex::new(BTreeMap::new());

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
        && canary_dir(model_path).is_some_and(|dir| !quarantined(&dir))
}

// Chromium's `gpu/config/webgpu_blocklist_impl.cc` Android 12+ policy as of
// 2026-07, minus ARM; revisit with pinned ONNX Runtime or Dawn upgrades.
// Leaving out ARM is temporary: Mali GPUs fail or hang on WebGPU inference
// with the current ONNX Runtime (ente/ente#14485). Add ARM back once ONNX
// Runtime fixes WebGPU on Mali, and bump CANARY_FILE_PREFIX so quarantined
// devices retry.
#[cfg(any(target_os = "android", test))]
const ALLOWLISTED_VULKAN_VENDOR_IDS: [u32; 2] = [
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
#[expect(
    unsafe_code,
    reason = "Probe Vulkan device vendors through ash's unsafe API"
)]
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
#[derive(Debug)]
pub(super) struct ArmedCanary {
    #[cfg(any(
        target_os = "android",
        target_os = "linux",
        target_os = "windows",
        test
    ))]
    path: PathBuf,
    #[cfg(any(
        target_os = "android",
        target_os = "linux",
        target_os = "windows",
        test
    ))]
    active: bool,
}

#[cfg(any(
    target_os = "android",
    target_os = "linux",
    target_os = "windows",
    test
))]
pub(super) fn arm_canary(model_path: &str, model_namespace: &str) -> io::Result<ArmedCanary> {
    let dir = canary_dir(model_path).ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "cannot derive WebGPU canary directory from model path",
        )
    })?;
    let path = dir.join(format!("{CANARY_FILE_PREFIX}{model_namespace}"));
    let mut active = ACTIVE_CANARIES
        .lock()
        .unwrap_or_else(PoisonError::into_inner);
    let failures = read_failure_count(&path)?;
    persist_failure_count(&path, failures.saturating_add(1))?;
    *active.entry(path.clone()).or_default() += 1;
    Ok(ArmedCanary { path, active: true })
}

impl ArmedCanary {
    pub(super) fn defer(self) {
        #[cfg(any(
            target_os = "android",
            target_os = "linux",
            target_os = "windows",
            test
        ))]
        {
            let mut canary = self;
            let mut active = ACTIVE_CANARIES
                .lock()
                .unwrap_or_else(PoisonError::into_inner);
            canary.active = false;
            retire_canary(&mut active, &canary.path);
            let result = read_failure_count(&canary.path).and_then(|failures| {
                update_failure_count(&canary.path, failures.saturating_sub(1))
            });
            if let Err(error) = result {
                log::warn!(
                    "failed to defer WebGPU crash canary at '{}': {error}",
                    canary.path.display()
                );
            }
        }
    }

    pub(super) fn disarm(self) {
        #[cfg(any(
            target_os = "android",
            target_os = "linux",
            target_os = "windows",
            test
        ))]
        {
            let mut canary = self;
            let mut active = ACTIVE_CANARIES
                .lock()
                .unwrap_or_else(PoisonError::into_inner);
            canary.active = false;
            let remaining = retire_canary(&mut active, &canary.path);
            if let Err(error) = update_failure_count(&canary.path, remaining) {
                log::warn!(
                    "failed to disarm WebGPU crash canary at '{}': {error}",
                    canary.path.display()
                );
            }
        }
    }
}

#[cfg(any(
    target_os = "android",
    target_os = "linux",
    target_os = "windows",
    test
))]
impl Drop for ArmedCanary {
    fn drop(&mut self) {
        if self.active {
            let mut active = ACTIVE_CANARIES
                .lock()
                .unwrap_or_else(PoisonError::into_inner);
            retire_canary(&mut active, &self.path);
        }
    }
}

#[cfg(any(
    target_os = "android",
    target_os = "linux",
    target_os = "windows",
    test
))]
fn retire_canary(active: &mut BTreeMap<PathBuf, u32>, path: &Path) -> u32 {
    let Some(count) = active.get_mut(path) else {
        return 0;
    };
    *count -= 1;
    let remaining = *count;
    if remaining == 0 {
        active.remove(path);
    }
    remaining
}

#[cfg(any(
    target_os = "android",
    target_os = "linux",
    target_os = "windows",
    test
))]
fn update_failure_count(path: &Path, failures: u32) -> io::Result<()> {
    if failures == 0 {
        remove_file_durably(path)
    } else {
        persist_failure_count(path, failures)
    }
}

#[cfg(any(
    target_os = "android",
    target_os = "linux",
    target_os = "windows",
    test
))]
fn canary_dir(model_path: &str) -> Option<PathBuf> {
    if model_path.trim().is_empty() {
        return None;
    }
    Path::new(model_path)
        .parent()?
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
fn is_canary(entry: &fs::DirEntry) -> bool {
    entry
        .file_name()
        .to_str()
        .is_some_and(|name| name.starts_with(CANARY_FILE_PREFIX))
}

#[cfg(any(
    target_os = "android",
    target_os = "linux",
    target_os = "windows",
    test
))]
fn quarantined(dir: &Path) -> bool {
    let _active = ACTIVE_CANARIES
        .lock()
        .unwrap_or_else(PoisonError::into_inner);
    let Ok(entries) = fs::read_dir(dir) else {
        return true;
    };
    let mut failures = 0_u32;
    for entry in entries {
        let Ok(entry) = entry else {
            return true;
        };
        if is_canary(&entry) {
            match read_failure_count(&entry.path()) {
                Ok(count) => failures = failures.saturating_add(count),
                Err(_) => return true,
            }
        } else {
            let Ok(kind) = entry.file_type() else {
                return true;
            };
            if kind.is_dir() && legacy_model_quarantined(&entry.path()) {
                return true;
            }
        }
    }
    failures >= MAX_CONSECUTIVE_FAILURES
}

#[cfg(any(
    target_os = "android",
    target_os = "linux",
    target_os = "windows",
    test
))]
fn legacy_model_quarantined(model_dir: &Path) -> bool {
    let Ok(entries) = fs::read_dir(model_dir) else {
        return true;
    };
    entries.into_iter().any(|entry| match entry {
        Err(_) => true,
        Ok(entry) => {
            is_canary(&entry)
                && !matches!(
                    read_failure_count(&entry.path()),
                    Ok(failures) if failures < MAX_CONSECUTIVE_FAILURES
                )
        }
    })
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
    fn allowlists_qualcomm_and_intel() {
        assert!(vendors_allowlisted(&[0x5143]), "Qualcomm");
        assert!(vendors_allowlisted(&[0x8086]), "Intel");
    }

    #[test]
    fn denies_arm_mali_and_immortalis() {
        assert!(!vendors_allowlisted(&[0x13B5]));
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
        assert!(vendors_allowlisted(&[0x5143, 0x8086]));
    }

    #[test]
    fn denies_when_no_adapters_are_enumerated() {
        assert!(!vendors_allowlisted(&[]));
    }

    fn model_path(dir: &std::path::Path) -> String {
        model_in(dir, "model")
    }

    fn model_in(dir: &std::path::Path, key: &str) -> String {
        let model_dir = dir.join(key);
        std::fs::create_dir_all(&model_dir).unwrap();
        model_dir.join("model.onnx").to_string_lossy().into_owned()
    }

    fn write_legacy_canary(dir: &std::path::Path, key: &str, failures: u32) {
        std::fs::write(
            dir.join(key)
                .join(format!("{}{key}", super::CANARY_FILE_PREFIX)),
            format!("{failures}\n"),
        )
        .unwrap();
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
    fn deferred_preloads_preserve_failures_until_quarantine() {
        let dir = tempfile::tempdir().unwrap();
        let model = model_path(dir.path());

        for attempt in 1..=MAX_CONSECUTIVE_FAILURES {
            assert!(!quarantined(dir.path()));
            arm_canary(&model, "ocr-detection").unwrap().defer();
            let canary = arm_canary(&model, "ocr-detection").unwrap();
            assert_eq!(super::read_failure_count(&canary.path).unwrap(), attempt);
            drop(canary);
        }

        assert!(quarantined(dir.path()));
    }

    #[test]
    fn overlapping_success_and_deferral_clear_prior_failures() {
        for prior_failures in 0..=2 {
            let dir = tempfile::tempdir().unwrap();
            let model = model_path(dir.path());
            for _ in 0..prior_failures {
                drop(arm_canary(&model, "ocr-detection").unwrap());
            }
            let inference = arm_canary(&model, "ocr-detection").unwrap();
            let preload = arm_canary(&model, "ocr-detection").unwrap();
            let path = preload.path.clone();

            inference.disarm();

            assert_eq!(super::read_failure_count(&path).unwrap(), 1);
            preload.defer();
            assert!(!path.exists());
            assert!(!quarantined(dir.path()));
        }
    }

    #[test]
    fn deferring_preload_preserves_a_newer_attempt() {
        let dir = tempfile::tempdir().unwrap();
        let model = model_path(dir.path());
        let first = arm_canary(&model, "ocr-detection").unwrap();
        let preload = arm_canary(&model, "ocr-detection").unwrap();
        first.disarm();
        let newer = arm_canary(&model, "ocr-detection").unwrap();
        let path = newer.path.clone();

        preload.defer();

        assert_eq!(super::read_failure_count(&path).unwrap(), 1);
        let newest = arm_canary(&model, "ocr-detection").unwrap();
        newer.disarm();
        assert_eq!(super::read_failure_count(&path).unwrap(), 1);
        drop(newest);
        assert_eq!(super::read_failure_count(&path).unwrap(), 1);
    }

    #[test]
    fn preload_deferral_preserves_a_later_inference_failure() {
        for prior_failures in 0..=2 {
            let dir = tempfile::tempdir().unwrap();
            let model = model_path(dir.path());
            for _ in 0..prior_failures {
                drop(arm_canary(&model, "ocr-detection").unwrap());
            }
            let preload = arm_canary(&model, "ocr-detection").unwrap();
            let inference = arm_canary(&model, "ocr-detection").unwrap();
            let path = inference.path.clone();

            preload.defer();
            drop(inference);

            assert_eq!(
                super::read_failure_count(&path).unwrap(),
                prior_failures + 1
            );
            assert_eq!(quarantined(dir.path()), prior_failures == 2);
        }
    }

    #[test]
    fn overlapping_deferrals_preserve_only_prior_failures() {
        for prior_failures in 0..=2 {
            let dir = tempfile::tempdir().unwrap();
            let model = model_path(dir.path());
            for _ in 0..prior_failures {
                drop(arm_canary(&model, "ocr-detection").unwrap());
            }
            let first = arm_canary(&model, "ocr-detection").unwrap();
            let second = arm_canary(&model, "ocr-detection").unwrap();
            let path = first.path.clone();

            first.defer();
            second.defer();

            assert_eq!(super::read_failure_count(&path).unwrap(), prior_failures);
            assert!(!quarantined(dir.path()));
        }
    }

    #[test]
    fn successful_attempt_preserves_another_live_attempt() {
        let dir = tempfile::tempdir().unwrap();
        let model = model_path(dir.path());
        let first = arm_canary(&model, "ocr-detection").unwrap();
        let second = arm_canary(&model, "ocr-detection").unwrap();
        let path = second.path.clone();

        first.disarm();
        drop(second);

        assert_eq!(super::read_failure_count(&path).unwrap(), 1);
        arm_canary(&model, "ocr-detection").unwrap().disarm();
        assert!(!path.exists());
    }

    #[test]
    fn failed_arm_persistence_does_not_register_an_active_attempt() {
        let dir = tempfile::tempdir().unwrap();
        let model = model_path(dir.path());
        let namespace = "missing-directory/ocr-detection";
        let path = dir
            .path()
            .join(format!("{}{namespace}", super::CANARY_FILE_PREFIX));

        assert!(arm_canary(&model, namespace).is_err());

        assert!(!super::ACTIVE_CANARIES.lock().unwrap().contains_key(&path));
    }

    #[test]
    fn failed_deferral_retires_its_active_attempt() {
        let dir = tempfile::tempdir().unwrap();
        let model = model_path(dir.path());
        let canary = arm_canary(&model, "ocr-detection").unwrap();
        let path = canary.path.clone();
        std::fs::write(&path, "invalid count").unwrap();

        canary.defer();

        assert!(quarantined(dir.path()));
        assert!(!super::ACTIVE_CANARIES.lock().unwrap().contains_key(&path));
        std::fs::remove_file(&path).unwrap();
        arm_canary(&model, "ocr-detection").unwrap().disarm();
        assert!(!path.exists());
    }

    #[test]
    fn failed_disarm_retires_its_active_attempt() {
        let dir = tempfile::tempdir().unwrap();
        let model = model_path(dir.path());
        let canary = arm_canary(&model, "ocr-detection").unwrap();
        let path = canary.path.clone();
        std::fs::remove_file(&path).unwrap();
        std::fs::create_dir(&path).unwrap();

        canary.disarm();

        assert!(quarantined(dir.path()));
        assert!(!super::ACTIVE_CANARIES.lock().unwrap().contains_key(&path));
        std::fs::remove_dir(&path).unwrap();
        arm_canary(&model, "ocr-detection").unwrap().disarm();
        assert!(!path.exists());
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
    fn canaries_live_in_the_directory_shared_by_all_models() {
        let dir = tempfile::tempdir().unwrap();
        let clip = model_in(dir.path(), "clip");

        drop(arm_canary(&clip, "clip-image").unwrap());

        assert!(
            dir.path()
                .join(format!("{}clip-image", super::CANARY_FILE_PREFIX))
                .exists()
        );
        assert!(
            !dir.path()
                .join("clip")
                .join(format!("{}clip-image", super::CANARY_FILE_PREFIX))
                .exists()
        );
    }

    #[test]
    fn failures_accumulate_across_models() {
        let dir = tempfile::tempdir().unwrap();
        let clip = model_in(dir.path(), "clip");
        let detection = model_in(dir.path(), "face-detection");
        let embedding = model_in(dir.path(), "face-embedding");

        drop(arm_canary(&clip, "clip-image").unwrap());
        drop(arm_canary(&detection, "face-detection").unwrap());
        assert!(!quarantined(dir.path()));
        drop(arm_canary(&embedding, "face-embedding").unwrap());

        assert!(quarantined(dir.path()));
    }

    #[test]
    fn success_clears_only_that_models_failures() {
        let dir = tempfile::tempdir().unwrap();
        let clip = model_in(dir.path(), "clip");
        let detection = model_in(dir.path(), "face-detection");

        drop(arm_canary(&detection, "face-detection").unwrap());
        drop(arm_canary(&detection, "face-detection").unwrap());
        arm_canary(&clip, "clip-image").unwrap().disarm();
        assert!(!quarantined(dir.path()));
        drop(arm_canary(&detection, "face-detection").unwrap());

        assert!(quarantined(dir.path()));
    }

    #[test]
    fn full_per_model_quarantine_from_earlier_versions_applies_to_every_model() {
        let dir = tempfile::tempdir().unwrap();
        model_in(dir.path(), "clip");
        model_in(dir.path(), "face-detection");

        write_legacy_canary(dir.path(), "clip", MAX_CONSECUTIVE_FAILURES);

        assert!(quarantined(dir.path()));
    }

    #[test]
    fn partial_per_model_failures_from_earlier_versions_are_not_carried_over() {
        let dir = tempfile::tempdir().unwrap();
        model_in(dir.path(), "clip");
        model_in(dir.path(), "face-detection");
        model_in(dir.path(), "face-embedding");

        write_legacy_canary(dir.path(), "clip", MAX_CONSECUTIVE_FAILURES - 1);
        write_legacy_canary(dir.path(), "face-detection", MAX_CONSECUTIVE_FAILURES - 1);

        assert!(!quarantined(dir.path()));
    }

    #[test]
    fn unlistable_per_model_folder_from_earlier_versions_fails_closed() {
        let dir = tempfile::tempdir().unwrap();

        assert!(super::legacy_model_quarantined(&dir.path().join("clip")));
    }

    #[test]
    fn unreadable_per_model_canary_from_earlier_versions_fails_closed() {
        let dir = tempfile::tempdir().unwrap();
        model_in(dir.path(), "clip");
        std::fs::write(
            dir.path()
                .join("clip")
                .join(format!("{}clip-image", super::CANARY_FILE_PREFIX)),
            b"not a number",
        )
        .unwrap();

        assert!(quarantined(dir.path()));
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
