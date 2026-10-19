pub mod config;
pub mod conversation;
pub mod db;
pub mod image;
pub mod llm;
pub mod model;
pub mod notes;
pub mod retrieval;

#[cfg(target_os = "android")]
mod platform;

#[cfg(feature = "transcription")]
pub mod transcription;
