//! FRB initialization

/// Set up the Rust runtime.
///
/// Called when EnteRust.init() is invoked from Dart.
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
