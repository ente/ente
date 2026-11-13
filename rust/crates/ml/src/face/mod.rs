mod align;
mod detect;
mod embed;
pub mod thumbnail;

pub(crate) use align::run_face_alignment;
pub(crate) use detect::run_face_detection;
pub(crate) use embed::run_face_embedding;

const FACE_INPUT_SIZE: u32 = 112;
