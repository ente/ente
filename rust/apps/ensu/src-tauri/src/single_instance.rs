use tauri::{Manager, plugin::TauriPlugin};

use crate::logging;

pub fn plugin() -> TauriPlugin<tauri::Wry> {
    tauri_plugin_single_instance::init(|app, _, _| {
        logging::log(
            "App",
            "additional launch received; focusing existing window",
        );
        if let Some(window) = app.get_webview_window("main") {
            for (operation, result) in [
                ("show", window.show()),
                ("restore", window.unminimize()),
                ("focus", window.set_focus()),
            ] {
                if let Err(error) = result {
                    logging::log(
                        "App",
                        format!("failed to {operation} existing window error={error}"),
                    );
                }
            }
        }
    })
}
