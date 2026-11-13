#[cfg(feature = "account-deletion")]
pub mod account_deletion;
#[cfg(feature = "accounts")]
pub mod accounts;
#[cfg(feature = "cast")]
pub mod cast;
#[cfg(feature = "collections")]
pub mod collections;
#[cfg(feature = "contacts")]
pub mod contacts;
#[cfg(feature = "crypto")]
pub mod crypto;
#[cfg(feature = "legacy")]
pub mod legacy;
#[cfg(feature = "location")]
pub mod location;
#[cfg(feature = "locker")]
pub mod locker;
mod logging;
#[cfg(feature = "photos")]
pub mod photos;
#[cfg(feature = "prelogin")]
mod prelogin;
#[cfg(feature = "session")]
pub mod session;
#[cfg(any(feature = "crypto", feature = "session"))]
mod types;

#[cfg(any(feature = "crypto", feature = "session"))]
pub use types::EncryptedBox;

pub fn js_error(error: &dyn std::error::Error, name: Option<&str>) -> wasm_bindgen::JsValue {
    let js_error = js_sys::Error::new(&ente_core::error::chain(error));
    if let Some(name) = name {
        js_error.set_name(name);
    }
    js_error.into()
}
