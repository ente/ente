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

    pub(crate) fn probability_map_u8(&self, bgr: &ImageU8) -> OpResult<Vec<u8>> {
        if bgr.channels != 3 {
            return Err(format!(
                "probability_map_u8: expected a 3-channel image, got {}",
                bgr.channels
            ));
        }
        let resized = cv::resize_u8(bgr, MASK_SIDE, MASK_SIDE, cv::Interp::Bilinear)?;

        let mut input = vec![0.0f32; resized.data.len()];
        for (out, px) in input.chunks_exact_mut(3).zip(resized.data.chunks_exact(3)) {
            out[0] = (px[2] as f32 - 127.5) / 127.5;
            out[1] = (px[1] as f32 - 127.5) / 127.5;
            out[2] = (px[0] as f32 - 127.5) / 127.5;
        }

        let data = self.infer(input)?;

        Ok(data
            .iter()
            .map(|&v| (v.clamp(0.0, 1.0) * 255.0).round_ties_even() as u8)
            .collect())
    }
}
