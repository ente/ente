use std::backtrace::Backtrace;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};
use std::time::{SystemTime, UNIX_EPOCH};

use tauri::{AppHandle, Manager};

static LOG_PATH: OnceLock<PathBuf> = OnceLock::new();
static LOG_LOCK: Mutex<()> = Mutex::new(());

const LOG_FILE_NAME: &str = "backend.log";

pub fn init_logging(app: &AppHandle) {
    let path = app
        .path()
        .app_data_dir()
        .map(|dir| dir.join(LOG_FILE_NAME))
        .unwrap_or_else(|_| default_log_path());

    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }

    let _ = LOG_PATH.set(path.clone());
    log(
        "App",
        format!("backend logging initialized path={}", path.display()),
    );
}

pub fn install_panic_hook() {
    let previous_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |panic_info| {
        let location = panic_info
            .location()
            .map(|loc| format!("{}:{}", loc.file(), loc.line()))
            .unwrap_or_else(|| "unknown".to_string());

        let payload = if let Some(message) = panic_info.payload().downcast_ref::<&str>() {
            (*message).to_string()
        } else if let Some(message) = panic_info.payload().downcast_ref::<String>() {
            message.clone()
        } else {
            "non-string panic payload".to_string()
        };

        let thread = std::thread::current()
            .name()
            .map(|name| name.to_string())
            .unwrap_or_else(|| "unnamed".to_string());

        log(
            "Panic",
            format!(
                "thread={thread} location={location} message={payload}\nbacktrace:\n{}",
                Backtrace::force_capture()
            ),
        );

        previous_hook(panic_info);
    }));
}

pub fn log(tag: &str, message: impl AsRef<str>) {
    append_line(tag, message.as_ref());
}

fn append_line(tag: &str, message: &str) {
    let _guard = LOG_LOCK.lock().ok();
    let path = LOG_PATH.get().cloned().unwrap_or_else(default_log_path);

    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }

    let timestamp_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis())
        .unwrap_or(0);

    if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(path) {
        let _ = writeln!(file, "[{timestamp_ms}][{tag}] {message}");
    }
}

fn default_log_path() -> PathBuf {
    if let Some(home) = std::env::var_os("HOME") {
        return PathBuf::from(home)
            .join("Library")
            .join("Application Support")
            .join("io.ente.ensu")
            .join(LOG_FILE_NAME);
    }

    std::env::temp_dir().join(LOG_FILE_NAME)
}
