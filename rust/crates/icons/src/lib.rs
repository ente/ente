#![cfg(not(target_arch = "wasm32"))]

mod discovery;
mod fetch;
mod format;

pub use fetch::{Error, Fetcher, Icon};
