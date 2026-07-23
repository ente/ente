pub mod ml;
pub mod motion_photo;

pub use motion_photo::{
    MotionPhotoError, VideoIndex, extract_motion_video_file_from_path,
    extract_motion_video_from_path, extract_xmp_from_path, get_motion_video_index_from_path,
};
