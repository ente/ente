use crate::error::MlResult;
use crate::onnx::{
    ExecutionMode, GpuOptions, OnnxSession, ProviderUsage, SessionHandle, SessionRunResult,
};

#[derive(Clone, Copy)]
pub(super) enum OcrModel {
    Detection,
    Classification,
    Recognition,
}

pub(super) struct OcrSession {
    session: OnnxSession,
}

impl OcrSession {
    pub(super) fn new(model_path: &str, model: OcrModel) -> Self {
        let namespace = match model {
            OcrModel::Detection => "ocr-detection-fixed-v1",
            OcrModel::Classification => "ocr-classification-fixed-v1",
            OcrModel::Recognition => "ocr-recognition-fixed-v1",
        };
        let options = GpuOptions {
            subgraphs: !matches!(model, OcrModel::Classification),
            #[cfg(any(target_os = "android", target_os = "linux", target_os = "windows"))]
            prefer_nhwc: matches!(model, OcrModel::Detection),
        };
        Self {
            session: OnnxSession::new(model_path, namespace, ExecutionMode::GpuPreferred)
                .with_gpu_options(options)
                .with_unvalidated_acceleration(),
        }
    }

    pub(super) fn run<T>(
        &mut self,
        operation: impl FnMut(&mut SessionHandle) -> SessionRunResult<T>,
    ) -> MlResult<(T, ProviderUsage)> {
        self.session.run(operation)
    }
}
