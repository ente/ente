#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use tauri::{Manager, RunEvent};

mod commands;
mod logging;

fn main() {
    logging::install_panic_hook();
    logging::log("App", "starting Tauri backend");

    let app = tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .manage(commands::llm::State::default())
        .manage(commands::llm::ModelDownloadState::default())
        .manage(commands::chat_db::ChatDbState::default())
        .setup(|app| {
            logging::init_logging(app.handle());
            logging::log("App", "setup started");

            // Show the main window after setup is complete
            if let Some(window) = app.get_webview_window("main")
                && let Err(err) = window.show()
            {
                logging::log("App", format!("failed to show main window error={err}"));
                return Err(Box::new(err));
            }
            logging::log("App", "setup complete");
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::crypto::crypto_init,
            commands::crypto::crypto_generate_key,
            commands::crypto::crypto_encrypt_blob,
            commands::crypto::crypto_decrypt_blob,
            commands::secure_storage::secure_storage_get,
            commands::secure_storage::secure_storage_set,
            commands::secure_storage::secure_storage_delete,
            commands::chat_db::chat_db_list_sessions,
            commands::chat_db::chat_db_list_sessions_with_preview,
            commands::chat_db::chat_db_get_session,
            commands::chat_db::chat_db_create_session,
            commands::chat_db::chat_db_update_session_title,
            commands::chat_db::chat_db_delete_session,
            commands::chat_db::chat_db_get_messages,
            commands::chat_db::chat_db_insert_message,
            commands::chat_db::chat_db_update_message_text,
            commands::chat_db::chat_db_upsert_session,
            commands::chat_db::chat_db_insert_message_with_uuid,
            commands::chat_db::chat_db_compress_attachment_image_file,
            commands::chat_db::chat_db_open,
            commands::chat_db::chat_db_has_existing_store,
            commands::llm::llm_init_backend,
            commands::llm::llm_load_model,
            commands::llm::llm_create_context,
            commands::llm::llm_free_context,
            commands::llm::llm_free_model,
            commands::llm::llm_prewarm_multimodal_context,
            commands::llm::llm_generate_chat_stream,
            commands::llm::llm_cancel,
            commands::system::system_info,
            commands::config::config_defaults,
            commands::llm::llm_download_model_files,
            commands::llm::llm_cancel_model_download,
        ])
        .build(tauri::generate_context!())
        .unwrap_or_else(|err| {
            logging::log("App", format!("tauri build failed error={err}"));
            panic!("error while building tauri application: {err}");
        });

    app.run(|app_handle, event| {
        if matches!(event, RunEvent::ExitRequested { .. } | RunEvent::Exit) {
            commands::cleanup_for_exit(app_handle);
        }
    });
}
