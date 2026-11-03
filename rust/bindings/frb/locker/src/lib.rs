pub mod api;

#[global_allocator]
static ALLOCATOR: ente_image::BudgetedAllocator = ente_image::BudgetedAllocator;

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
