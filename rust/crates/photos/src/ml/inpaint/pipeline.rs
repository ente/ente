//! Moebius inpainting pipeline: preprocess -> VAE encode -> DDIM/CFG denoise
//! loop -> VAE decode -> feathered full-resolution composite.
//!
//! Faithful re-implementation of the reference `onnx_pipeline.py`
//! (`simonw/moebius-web`), with one deliberate extension: instead of returning
//! the 512x512 result, we upscale the inpainted region and its feathered mask
//! back to the original resolution and composite over the untouched original so
//! pixels outside the mask stay full-resolution.

use ente_image::types::DecodedImage;
use fast_image_resize::{
    FilterType, PixelType, ResizeAlg, ResizeOptions, Resizer,
    images::{Image as FirImage, ImageRef as FirImageRef},
};
use ort::{Session, Tensor};

use std::time::Instant;

use crate::ml::{
    error::{MlError, MlResult},
    inpaint::{ilog, noise::GaussianRng, scheduler::DdimSchedule},
    onnx,
    runtime::ExecutionProviderPolicy,
};

pub const SCALING_FACTOR: f32 = 0.13025;
pub const NOISE_OFFSET: f32 = 0.0357;
/// 20 -> 19 effective steps, matching the reference pipeline. The schedule
/// pins the starting timestep at t=900 for any step count (see scheduler.rs),
/// so lower counts trade quality for speed gracefully.
pub const DEFAULT_NUM_STEPS: usize = 20;
pub const DEFAULT_GUIDANCE: f32 = 2.0;
/// Gaussian blur radius (in 512-space pixels) used to feather the mask edge.
const MASK_FEATHER_SIGMA: f32 = 3.0;
/// JPEG quality for the returned, composited image.
pub const OUTPUT_JPEG_QUALITY: u8 = 95;

const IMG: usize = 512;
const LAT: usize = 64;
const LAT_CH: usize = 4;
const LAT_SPATIAL: usize = LAT * LAT; // 4096
const LAT_SIZE: usize = LAT_CH * LAT_SPATIAL; // 16384

/// Result of a successful inpaint: full-resolution RGB8 plus its dimensions.
pub struct CompositeResult {
    pub rgb: Vec<u8>,
    pub width: u32,
    pub height: u32,
}

/// Runs the full pipeline. Sessions are built and dropped stage-by-stage to keep
/// peak memory near the size of the single largest graph (the U-Net) rather than
/// the sum of all three.
pub fn run(
    image: &DecodedImage,
    mask: &DecodedImage,
    unet_path: &str,
    vae_encoder_path: &str,
    vae_decoder_path: &str,
    policy: &ExecutionProviderPolicy,
    num_steps: usize,
    guidance: f32,
    seed: u64,
) -> MlResult<CompositeResult> {
    let width = image.dimensions.width;
    let height = image.dimensions.height;
    if width == 0 || height == 0 {
        return Err(MlError::Preprocess(
            "image dimensions cannot be zero".to_string(),
        ));
    }

    let total_start = Instant::now();
    let tuning = onnx::SessionTuning {
        intra_threads: inpaint_threads(),
    };
    ilog(&format!(
        "start: {width}x{height}, num_steps={num_steps}, guidance={guidance}, threads={}",
        tuning.intra_threads
    ));

    // --- preprocess: image -> 512 CHW [-1,1], mask -> 512 binary {0,255} ---
    let img_rgb_512 = resize_rgb(
        &image.rgb,
        width,
        height,
        IMG as u32,
        IMG as u32,
        ResizeAlg::Convolution(FilterType::Lanczos3),
    )?;
    let img_chw_512 = rgb_to_chw_normalized(&img_rgb_512);

    let mask_gray = rgb_to_gray(&mask.rgb);
    let mask_512 = resize_gray(
        &mask_gray,
        mask.dimensions.width,
        mask.dimensions.height,
        IMG as u32,
        IMG as u32,
        ResizeAlg::Nearest,
    )?;
    let mask_512_bin: Vec<f32> = mask_512
        .iter()
        .map(|&v| if v >= 128 { 1.0 } else { 0.0 })
        .collect();

    // masked image (zero the hole, in [-1,1] space) for the conditioning latent.
    let mut masked_chw = img_chw_512.clone();
    for c in 0..3 {
        let base = c * IMG * IMG;
        for i in 0..IMG * IMG {
            masked_chw[base + i] *= 1.0 - mask_512_bin[i];
        }
    }

    // mask downsampled to latent size (64x64, nearest) as {0,1}.
    let mask_64_u8 = resize_gray(
        &mask_512,
        IMG as u32,
        IMG as u32,
        LAT as u32,
        LAT as u32,
        ResizeAlg::Nearest,
    )?;
    let mask_small: Vec<f32> = mask_64_u8
        .iter()
        .map(|&v| if v >= 128 { 1.0 } else { 0.0 })
        .collect();

    // --- VAE encode (masked image only; clean latent is unused by the loop) ---
    let masked_lat = {
        let t = Instant::now();
        let encoder = onnx::build_session_tuned(vae_encoder_path, policy, tuning)?;
        ilog(&format!("vae_encoder loaded in {} ms", t.elapsed().as_millis()));
        let t = Instant::now();
        let lat = encode_latent(&encoder, &masked_chw)?;
        ilog(&format!("vae encode done in {} ms", t.elapsed().as_millis()));
        lat
    };

    // --- init noise: randn(4,64,64) + noise_offset * randn(4,1,1) ---
    let mut rng = GaussianRng::new(seed);
    let mut latents = vec![0f32; LAT_SIZE];
    rng.fill_normal(&mut latents);
    for c in 0..LAT_CH {
        let channel_offset = NOISE_OFFSET * rng.next_normal();
        let base = c * LAT_SPATIAL;
        for i in 0..LAT_SPATIAL {
            latents[base + i] += channel_offset;
        }
    }

    // --- DDIM denoise loop with classifier-free guidance ---
    let schedule = DdimSchedule::new(num_steps);
    let input_ids = cfg_input_ids();
    {
        let t0 = Instant::now();
        let unet = onnx::build_session_tuned(unet_path, policy, tuning)?;
        ilog(&format!("unet loaded in {} ms", t0.elapsed().as_millis()));
        let total_steps = schedule.timesteps.len();
        for i in 0..schedule.timesteps.len() {
            let step_start = Instant::now();
            let t = schedule.timesteps[i];
            let prev_t = if i + 1 < schedule.timesteps.len() {
                schedule.timesteps[i + 1]
            } else {
                -1
            };

            // Assemble the 9-channel input [latents(4) | mask(1) | masked_lat(4)]
            // and duplicate it for the CFG batch (row 0 uncond, row 1 cond).
            let nine = assemble_nine(&latents, &mask_small, &masked_lat);
            let mut batch = Vec::with_capacity(2 * nine.len());
            batch.extend_from_slice(&nine);
            batch.extend_from_slice(&nine);

            let noise_pred = run_unet(&unet, batch, [t, t], &input_ids)?;
            let (nu, nc) = noise_pred.split_at(LAT_SIZE);
            let mut pred = vec![0f32; LAT_SIZE];
            for j in 0..LAT_SIZE {
                pred[j] = nu[j] + guidance * (nc[j] - nu[j]);
            }

            schedule.step(&mut latents, &pred, t, prev_t);
            ilog(&format!(
                "denoise step {}/{} (t={t}) in {} ms",
                i + 1,
                total_steps,
                step_start.elapsed().as_millis()
            ));
        }
    }

    // --- VAE decode -> 512 RGB8 ---
    let decoded_512 = {
        let t = Instant::now();
        let decoder = onnx::build_session_tuned(vae_decoder_path, policy, tuning)?;
        ilog(&format!("vae_decoder loaded in {} ms", t.elapsed().as_millis()));
        let t = Instant::now();
        let img = decode_latent(&decoder, &latents)?;
        ilog(&format!("vae decode done in {} ms", t.elapsed().as_millis()));
        img
    };

    // --- full-resolution feathered composite ---
    let t = Instant::now();
    let composite = composite_full_res(
        &image.rgb,
        width,
        height,
        &decoded_512,
        &mask_512_bin,
    )?;
    ilog(&format!("composite done in {} ms", t.elapsed().as_millis()));

    ilog(&format!(
        "done: total {} ms",
        total_start.elapsed().as_millis()
    ));

    Ok(CompositeResult {
        rgb: composite,
        width,
        height,
    })
}

/// Thread count for the interactive inpaint sessions. Unlike the background
/// indexing models (which deliberately stay single-threaded), inpainting is a
/// foreground, user-visible wait, so it should use the performance cores.
/// Heuristic: half the logical cores targets the big+mid cluster on typical
/// big.LITTLE phone SoCs without dragging in the slow little cores.
fn inpaint_threads() -> usize {
    std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(4)
        .div_ceil(2)
        .clamp(2, 6)
}

/// input_ids for the CFG batch: row 0 = uncond [10..20), row 1 = cond [0..10).
fn cfg_input_ids() -> Vec<i64> {
    let mut ids = Vec::with_capacity(20);
    ids.extend(10..20); // uncond
    ids.extend(0..10); // cond
    ids
}

fn assemble_nine(latents: &[f32], mask_small: &[f32], masked_lat: &[f32]) -> Vec<f32> {
    let mut nine = Vec::with_capacity(9 * LAT_SPATIAL);
    nine.extend_from_slice(latents); // 4 channels
    nine.extend_from_slice(mask_small); // 1 channel
    nine.extend_from_slice(masked_lat); // 4 channels
    nine
}

/// Encode a normalized CHW image into the 4-channel latent mean (scaled).
fn encode_latent(session: &Session, img_chw: &[f32]) -> MlResult<Vec<f32>> {
    let (_shape, out) = onnx::run_f32(session, img_chw.to_vec(), [1, 3, IMG as i64, IMG as i64])?;
    if out.len() < LAT_SIZE {
        return Err(MlError::Ort(format!(
            "VAE encoder produced {} values, expected at least {}",
            out.len(),
            LAT_SIZE
        )));
    }
    // Take the first 4 channels (the distribution mean) and scale.
    Ok(out[..LAT_SIZE].iter().map(|v| v * SCALING_FACTOR).collect())
}

/// Decode latents into a 512x512 RGB8 buffer.
fn decode_latent(session: &Session, latents: &[f32]) -> MlResult<Vec<u8>> {
    let scaled: Vec<f32> = latents.iter().map(|v| v / SCALING_FACTOR).collect();
    let (_shape, out) = onnx::run_f32(session, scaled, [1, LAT_CH as i64, LAT as i64, LAT as i64])?;
    let expected = 3 * IMG * IMG;
    if out.len() != expected {
        return Err(MlError::Ort(format!(
            "VAE decoder produced {} values, expected {}",
            out.len(),
            expected
        )));
    }
    // CHW [-1,1] -> interleaved RGB8 [0,255].
    let mut rgb = vec![0u8; expected];
    for i in 0..IMG * IMG {
        for c in 0..3 {
            let v = ((out[c * IMG * IMG + i] + 1.0) / 2.0).clamp(0.0, 1.0);
            rgb[i * 3 + c] = (v * 255.0).round() as u8;
        }
    }
    Ok(rgb)
}

/// Run the U-Net once over the CFG batch (batch = 2). Returns the flat
/// `(2 * 4 * 64 * 64)` noise prediction.
fn run_unet(
    session: &Session,
    latent_batch: Vec<f32>,
    timesteps: [i64; 2],
    input_ids: &[i64],
) -> MlResult<Vec<f32>> {
    let latent_shape = [2i64, 9, LAT as i64, LAT as i64];
    let timesteps_tensor = Tensor::<i64>::from_array(([2i64], timesteps.to_vec()))?;
    let input_ids_tensor = Tensor::<i64>::from_array(([2i64, 10], input_ids.to_vec()))?;

    // The fp16 U-Net wants an fp16 `latent` input (timesteps/input_ids stay
    // int64); the fp32 U-Net wants f32. Build whichever the model expects.
    let outputs = if onnx::session_expects_f16(session) {
        let f16_latent: Vec<half::f16> =
            latent_batch.into_iter().map(half::f16::from_f32).collect();
        let latent_tensor = Tensor::<half::f16>::from_array((latent_shape, f16_latent))?;
        session.run(ort::inputs![
            "latent" => latent_tensor,
            "timesteps" => timesteps_tensor,
            "input_ids" => input_ids_tensor,
        ]?)?
    } else {
        let latent_tensor = Tensor::<f32>::from_array((latent_shape, latent_batch))?;
        session.run(ort::inputs![
            "latent" => latent_tensor,
            "timesteps" => timesteps_tensor,
            "input_ids" => input_ids_tensor,
        ]?)?
    };

    if outputs.is_empty() {
        return Err(MlError::Ort("U-Net produced no output".to_string()));
    }
    let output = &outputs[0];
    if let Ok(tensor) = output.try_extract_tensor::<f32>() {
        Ok(tensor.iter().copied().collect())
    } else {
        let tensor = output.try_extract_tensor::<half::f16>()?;
        Ok(tensor.iter().map(|v: &half::f16| v.to_f32()).collect())
    }
}

/// Composite the 512 inpaint result back into the original full-resolution image
/// using a feathered mask, so only the masked region changes.
fn composite_full_res(
    original_rgb: &[u8],
    width: u32,
    height: u32,
    inpaint_512: &[u8],
    mask_512_bin: &[f32],
) -> MlResult<Vec<u8>> {
    // Feather the binary mask at 512, then upscale to full resolution.
    let blurred = gaussian_blur_gray(mask_512_bin, IMG, IMG, MASK_FEATHER_SIGMA);
    let blurred_u8: Vec<u8> = blurred
        .iter()
        .map(|v| (v.clamp(0.0, 1.0) * 255.0).round() as u8)
        .collect();
    let mask_full = resize_gray(
        &blurred_u8,
        IMG as u32,
        IMG as u32,
        width,
        height,
        ResizeAlg::Convolution(FilterType::Bilinear),
    )?;
    let inpaint_full = resize_rgb(
        inpaint_512,
        IMG as u32,
        IMG as u32,
        width,
        height,
        ResizeAlg::Convolution(FilterType::Lanczos3),
    )?;

    let pixels = (width as usize) * (height as usize);
    let expected = pixels * 3;
    if original_rgb.len() != expected {
        return Err(MlError::Postprocess(format!(
            "original RGB buffer length {} does not match {}x{}",
            original_rgb.len(),
            width,
            height
        )));
    }

    let mut out = vec![0u8; expected];
    for i in 0..pixels {
        let m = mask_full[i] as f32 / 255.0;
        for c in 0..3 {
            let fg = inpaint_full[i * 3 + c] as f32;
            let bg = original_rgb[i * 3 + c] as f32;
            out[i * 3 + c] = (fg * m + bg * (1.0 - m)).round().clamp(0.0, 255.0) as u8;
        }
    }
    Ok(out)
}

// ── small image helpers ─────────────────────────────────────────────────────

fn rgb_to_chw_normalized(rgb: &[u8]) -> Vec<f32> {
    let spatial = IMG * IMG;
    let mut out = vec![0f32; 3 * spatial];
    for i in 0..spatial {
        for c in 0..3 {
            out[c * spatial + i] = rgb[i * 3 + c] as f32 / 255.0 * 2.0 - 1.0;
        }
    }
    out
}

fn rgb_to_gray(rgb: &[u8]) -> Vec<u8> {
    // Max of channels: robust to any (possibly colored) brush stroke on black.
    let pixels = rgb.len() / 3;
    let mut out = vec![0u8; pixels];
    for i in 0..pixels {
        out[i] = rgb[i * 3].max(rgb[i * 3 + 1]).max(rgb[i * 3 + 2]);
    }
    out
}

fn resize_rgb(
    src: &[u8],
    sw: u32,
    sh: u32,
    dw: u32,
    dh: u32,
    alg: ResizeAlg,
) -> MlResult<Vec<u8>> {
    resize_with(src, sw, sh, dw, dh, PixelType::U8x3, alg)
}

fn resize_gray(
    src: &[u8],
    sw: u32,
    sh: u32,
    dw: u32,
    dh: u32,
    alg: ResizeAlg,
) -> MlResult<Vec<u8>> {
    resize_with(src, sw, sh, dw, dh, PixelType::U8, alg)
}

fn resize_with(
    src: &[u8],
    sw: u32,
    sh: u32,
    dw: u32,
    dh: u32,
    pixel: PixelType,
    alg: ResizeAlg,
) -> MlResult<Vec<u8>> {
    let src_image = FirImageRef::new(sw, sh, src, pixel)
        .map_err(|e| MlError::Preprocess(format!("failed to create FIR source image: {e}")))?;
    let mut dst_image = FirImage::new(dw, dh, pixel);
    let mut resizer = Resizer::new();
    let options = ResizeOptions::new().resize_alg(alg);
    resizer
        .resize(&src_image, &mut dst_image, Some(&options))
        .map_err(|e| MlError::Preprocess(format!("failed to resize image: {e}")))?;
    Ok(dst_image.buffer().to_vec())
}

/// Separable Gaussian blur over a normalized {0,1} single-channel buffer.
fn gaussian_blur_gray(src: &[f32], w: usize, h: usize, sigma: f32) -> Vec<f32> {
    let radius = (3.0 * sigma).ceil() as i32;
    let mut kernel = Vec::with_capacity((2 * radius + 1) as usize);
    let mut sum = 0f32;
    for k in -radius..=radius {
        let v = (-(k * k) as f32 / (2.0 * sigma * sigma)).exp();
        kernel.push(v);
        sum += v;
    }
    for v in kernel.iter_mut() {
        *v /= sum;
    }

    let clamp = |val: i32, max: i32| val.clamp(0, max - 1) as usize;

    // Horizontal pass.
    let mut tmp = vec![0f32; w * h];
    for y in 0..h {
        for x in 0..w {
            let mut acc = 0f32;
            for (ki, &kv) in kernel.iter().enumerate() {
                let sx = clamp(x as i32 + ki as i32 - radius, w as i32);
                acc += kv * src[y * w + sx];
            }
            tmp[y * w + x] = acc;
        }
    }

    // Vertical pass.
    let mut out = vec![0f32; w * h];
    for y in 0..h {
        for x in 0..w {
            let mut acc = 0f32;
            for (ki, &kv) in kernel.iter().enumerate() {
                let sy = clamp(y as i32 + ki as i32 - radius, h as i32);
                acc += kv * tmp[sy * w + x];
            }
            out[y * w + x] = acc;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cfg_input_ids_layout() {
        let ids = cfg_input_ids();
        assert_eq!(ids.len(), 20);
        assert_eq!(&ids[0..10], &[10, 11, 12, 13, 14, 15, 16, 17, 18, 19]);
        assert_eq!(&ids[10..20], &[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    }

    #[test]
    fn gaussian_blur_preserves_constant_field() {
        let src = vec![1.0f32; 16 * 16];
        let out = gaussian_blur_gray(&src, 16, 16, 3.0);
        for v in out {
            assert!((v - 1.0).abs() < 1e-4);
        }
    }

    #[test]
    fn assemble_nine_has_nine_channels() {
        let latents = vec![0f32; LAT_SIZE];
        let mask = vec![0f32; LAT_SPATIAL];
        let masked_lat = vec![0f32; LAT_SIZE];
        let nine = assemble_nine(&latents, &mask, &masked_lat);
        assert_eq!(nine.len(), 9 * LAT_SPATIAL);
    }
}
