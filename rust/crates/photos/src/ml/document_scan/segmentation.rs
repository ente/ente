//! ONNX segmentation: BGR image -> 256x256 u8 probability map.
//!
//! Preprocessing contract: BGR -> RGB -> resize 256x256 (INTER_LINEAR) ->
//! f32 (x-127.5)/127.5 -> NHWC [1,256,256,3] -> model -> clip [0,1] ->
//! round(p*255) u8.

use std::sync::Mutex;

use ort::ep::CPU;
use ort::session::Session;
use ort::session::builder::GraphOptimizationLevel;
use ort::value::TensorRef;

use super::OpResult;
use super::image::{ImageRef, ImageU8};
use super::ops;
use super::scanner::ScanError;

pub const MASK_SIDE: i32 = 256;

pub(crate) struct Segmenter {
    // `Session::run` needs `&mut self`; the lock keeps the scanner session
    // usable through `&self` and Send + Sync.
    session: Mutex<Session>,
}

impl Segmenter {
    /// Loads the segmentation model with a plain CPU execution provider: the
    /// model is tiny (256x256 input) and CPU execution keeps the discontinuous
    /// downstream pipeline deterministic across devices.
    pub(crate) fn new(model_path: &str) -> Result<Self, ScanError> {
        let build = || -> Result<Session, ort::Error> {
            Session::builder()?
                .with_optimization_level(GraphOptimizationLevel::All)?
                .with_intra_threads(1)?
                .with_inter_threads(1)?
                .with_execution_providers([CPU::default().with_arena_allocator(true).build()])?
                .commit_from_file(model_path)
        };
        let session = build().map_err(|err| ScanError::ModelLoad(err.to_string()))?;
        if session.inputs().len() != 1 {
            return Err(ScanError::ModelLoad(format!(
                "expected exactly 1 model input, got {}",
                session.inputs().len()
            )));
        }
        Ok(Self {
            session: Mutex::new(session),
        })
    }

    /// Returns the 256x256 u8 probability map, row-major.
    pub(crate) fn probability_map_u8(&self, bgr: &ImageU8) -> OpResult<Vec<u8>> {
        let rgb = ops::cvt_color_bgr_rgb(bgr)?;
        let resized =
            ops::resize_inter_linear(ImageRef::U8(&rgb), MASK_SIDE, MASK_SIDE)?.into_u8()?;

        let input: Vec<f32> = resized
            .data
            .iter()
            .map(|&v| (v as f32 - 127.5) / 127.5)
            .collect();

        let side = MASK_SIDE as i64;
        let mut session = match self.session.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        let mut run = || -> Result<Vec<f32>, String> {
            let tensor = TensorRef::<f32>::from_array_view(([1i64, side, side, 3], &input[..]))
                .map_err(|err| err.to_string())?;
            let outputs = session
                .run(ort::inputs![tensor])
                .map_err(|err| err.to_string())?;
            if outputs.len() == 0 {
                return Err("model produced no outputs".to_string());
            }
            let (shape, data) = outputs[0]
                .try_extract_tensor::<f32>()
                .map_err(|err| err.to_string())?;
            let expected = (MASK_SIDE * MASK_SIDE) as usize;
            if data.len() != expected {
                return Err(format!("unexpected model output shape {shape:?}"));
            }
            Ok(data.to_vec())
        };
        let data = run()?;

        // clip(p, 0, 1) with NO sigmoid, then round(p*255) with
        // round-half-to-even semantics.
        Ok(data
            .iter()
            .map(|&v| (v.clamp(0.0, 1.0) * 255.0).round_ties_even() as u8)
            .collect())
    }
}
