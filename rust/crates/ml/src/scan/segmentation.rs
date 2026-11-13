use std::sync::Mutex;

use super::OpResult;
use super::scanner::ScanError;
use crate::cv;
use crate::cv::image::ImageU8;
use crate::error::MlError;
use crate::onnx::{ExecutionMode, OnnxSession, PreparedF32Input, SessionRunError, run_f32};

pub const MASK_SIDE: i32 = 256;

const MODEL_NAMESPACE: &str = "document-segmentation";

pub(crate) struct Segmenter {
    session: Mutex<OnnxSession>,
}

impl Segmenter {
    pub(crate) fn new(model_path: &str) -> Result<Self, ScanError> {
        let segmenter = Self {
            session: Mutex::new(
                OnnxSession::new(model_path, MODEL_NAMESPACE, ExecutionMode::PlatformDefault)
                    .with_unvalidated_acceleration(),
            ),
        };
        let samples = (MASK_SIDE * MASK_SIDE * 3) as usize;
        segmenter
            .infer(vec![0.0f32; samples])
            .map_err(ScanError::ModelLoad)?;
        Ok(segmenter)
    }

    fn infer(&self, input: Vec<f32>) -> OpResult<Vec<f32>> {
        let side = MASK_SIDE as i64;
        let expected = (MASK_SIDE * MASK_SIDE) as usize;
        let input = PreparedF32Input::new(input);
        let mut guard = match self.session.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        let (data, _usage) = guard
            .run(|session| {
                let (shape, values) = run_f32(session, &input, [1i64, side, side, 3])?;
                if values.len() != expected {
                    return Err(SessionRunError::from(MlError::Ort(format!(
                        "unexpected model output shape {shape:?}"
                    ))));
                }
                Ok(values)
            })
            .map_err(|error| error.to_string())?;
        Ok(data)
    }

    pub(crate) fn probability_map(&self, bgr: &ImageU8) -> OpResult<ProbabilityMap> {
        ProbabilityMap::new(
            self.infer(prepare_input(bgr)?)?,
            MASK_SIDE as usize,
            MASK_SIDE as usize,
        )
    }
}

pub(super) fn prepare_input(bgr: &ImageU8) -> OpResult<Vec<f32>> {
    if bgr.channels != 3 {
        return Err(format!(
            "segmentation requires three channels, got {}",
            bgr.channels
        ));
    }
    let resized = if bgr.width == MASK_SIDE && bgr.height == MASK_SIDE {
        None
    } else {
        Some(cv::resize_u8(
            bgr,
            MASK_SIDE,
            MASK_SIDE,
            cv::Interp::Bilinear,
        )?)
    };
    let resized = resized.as_ref().unwrap_or(bgr);
    let mut input = vec![0.0f32; resized.data.len()];
    for (out, px) in input
        .as_chunks_mut::<3>()
        .0
        .iter_mut()
        .zip(resized.data.as_chunks::<3>().0.iter())
    {
        out[0] = (px[2] as f32 - 127.5) / 127.5;
        out[1] = (px[1] as f32 - 127.5) / 127.5;
        out[2] = (px[0] as f32 - 127.5) / 127.5;
    }
    Ok(input)
}

pub(super) struct ProbabilityMap {
    pub width: usize,
    pub height: usize,
    pub values: Vec<f32>,
}

impl ProbabilityMap {
    pub fn new(mut values: Vec<f32>, width: usize, height: usize) -> OpResult<Self> {
        if width == 0 || height == 0 || width.checked_mul(height) != Some(values.len()) {
            return Err("invalid probability-map dimensions".to_owned());
        }
        if values.iter().any(|v| !v.is_finite()) {
            return Err("non-finite segmentation output".to_owned());
        }
        values.iter_mut().for_each(|v| *v = v.clamp(0.0, 1.0));
        Ok(Self {
            width,
            height,
            values,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scan::yuv::{PlaneLayout, bgra_to_bgr, yuv420_to_bgr};

    fn hash(image: &ImageU8) -> OpResult<u64> {
        Ok(prepare_input(image)?
            .iter()
            .flat_map(|v| v.to_le_bytes())
            .fold(0xcbf29ce484222325u64, |h, b| {
                (h ^ b as u64).wrapping_mul(0x100000001b3)
            }))
    }

    #[test]
    fn prepared_input_matches_pre_rewrite_golden_bits() -> OpResult<()> {
        for (w, h, expected) in [
            (1, 1, 0x194e6f7e1cf62325),
            (17, 39, 0x66f02b798fcce024),
            (301, 103, 0x70448e7edd3ec825),
            (256, 256, 0x6e6f7ff897d8c759),
            (1027, 769, 0x3872cf1d817be804),
        ] {
            let bytes = (0..w * h * 3)
                .map(|i| ((i * 71 + i / 17 * 19) % 256) as u8)
                .collect();
            assert_eq!(hash(&ImageU8::new(w, h, 3, bytes)?)?, expected);
        }
        Ok(())
    }

    #[test]
    fn camera_input_matches_pre_rewrite_golden_bits() -> OpResult<()> {
        let (w, h, stride) = (37, 21, 37 * 4 + 13);
        let bgra = (0..stride * h)
            .map(|i| ((i * 97 + i / 11 * 37) % 256) as u8)
            .collect::<Vec<_>>();
        assert_eq!(
            hash(&bgra_to_bgr(&bgra, stride, w, h)?)?,
            0xa01f90e4cc066c9c
        );
        for (step, expected) in [(1, 0xbd51f44eacc387b7), (2, 0x8078d82c5cf79ac1)] {
            let ys = 42;
            let uvs = 19 * step + 7;
            let y = (0..ys * h)
                .map(|i| ((i * 37 + i / 9) % 256) as u8)
                .collect::<Vec<_>>();
            let u = (0..uvs * 11)
                .map(|i| ((i * 13 + 75) % 256) as u8)
                .collect::<Vec<_>>();
            let v = (0..uvs * 11)
                .map(|i| ((i * 23 + 101) % 256) as u8)
                .collect::<Vec<_>>();
            let layout = PlaneLayout {
                width: w,
                height: h,
                y_row_stride: ys,
                uv_row_stride: uvs,
                uv_pixel_stride: step,
            };
            assert_eq!(
                hash(&yuv420_to_bgr(&y, &u, &v, layout, 256, 256)?)?,
                expected
            );
        }
        Ok(())
    }

    #[test]
    fn probabilities_reject_non_finite_and_bad_shape() {
        assert!(ProbabilityMap::new(vec![f32::NAN], 1, 1).is_err());
        assert!(ProbabilityMap::new(vec![f32::INFINITY], 1, 1).is_err());
        assert!(ProbabilityMap::new(vec![0.0], 2, 2).is_err());
        assert!(ProbabilityMap::new(vec![], 0, 0).is_err());
    }
}

#[cfg(test)]
mod model_parity_tests {
    use super::*;

    #[test]
    #[ignore = "requires ENTE_SCAN_MODEL and ENTE_SCAN_INPUT_GOLDENS"]
    fn golden_tensor_bytes_and_same_provider_outputs_match() -> OpResult<()> {
        let model = std::env::var("ENTE_SCAN_MODEL").map_err(|e| e.to_string())?;
        let directory = std::env::var("ENTE_SCAN_INPUT_GOLDENS").map_err(|e| e.to_string())?;
        let segmenter = Segmenter::new(&model).map_err(|e| e.to_string())?;
        for (w, h) in [(1, 1), (17, 39), (301, 103), (256, 256), (1027, 769)] {
            let data = (0..w * h * 3)
                .map(|i| ((i * 71 + i / 17 * 19) % 256) as u8)
                .collect();
            let prepared = prepare_input(&ImageU8::new(w, h, 3, data)?)?;
            let golden_bytes =
                std::fs::read(format!("{directory}/bgr-{w}-{h}.f32")).map_err(|e| e.to_string())?;
            let actual_bytes: Vec<u8> = prepared.iter().flat_map(|v| v.to_le_bytes()).collect();
            assert_eq!(actual_bytes, golden_bytes);
            let golden = golden_bytes
                .as_chunks::<4>()
                .0
                .iter()
                .map(|&b| f32::from_le_bytes(b))
                .collect();
            let expected = segmenter.infer(golden)?;
            let actual = segmenter.infer(prepared)?;
            assert_eq!(actual, expected);
            println!(
                "same-provider input/output parity {w}x{h}: {} float samples",
                actual.len()
            );
        }
        Ok(())
    }
}

#[cfg(test)]
impl Segmenter {
    pub(super) fn unavailable_for_render_tests() -> Self {
        Self {
            session: Mutex::new(OnnxSession::new(
                "/nonexistent/document-segmentation.onnx",
                MODEL_NAMESPACE,
                ExecutionMode::PlatformDefault,
            )),
        }
    }
}
