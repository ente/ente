use std::path::{Path, PathBuf};
use std::sync::{Mutex, MutexGuard, PoisonError};

use super::graph_cache::{GRAPHS, GraphCache, LoadPlan, SOURCES};
use super::parakeet::{Parakeet, Transcript};
use super::vad::Vad;
use crate::transcription::audio::extract_speech_from_pcm16;
use crate::transcription::{Result, TranscriptionError};

pub struct Transcriber {
    model_dir: PathBuf,
    vad_model_path: PathBuf,
    loaded: Mutex<Option<Parakeet>>,
    graph_cache: Option<GraphCache>,
}

impl Transcriber {
    pub(crate) fn live_vad(&self) -> crate::voice::Result<Box<dyn Vad>> {
        let metadata = std::fs::metadata(&self.vad_model_path).map_err(|error| {
            if error.kind() == std::io::ErrorKind::NotFound {
                crate::voice::VoiceError::VadNotDownloaded
            } else {
                super::voice_error("Read voice activity model", error)
            }
        })?;
        if !metadata.is_file() {
            return Err(crate::voice::VoiceError::VadNotDownloaded);
        }
        super::SileroV4Vad::new(&self.vad_model_path, 0.3)
            .map(|vad| Box::new(vad) as Box<dyn Vad>)
            .map_err(|error| super::voice_error("Load voice activity model", error))
    }

    pub(crate) fn transcribe_window(
        &self,
        samples: &[f32],
        mut is_cancelled: impl FnMut() -> bool,
    ) -> crate::voice::Result<Vec<crate::voice::AlignedWord>> {
        use crate::voice::{MAX_WINDOW_SAMPLES, VoiceError};
        if is_cancelled() {
            return Err(VoiceError::Cancelled);
        }
        if samples.is_empty()
            || samples.len() > MAX_WINDOW_SAMPLES
            || samples.iter().any(|s| !s.is_finite())
        {
            return Err(VoiceError::InvalidAudio("Recognition requires a nonempty window of finite samples within the duration limit".into()));
        }
        let mut loaded = self.lock();
        let model = ensure_loaded(
            &mut loaded,
            &self.model_dir,
            self.graph_cache.as_ref(),
            true,
        )
        .map_err(|error| super::voice_error("Load transcription model", error))?;
        let result = decode_window(model, samples, &mut is_cancelled)
            .map_err(|error| super::voice_error("Transcribe live audio", error))?
            .ok_or(VoiceError::Cancelled)?;
        aligned_words(result, samples.len())
    }

    pub fn new(model_dir: impl Into<PathBuf>, vad_model_path: impl Into<PathBuf>) -> Self {
        Self {
            model_dir: model_dir.into(),
            vad_model_path: vad_model_path.into(),
            loaded: Mutex::new(None),
            graph_cache: None,
        }
    }

    pub fn with_cache(
        model_dir: impl Into<PathBuf>,
        vad_model_path: impl Into<PathBuf>,
        cache_directory: impl Into<PathBuf>,
        device_identity: String,
    ) -> Self {
        let mut transcriber = Self::new(model_dir, vad_model_path);
        transcriber.graph_cache = Some(GraphCache::new(cache_directory.into(), device_identity));
        transcriber
    }

    pub fn load_model(&self) -> Result<()> {
        if !self.model_dir.is_dir() {
            return Err(TranscriptionError::NotDownloaded);
        }
        ensure_loaded(
            &mut self.lock(),
            &self.model_dir,
            self.graph_cache.as_ref(),
            true,
        )?;
        Ok(())
    }

    pub fn unload_model(&self) {
        *self.lock() = None;
    }

    pub fn transcribe(&self, input_sample_rate: u32, pcm_le: &[u8]) -> Result<String> {
        if pcm_le.is_empty() {
            return Ok(String::new());
        }
        if !self.model_dir.is_dir() {
            return Err(TranscriptionError::NotDownloaded);
        }
        if !self.vad_model_path.is_file() {
            return Err(TranscriptionError::VadNotDownloaded);
        }
        let speech = extract_speech_from_pcm16(&self.vad_model_path, input_sample_rate, pcm_le)?;
        if speech.is_empty() {
            return Ok(String::new());
        }
        let mut loaded = self.lock();
        let model = ensure_loaded(
            &mut loaded,
            &self.model_dir,
            self.graph_cache.as_ref(),
            true,
        )?;
        let result = model.transcribe(&speech)?;
        Ok(super::text::filter_transcription_output(&result.text))
    }

    pub(crate) fn transcribe_tail(
        &self,
        pcm_le: &[u8],
        mut is_cancelled: impl FnMut() -> bool,
    ) -> crate::voice::Result<Vec<crate::voice::AlignedWord>> {
        use crate::voice::VoiceError;

        if is_cancelled() {
            return Err(VoiceError::Cancelled);
        }
        let samples = super::audio::pcm16_samples(pcm_le)
            .map_err(|error| super::voice_error("Read recorded audio", error))?;
        if samples.is_empty() || samples.len() > super::MAX_RECORDED_WINDOW_SAMPLES {
            return Err(VoiceError::InvalidAudio(
                "Recorded audio exceeds the recognition window".into(),
            ));
        }
        let mut loaded = self.lock();
        let model = ensure_loaded(
            &mut loaded,
            &self.model_dir,
            self.graph_cache.as_ref(),
            false,
        )
        .map_err(|error| super::voice_error("Load transcription model", error))?;
        let result = decode_window(model, &samples, &mut is_cancelled)
            .map_err(|error| super::voice_error("Transcribe recorded audio", error))?
            .ok_or(VoiceError::Cancelled)?;
        aligned_words(result, samples.len())
    }

    fn lock(&self) -> MutexGuard<'_, Option<Parakeet>> {
        self.loaded.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

fn decode_window(
    model: &mut Parakeet,
    samples: &[f32],
    is_cancelled: &mut impl FnMut() -> bool,
) -> Result<Option<Transcript>> {
    if is_cancelled() {
        return Ok(None);
    }
    let mut result = model.transcribe(samples)?;
    if is_cancelled() {
        return Ok(None);
    }
    let maximum = if samples.len() <= crate::voice::MAX_WINDOW_SAMPLES {
        crate::voice::MAX_WINDOW_SAMPLES
    } else {
        super::MAX_RECORDED_WINDOW_SAMPLES
    };
    let padding = (maximum - samples.len()).min(super::ENDPOINT_PADDING_SAMPLES);
    if result.text.trim().is_empty() && padding > 0 {
        let mut padded = Vec::with_capacity(samples.len() + padding);
        padded.extend_from_slice(samples);
        padded.resize(samples.len() + padding, 0.0);
        result = model.transcribe(&padded)?;
    }
    Ok((!is_cancelled()).then_some(result))
}

fn aligned_words(
    result: Transcript,
    samples: usize,
) -> crate::voice::Result<Vec<crate::voice::AlignedWord>> {
    use crate::voice::{AlignedWord, VoiceError};
    result
        .words
        .into_iter()
        .map(|word| {
            if !word.start.is_finite()
                || !word.end.is_finite()
                || word.end < word.start
                || word.start * 16000.0 > samples as f32
            {
                return Err(VoiceError::UnstableTranscript);
            }
            Ok(AlignedWord {
                text: word.text,
                start: (word.start.max(0.0) * 16000.0).round() as u64,
                end: ((word.end.max(0.0) * 16000.0).round() as u64).min(samples as u64),
            })
        })
        .collect()
}

fn ensure_loaded<'a>(
    loaded: &'a mut Option<Parakeet>,
    model_dir: &Path,
    cache: Option<&GraphCache>,
    may_build: bool,
) -> Result<&'a mut Parakeet> {
    match loaded {
        Some(model) => Ok(model),
        slot => {
            for name in SOURCES {
                if !model_dir.join(name).is_file() {
                    return Err(TranscriptionError::NotDownloaded);
                }
            }
            let result = if let Some(cache) = cache {
                let configuration = format!(
                    "{};cpu;parallel=true;intra=auto;threads={}",
                    ort::info(),
                    std::thread::available_parallelism()
                        .map(std::num::NonZeroUsize::get)
                        .unwrap_or(1)
                );
                cache.load(model_dir, &configuration, may_build, |plan| {
                    load_plan(model_dir, plan)
                })
            } else {
                load_plan(model_dir, LoadPlan::Source { save_to: None })
            };
            Ok(slot.insert(result?))
        }
    }
}

fn load_plan(model_dir: &Path, plan: LoadPlan<'_>) -> Result<Parakeet> {
    use ort::session::builder::{AutoDevicePolicy, GraphOptimizationLevel};
    let directory = match plan {
        LoadPlan::Source { save_to: None } => model_dir,
        LoadPlan::Cached { directory } => directory,
        LoadPlan::Source {
            save_to: Some(directory),
        } => {
            let environment = super::environment()?;
            for name in GRAPHS {
                let session = ort::session::Session::builder(&environment)?
                    .with_auto_device(AutoDevicePolicy::PreferCPU)?
                    .with_optimization_level(GraphOptimizationLevel::Level3)?
                    .with_optimized_model_path(directory.join(name))?
                    .with_parallel_execution(true)?
                    .with_execution_providers([ort::ep::CPU::default().build()])?
                    .commit_from_file(model_dir.join(name))?;
                drop(session);
            }
            directory
        }
    };
    Parakeet::load(directory)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_quantized_graph_never_falls_back_to_full_precision() {
        let directory = tempfile::tempdir().unwrap();
        for name in [
            "encoder-model.onnx",
            "decoder_joint-model.onnx",
            "nemo128.onnx",
            "vocab.txt",
        ] {
            std::fs::write(directory.path().join(name), b"not a model").unwrap();
        }
        let transcriber = Transcriber::new(directory.path(), directory.path().join("vad.onnx"));
        assert!(matches!(
            transcriber.load_model(),
            Err(TranscriptionError::NotDownloaded)
        ));
    }

    #[test]
    #[ignore = "requires ENSU_TEST_TRANSCRIPTION_MODEL"]
    fn quantized_model_loads_from_source_and_cached_graphs() {
        let model_dir = PathBuf::from(std::env::var("ENSU_TEST_TRANSCRIPTION_MODEL").unwrap());
        let transcriber = Transcriber::new(&model_dir, model_dir.join("vad.onnx"));
        transcriber.load_model().unwrap();
        assert!(transcriber.lock().is_some());
        transcriber.unload_model();

        let directory = tempfile::tempdir().unwrap();
        let cache = GraphCache::new(directory.path().to_path_buf(), "test-device".into());
        for cached in [false, true] {
            let model = cache
                .load(&model_dir, ort::info(), true, |plan| {
                    match &plan {
                        LoadPlan::Source { save_to } => {
                            assert!(!cached);
                            assert!(save_to.is_some());
                        }
                        LoadPlan::Cached { .. } => assert!(cached),
                    }
                    load_plan(&model_dir, plan)
                })
                .unwrap();
            drop(model);
        }
    }
}
