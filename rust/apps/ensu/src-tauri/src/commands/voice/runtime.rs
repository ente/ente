use super::{ApiError, error};
use tauri::{AppHandle, Manager};

pub(super) fn unsupported_reason() -> Option<String> {
    if supported() {
        None
    } else {
        Some("Voice input requires macOS 13.3 or later.".into())
    }
}

#[cfg(target_os = "macos")]
fn supported() -> bool {
    crate::platform::macos_version()
        .is_some_and(|(major, minor)| major > 13 || major == 13 && minor >= 3)
}

#[cfg(not(target_os = "macos"))]
fn supported() -> bool {
    true
}

pub(super) fn path(app: &AppHandle) -> Result<std::path::PathBuf, ApiError> {
    let arch = match std::env::consts::ARCH {
        "aarch64" => "arm64",
        "x86_64" => "x64",
        other => other,
    };
    let name = if cfg!(target_os = "macos") {
        "libonnxruntime.dylib"
    } else if cfg!(windows) {
        "onnxruntime.dll"
    } else {
        "libonnxruntime.so"
    };
    let relative = if cfg!(target_os = "macos") {
        std::path::PathBuf::from("../Frameworks").join(name)
    } else {
        std::path::PathBuf::from("onnxruntime")
            .join(arch)
            .join(name)
    };
    let bundled = app.path().resource_dir().map_err(error)?.join(relative);
    if bundled.is_file() {
        return Ok(bundled);
    }
    if cfg!(debug_assertions) {
        let source = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("onnxruntime");
        let source = if cfg!(target_os = "macos") {
            source.join(name)
        } else {
            source.join(arch).join(name)
        };
        if source.is_file() {
            return Ok(source);
        }
    }
    Err(error(
        "The speech runtime is missing. Reinstall Ensu or run scripts/prepare-voice-runtime.mjs when developing.",
    ))
}
