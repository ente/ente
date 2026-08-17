use std::{
    collections::HashMap,
    sync::{
        Arc, Condvar, Mutex, MutexGuard,
        atomic::{AtomicU64, Ordering},
    },
    time::{Duration, Instant},
};

use once_cell::sync::Lazy;

use super::error::{MlError, MlResult};

const SLOW_ANALYSIS_THRESHOLD: Duration = Duration::from_secs(60);

static NEXT_ANALYSIS_ID: AtomicU64 = AtomicU64::new(0);
static ANALYSIS_MONITOR: Lazy<Arc<AnalysisMonitor>> = Lazy::new(|| {
    let monitor = Arc::new(AnalysisMonitor::new(SLOW_ANALYSIS_THRESHOLD));
    let worker = Arc::clone(&monitor);
    if let Err(error) = std::thread::Builder::new()
        .name("ente-ml-watchdog".to_string())
        .spawn(move || worker.run())
    {
        log::error!("failed to start ML analysis watchdog: {error}");
    }
    monitor
});

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct AnalysisContext {
    pub(crate) file_id: i64,
    pub(crate) run_faces: bool,
    pub(crate) run_clip: bool,
    pub(crate) run_pets: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum AnalysisStage {
    ValidateRequest,
    RuntimeSetup,
    DecodeImage,
    YoloPreprocess,
    FaceDetection,
    FaceAlignment,
    FaceEmbedding,
    FaceCrops,
    ClipEmbedding,
    PetFaceDetection,
    PetBodyDetection,
    PetFaceAlignment,
    PetFaceEmbedding,
    PetBodyEmbedding,
    Finalize,
}

impl AnalysisStage {
    fn label(self) -> &'static str {
        match self {
            Self::ValidateRequest => "validate_request",
            Self::RuntimeSetup => "runtime_setup",
            Self::DecodeImage => "decode_image",
            Self::YoloPreprocess => "yolo_preprocess",
            Self::FaceDetection => "face_detection",
            Self::FaceAlignment => "face_alignment",
            Self::FaceEmbedding => "face_embedding",
            Self::FaceCrops => "face_crops",
            Self::ClipEmbedding => "clip_embedding",
            Self::PetFaceDetection => "pet_face_detection",
            Self::PetBodyDetection => "pet_body_detection",
            Self::PetFaceAlignment => "pet_face_alignment",
            Self::PetFaceEmbedding => "pet_face_embedding",
            Self::PetBodyEmbedding => "pet_body_embedding",
            Self::Finalize => "finalize",
        }
    }
}

pub(crate) struct AnalysisOperation {
    id: u64,
    context: AnalysisContext,
    stage: AnalysisStage,
    started_at: Instant,
    finished: bool,
}

impl AnalysisOperation {
    pub(crate) fn start(context: AnalysisContext) -> Self {
        let id = NEXT_ANALYSIS_ID.fetch_add(1, Ordering::Relaxed);
        let started_at = Instant::now();
        let stage = AnalysisStage::ValidateRequest;
        ANALYSIS_MONITOR.register(id, context, stage, started_at);
        Self {
            id,
            context,
            stage,
            started_at,
            finished: false,
        }
    }

    pub(crate) fn set_stage(&mut self, stage: AnalysisStage) {
        self.stage = stage;
        ANALYSIS_MONITOR.update_stage(self.id, stage);
    }

    pub(crate) fn finish<T>(&mut self, result: &MlResult<T>) {
        let completed_at = Instant::now();
        let active = ANALYSIS_MONITOR.complete(self.id);
        self.finished = true;
        let elapsed = completed_at.duration_since(self.started_at);
        let watchdog_reported = active.is_some_and(|analysis| analysis.slow_reported);

        if let Err(error) = result {
            log_analysis_error(
                "analyze_image",
                Some(self.context),
                Some(self.stage),
                elapsed,
                error,
            );
        } else if elapsed >= SLOW_ANALYSIS_THRESHOLD {
            let level = if watchdog_reported {
                log::Level::Info
            } else {
                log::Level::Warn
            };
            log::log!(
                level,
                "Rust ML slow operation: operation=analyze_image event=completed file_id={} stage={} elapsed_ms={} run_faces={} run_clip={} run_pets={}",
                self.context.file_id,
                self.stage.label(),
                elapsed.as_millis(),
                self.context.run_faces,
                self.context.run_clip,
                self.context.run_pets,
            );
        }
    }
}

impl Drop for AnalysisOperation {
    fn drop(&mut self) {
        if self.finished {
            return;
        }
        ANALYSIS_MONITOR.complete(self.id);
        let elapsed = self.started_at.elapsed();
        if elapsed >= SLOW_ANALYSIS_THRESHOLD {
            log::warn!(
                "Rust ML slow operation: operation=analyze_image event=ended_without_result file_id={} stage={} elapsed_ms={} run_faces={} run_clip={} run_pets={}",
                self.context.file_id,
                self.stage.label(),
                elapsed.as_millis(),
                self.context.run_faces,
                self.context.run_clip,
                self.context.run_pets,
            );
        }
    }
}

pub(crate) fn log_public_ml_error(operation: &'static str, error: &MlError) {
    log_analysis_error(operation, None, None, Duration::ZERO, error);
}

fn log_analysis_error(
    operation: &'static str,
    context: Option<AnalysisContext>,
    stage: Option<AnalysisStage>,
    elapsed: Duration,
    error: &MlError,
) {
    let context = context.map_or_else(String::new, |context| {
        format!(
            " file_id={} run_faces={} run_clip={} run_pets={}",
            context.file_id, context.run_faces, context.run_clip, context.run_pets
        )
    });
    let stage = stage.map_or_else(String::new, |stage| format!(" stage={}", stage.label()));
    let elapsed = if elapsed != Duration::ZERO {
        format!(" elapsed_ms={}", elapsed.as_millis())
    } else {
        String::new()
    };
    let message = format!(
        "Rust ML operation failed: operation={operation}{context}{stage}{elapsed} error_kind={} error={error}",
        error_kind(error)
    );

    match error {
        MlError::Decode(_) | MlError::Image(_) => log::warn!("{message}"),
        MlError::InvalidRequest(_)
        | MlError::Preprocess(_)
        | MlError::Ort(_)
        | MlError::CorruptModel(_)
        | MlError::Postprocess(_)
        | MlError::Runtime(_) => log::error!("{message}"),
    }
}

fn error_kind(error: &MlError) -> &'static str {
    match error {
        MlError::InvalidRequest(_) => "invalid_request",
        MlError::Decode(_) => "decode",
        MlError::Image(_) => "image",
        MlError::Preprocess(_) => "preprocess",
        MlError::Ort(_) => "ort",
        MlError::CorruptModel(_) => "corrupt_model",
        MlError::Postprocess(_) => "postprocess",
        MlError::Runtime(_) => "runtime",
    }
}

struct AnalysisMonitor {
    threshold: Duration,
    state: Mutex<MonitorState>,
    changed: Condvar,
}

impl AnalysisMonitor {
    fn new(threshold: Duration) -> Self {
        Self {
            threshold,
            state: Mutex::new(MonitorState::default()),
            changed: Condvar::new(),
        }
    }

    fn register(
        &self,
        id: u64,
        context: AnalysisContext,
        stage: AnalysisStage,
        started_at: Instant,
    ) {
        self.lock_state().register(id, context, stage, started_at);
        self.changed.notify_one();
    }

    fn update_stage(&self, id: u64, stage: AnalysisStage) {
        let should_wake = self.lock_state().update_stage(id, stage);
        if should_wake {
            self.changed.notify_one();
        }
    }

    fn complete(&self, id: u64) -> Option<ActiveAnalysis> {
        let active = self.lock_state().complete(id);
        self.changed.notify_one();
        active
    }

    fn run(&self) {
        let mut state = self.lock_state();
        loop {
            let now = Instant::now();
            let events = state.collect_events(now, self.threshold);
            if !events.is_empty() {
                drop(state);
                for event in events {
                    event.log();
                }
                state = self.lock_state();
                continue;
            }

            state = match state.next_wait(now, self.threshold) {
                Some(wait) => match self.changed.wait_timeout(state, wait) {
                    Ok((state, _)) => state,
                    Err(poisoned) => poisoned.into_inner().0,
                },
                None => match self.changed.wait(state) {
                    Ok(state) => state,
                    Err(poisoned) => poisoned.into_inner(),
                },
            };
        }
    }

    fn lock_state(&self) -> MutexGuard<'_, MonitorState> {
        self.state
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }
}

#[derive(Default)]
struct MonitorState {
    active: HashMap<u64, ActiveAnalysis>,
}

impl MonitorState {
    fn register(
        &mut self,
        id: u64,
        context: AnalysisContext,
        stage: AnalysisStage,
        started_at: Instant,
    ) {
        self.active.insert(
            id,
            ActiveAnalysis {
                context,
                started_at,
                stage,
                slow_reported: false,
                last_reported_stage: None,
            },
        );
    }

    fn update_stage(&mut self, id: u64, stage: AnalysisStage) -> bool {
        let Some(active) = self.active.get_mut(&id) else {
            return false;
        };
        active.stage = stage;
        active.slow_reported && active.last_reported_stage != Some(stage)
    }

    fn complete(&mut self, id: u64) -> Option<ActiveAnalysis> {
        self.active.remove(&id)
    }

    fn collect_events(&mut self, now: Instant, threshold: Duration) -> Vec<SlowAnalysisEvent> {
        let mut events = Vec::new();
        for active in self.active.values_mut() {
            if !active.slow_reported
                && now.saturating_duration_since(active.started_at) >= threshold
            {
                active.slow_reported = true;
                active.last_reported_stage = Some(active.stage);
                events.push(active.event(SlowEventKind::ThresholdExceeded, now));
            } else if active.slow_reported && active.last_reported_stage != Some(active.stage) {
                active.last_reported_stage = Some(active.stage);
                events.push(active.event(SlowEventKind::StageChanged, now));
            }
        }
        events
    }

    fn next_wait(&self, now: Instant, threshold: Duration) -> Option<Duration> {
        self.active
            .values()
            .filter(|active| !active.slow_reported)
            .map(|active| {
                threshold.saturating_sub(now.saturating_duration_since(active.started_at))
            })
            .min()
    }
}

struct ActiveAnalysis {
    context: AnalysisContext,
    started_at: Instant,
    stage: AnalysisStage,
    slow_reported: bool,
    last_reported_stage: Option<AnalysisStage>,
}

impl ActiveAnalysis {
    fn event(&self, kind: SlowEventKind, now: Instant) -> SlowAnalysisEvent {
        SlowAnalysisEvent {
            kind,
            context: self.context,
            stage: self.stage,
            elapsed: now.saturating_duration_since(self.started_at),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum SlowEventKind {
    ThresholdExceeded,
    StageChanged,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct SlowAnalysisEvent {
    kind: SlowEventKind,
    context: AnalysisContext,
    stage: AnalysisStage,
    elapsed: Duration,
}

impl SlowAnalysisEvent {
    fn log(self) {
        let message = format!(
            "file_id={} stage={} elapsed_ms={} run_faces={} run_clip={} run_pets={}",
            self.context.file_id,
            self.stage.label(),
            self.elapsed.as_millis(),
            self.context.run_faces,
            self.context.run_clip,
            self.context.run_pets,
        );
        match self.kind {
            SlowEventKind::ThresholdExceeded => log::warn!(
                "Rust ML slow operation: operation=analyze_image event=threshold_exceeded threshold_ms={} {message}",
                SLOW_ANALYSIS_THRESHOLD.as_millis()
            ),
            SlowEventKind::StageChanged => {
                log::info!(
                    "Rust ML slow operation: operation=analyze_image event=stage_changed {message}"
                )
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn context(file_id: i64) -> AnalysisContext {
        AnalysisContext {
            file_id,
            run_faces: true,
            run_clip: true,
            run_pets: false,
        }
    }

    #[test]
    fn fast_analysis_emits_no_watchdog_events() {
        assert_eq!(SLOW_ANALYSIS_THRESHOLD, Duration::from_secs(60));
        let started_at = Instant::now();
        let mut state = MonitorState::default();
        state.register(1, context(42), AnalysisStage::DecodeImage, started_at);

        assert!(
            state
                .collect_events(
                    started_at + Duration::from_secs(59),
                    Duration::from_secs(60)
                )
                .is_empty()
        );
        assert!(!state.complete(1).unwrap().slow_reported);
    }

    #[test]
    fn slow_analysis_reports_current_and_later_stages_once() {
        let started_at = Instant::now();
        let threshold = Duration::from_secs(60);
        let mut state = MonitorState::default();
        state.register(1, context(42), AnalysisStage::FaceDetection, started_at);

        assert_eq!(
            state.collect_events(started_at + threshold, threshold),
            vec![SlowAnalysisEvent {
                kind: SlowEventKind::ThresholdExceeded,
                context: context(42),
                stage: AnalysisStage::FaceDetection,
                elapsed: threshold,
            }]
        );
        assert!(
            state
                .collect_events(started_at + threshold, threshold)
                .is_empty()
        );

        assert!(state.update_stage(1, AnalysisStage::FaceEmbedding));
        assert_eq!(
            state.collect_events(started_at + Duration::from_secs(61), threshold),
            vec![SlowAnalysisEvent {
                kind: SlowEventKind::StageChanged,
                context: context(42),
                stage: AnalysisStage::FaceEmbedding,
                elapsed: Duration::from_secs(61),
            }]
        );
        assert!(!state.update_stage(1, AnalysisStage::FaceEmbedding));
    }

    #[test]
    fn watchdog_waits_for_the_earliest_active_analysis() {
        let started_at = Instant::now();
        let threshold = Duration::from_secs(60);
        let mut state = MonitorState::default();
        state.register(1, context(1), AnalysisStage::DecodeImage, started_at);
        state.register(
            2,
            context(2),
            AnalysisStage::DecodeImage,
            started_at + Duration::from_secs(20),
        );

        assert_eq!(
            state.next_wait(started_at + Duration::from_secs(30), threshold),
            Some(Duration::from_secs(30))
        );
    }

    #[test]
    fn error_kinds_are_stable_for_log_filtering() {
        assert_eq!(error_kind(&MlError::Decode("bad image".into())), "decode");
        assert_eq!(error_kind(&MlError::Ort("failed".into())), "ort");
        assert_eq!(
            error_kind(&MlError::CorruptModel("model.onnx".into())),
            "corrupt_model"
        );
    }
}
