//! On-device object removal ("AI edit") via the Moebius latent-diffusion
//! inpainting model.
//!
//! The whole diffusion pipeline runs in Rust: a single [`inpaint`] call decodes
//! the image and mask, runs the three ONNX graphs (VAE encoder, U-Net, VAE
//! decoder) with a host-side DDIM + classifier-free-guidance loop, composites
//! the result back at full resolution, and returns an encoded JPEG.
//!
//! Models are loaded on demand and dropped stage-by-stage, so this never has to
//! be resident alongside the discriminative indexing models in [`super::runtime`].

mod noise;
pub mod pipeline;
mod scheduler;

use ente_image::{decode::decode_image_from_path, image_compression};

use crate::ml::{
    error::{MlError, MlResult},
    runtime::ExecutionProviderPolicy,
};

/// Log a progress/diagnostic line for inpainting. On Android this goes to
/// logcat under the `ml_inpaint` tag (filter with `adb logcat -s ml_inpaint`),
/// elsewhere to stderr. Inference runs on a Rust worker thread, so these are the
/// only way to observe progress of the (multi-minute) pipeline.
pub(crate) fn ilog(msg: &str) {
    #[cfg(target_os = "android")]
    {
        unsafe extern "C" {
            unsafe fn __android_log_write(
                prio: std::ffi::c_int,
                tag: *const std::ffi::c_char,
                text: *const std::ffi::c_char,
            ) -> std::ffi::c_int;
        }
        use std::ffi::CString;
        let tag = CString::new("ml_inpaint").unwrap();
        let cmsg = CString::new(msg).unwrap_or_else(|_| CString::new("(invalid)").unwrap());
        unsafe {
            __android_log_write(4, tag.as_ptr(), cmsg.as_ptr());
        }
    }
    #[cfg(not(target_os = "android"))]
    {
        eprintln!("[ml][inpaint] {msg}");
    }
}

/// Filesystem paths to the three Moebius ONNX graphs.
#[derive(Clone, Debug)]
pub struct InpaintModelPaths {
    pub unet: String,
    pub vae_encoder: String,
    pub vae_decoder: String,
}

/// A single inpainting request.
#[derive(Clone, Debug)]
pub struct InpaintRequest {
    /// Source image on disk (any format the `ente_image` decoder supports).
    pub image_path: String,
    /// Mask on disk: the region to erase is non-black (white strokes on black).
    pub mask_path: String,
    pub model_paths: InpaintModelPaths,
    pub provider_policy: ExecutionProviderPolicy,
    /// Number of scheduler steps before the strength-0.99 drop (default 20 -> 19
    /// effective steps). Lower is faster, higher is (marginally) higher quality.
    pub num_steps: usize,
    /// Classifier-free guidance scale (default 2.0).
    pub guidance: f32,
    /// Seed for the initial noise. Deterministic within this implementation.
    pub seed: u64,
}

/// Run object removal end to end. Returns a JPEG-encoded, full-resolution image.
pub fn inpaint(req: InpaintRequest) -> MlResult<Vec<u8>> {
    let num_steps = if req.num_steps == 0 {
        pipeline::DEFAULT_NUM_STEPS
    } else {
        req.num_steps
    };
    let guidance = if req.guidance <= 0.0 {
        pipeline::DEFAULT_GUIDANCE
    } else {
        req.guidance
    };

    let t = std::time::Instant::now();
    let image = decode_image_from_path(&req.image_path)?;
    let mask = decode_image_from_path(&req.mask_path)?;
    ilog(&format!("inputs decoded in {} ms", t.elapsed().as_millis()));

    let result = pipeline::run(
        &image,
        &mask,
        &req.model_paths.unet,
        &req.model_paths.vae_encoder,
        &req.model_paths.vae_decoder,
        &req.provider_policy,
        num_steps,
        guidance,
        req.seed,
    )?;

    let t = std::time::Instant::now();
    let jpeg = image_compression::encode_rgb(
        &result.rgb,
        result.width,
        result.height,
        image_compression::EncodedImageFormat::Jpeg {
            quality: pipeline::OUTPUT_JPEG_QUALITY,
        },
    )
    .map_err(MlError::from)?;
    ilog(&format!("jpeg encode done in {} ms", t.elapsed().as_millis()));
    Ok(jpeg)
}
