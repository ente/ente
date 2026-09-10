use std::collections::VecDeque;

use crate::error::{MlError, MlResult};
use crate::onnx::{
    ExecutionMode, GpuOptions, OnnxSession, ProviderUsage, SessionHandle, SessionRunResult,
};

#[derive(Clone, Copy)]
pub(super) enum OcrModel {
    Detection,
    Classification,
    Recognition,
}

impl OcrModel {
    fn cache_capacity(self) -> usize {
        match self {
            Self::Detection => 2,
            Self::Classification => 6,
            Self::Recognition => 8,
        }
    }

    fn namespace(self) -> &'static str {
        match self {
            Self::Detection => "ocr-detection",
            Self::Classification => "ocr-classification",
            Self::Recognition => "ocr-recognition",
        }
    }

    fn mode(self) -> ExecutionMode {
        if matches!(self, Self::Classification)
            && !cfg!(any(target_os = "ios", target_os = "macos"))
        {
            ExecutionMode::CpuOnly
        } else {
            ExecutionMode::GpuPreferred
        }
    }

    fn gpu_options(self, [count, _, height, width]: [i64; 4]) -> GpuOptions {
        let dimensions = match self {
            Self::Detection => vec![
                ("DynamicDimension.0", count),
                ("DynamicDimension.1", height),
                ("DynamicDimension.2", width),
            ],
            Self::Classification => vec![
                ("p2o.DynamicDimension.0", count),
                ("p2o.DynamicDimension.1", height),
                ("p2o.DynamicDimension.2", width),
            ],
            Self::Recognition => vec![("DynamicDimension.0", count), ("DynamicDimension.1", width)],
        };
        GpuOptions {
            dimensions,
            #[cfg(any(target_os = "android", target_os = "linux", target_os = "windows"))]
            prefer_nhwc: matches!(self, Self::Detection),
        }
    }
}

pub(super) struct OcrSession {
    model_path: String,
    model: OcrModel,
    sessions: VecDeque<([i64; 4], OnnxSession)>,
}

impl OcrSession {
    pub(super) fn new(model_path: &str, model: OcrModel) -> Self {
        Self {
            model_path: model_path.to_owned(),
            model,
            sessions: VecDeque::new(),
        }
    }

    pub(super) fn run<T>(
        &mut self,
        shape: [i64; 4],
        operation: impl FnMut(&mut SessionHandle) -> SessionRunResult<T>,
    ) -> MlResult<(T, ProviderUsage)> {
        self.session_for(shape)?.run(operation)
    }

    fn session_for(&mut self, shape: [i64; 4]) -> MlResult<&mut OnnxSession> {
        let mode = self.model.mode();
        let key = if mode == ExecutionMode::CpuOnly {
            [0; 4]
        } else {
            shape
        };
        if let Some(index) = self.sessions.iter().position(|(cached, _)| *cached == key) {
            self.sessions.make_contiguous()[..=index].rotate_right(1);
        } else {
            if self.sessions.len() == self.model.cache_capacity() {
                self.sessions.pop_back();
            }
            let [n, c, h, w] = key;
            let namespace = format!("{}-{n}x{c}x{h}x{w}-gpu-f32-v1", self.model.namespace());
            let mut session = OnnxSession::new(&self.model_path, &namespace, mode);
            if mode == ExecutionMode::GpuPreferred {
                session = session
                    .with_gpu_options(self.model.gpu_options(shape))
                    .with_unvalidated_acceleration();
            }
            self.sessions.push_front((key, session));
        }
        self.sessions
            .front_mut()
            .map(|(_, session)| session)
            .ok_or_else(|| MlError::Runtime("OCR session cache is empty".to_owned()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reuses_shapes_and_evicts_the_least_recently_used_session() {
        let mut cache = OcrSession::new("rec.onnx", OcrModel::Recognition);
        let first = [6, 3, 48, 320];
        cache.session_for(first).unwrap().initialize_load_state();
        for width in 321..328 {
            cache.session_for([6, 3, 48, width]).unwrap();
        }
        assert!(cache.session_for(first).unwrap().has_load_state());
        cache.session_for([1, 3, 48, 320]).unwrap();
        assert_eq!(cache.sessions.len(), OcrModel::Recognition.cache_capacity());
        assert!(cache.session_for(first).unwrap().has_load_state());
        assert!(
            !cache
                .sessions
                .iter()
                .any(|(shape, _)| *shape == [6, 3, 48, 321])
        );
    }

    #[test]
    fn models_override_their_actual_spatial_dimensions() {
        assert_eq!(
            OcrModel::Detection.gpu_options([1, 3, 960, 704]).dimensions,
            vec![
                ("DynamicDimension.0", 1),
                ("DynamicDimension.1", 960),
                ("DynamicDimension.2", 704)
            ]
        );
        assert_eq!(
            OcrModel::Recognition
                .gpu_options([3, 3, 48, 641])
                .dimensions,
            vec![("DynamicDimension.0", 3), ("DynamicDimension.1", 641)]
        );
        assert_eq!(
            OcrModel::Classification
                .gpu_options([3, 3, 48, 192])
                .dimensions,
            vec![
                ("p2o.DynamicDimension.0", 3),
                ("p2o.DynamicDimension.1", 48),
                ("p2o.DynamicDimension.2", 192)
            ]
        );
    }
}
