pub mod api;

#[cfg(feature = "flutter")]
#[expect(
    unsafe_code,
    clippy::allow_attributes,
    clippy::allow_attributes_without_reason,
    clippy::unwrap_used,
    reason = "Flutter Rust Bridge generates unsafe bindings, unwrap calls and allow attributes without reasons"
)]
#[rustfmt::skip]
mod frb_generated;
