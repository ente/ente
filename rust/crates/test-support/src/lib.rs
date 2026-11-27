pub mod account_fixture;
mod museum;
mod net;
mod object_store;
pub mod photos_fixture;
mod postgres;
mod process;
mod server;

pub use museum::Museum;
pub use object_store::{HeldReads, ObjectStoreControl};

pub type TestResult<T = ()> = Result<T, Box<dyn std::error::Error>>;

pub const HARDCODED_OTT: &str = "123456";

pub const HARDCODED_OTT_EMAIL_SUFFIX: &str = "@example.org";
