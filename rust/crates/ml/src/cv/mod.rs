mod contours;
pub(crate) mod image;
pub(crate) mod projective;
mod resize;
mod transform;
mod warp;
mod warp_rgb;

pub(crate) type OpResult<T> = Result<T, String>;

pub(crate) use contours::find_contours;
pub(crate) use resize::{Interp, resize_u8};
pub(crate) use transform::rotate_u8;
pub(crate) use warp::warp_rgb_perspective;
