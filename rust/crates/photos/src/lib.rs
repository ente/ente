pub mod collections;
#[cfg(not(target_arch = "wasm32"))]
pub mod db;
pub mod dedup;
pub mod face_clustering;
pub mod files;
#[cfg(not(target_arch = "wasm32"))]
pub mod location;
#[cfg(not(target_arch = "wasm32"))]
pub mod memories;
pub mod metadata;
#[cfg(not(target_arch = "wasm32"))]
pub mod ml_db;
#[cfg(not(target_arch = "wasm32"))]
pub mod ml_store;
pub mod motion_photo;
pub mod source;

pub use motion_photo::{
    MotionPhotoError, VideoIndex, extract_motion_video_file_from_path,
    extract_motion_video_from_path, extract_xmp_from_path, get_motion_video_index_from_path,
};
