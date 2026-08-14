#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // Install before FRB claims the process logger.
    #[cfg(feature = "flutter")]
    crate::api::log::install();
    flutter_rust_bridge::setup_default_user_utils();
}
