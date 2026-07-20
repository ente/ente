//! WASM bindings for URL construction.

use wasm_bindgen::prelude::*;

/// Generate the download URL for a file.
#[wasm_bindgen]
pub fn file_download_url(api_origin: &str, file_id: i64) -> String {
    ente_core::urls::file_download_url(api_origin, file_id)
}
