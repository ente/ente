mod runtime;

use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};
use std::time::{Duration, Instant};

use ente_assets::download::CancellationToken;
use ente_ensu::config::ModelRuntimeSurface;
use ente_ensu::llm::memory::{MemoryOperation, has_required_work_reserve, memory_budget};
use ente_ensu::transcription::{
    DictationState, LiveControl, LiveEvent, LiveTranscription, Transcriber,
};
use ente_ensu::{model, voice};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, Manager, State as TauriState, WebviewWindow, async_runtime};

use super::common::{ApiError, panic_message};
use super::llm;
use crate::platform;

#[derive(Default)]
pub struct State(Mutex<Option<Arc<Session>>>);

struct Session {
    id: String,
    window: String,
    started: AtomicBool,
    cancel: CancellationToken,
    dictation: Mutex<DictationState>,
    stream: Mutex<Option<Arc<LiveTranscription>>>,
    capturing: AtomicBool,
    level: AtomicU32,
    capture_error: Mutex<Option<String>>,
    next_chunk: Mutex<u64>,
}

impl Session {
    fn new(window: String) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            window,
            started: AtomicBool::new(false),
            cancel: CancellationToken::new(),
            dictation: Mutex::new(DictationState::new(true)),
            stream: Mutex::new(None),
            capturing: AtomicBool::new(false),
            level: AtomicU32::new(0),
            capture_error: Mutex::new(None),
            next_chunk: Mutex::new(0),
        }
    }

    fn check(&self) -> Result<(), ApiError> {
        if !self.cancel.is_cancelled() {
            return Ok(());
        }
        Err(match lock(&self.capture_error).as_deref() {
            Some(message) => error(message),
            None => ApiError::new("cancelled", "Voice input cancelled"),
        })
    }

    fn stop(&self, discard: bool) {
        self.capturing.store(false, Ordering::Release);
        if discard {
            self.cancel.cancel();
        }
        let mut state = lock(&self.dictation);
        let reason = if discard {
            voice::StopReason::Discard
        } else {
            voice::StopReason::Done
        };
        let _ = state.session.stop(reason);
        if let Some(stream) = lock(&self.stream).as_ref() {
            if discard {
                stream.cancel();
            } else {
                stream.finish();
            }
        }
    }

    fn feed(&self, sequence: u64, pcm: &[u8]) -> Result<bool, ApiError> {
        if !self.capturing.load(Ordering::Acquire) || self.cancel.is_cancelled() {
            return Ok(false);
        }
        if pcm.is_empty() || pcm.len() > 9600 || !pcm.len().is_multiple_of(2) {
            return Err(error("Invalid microphone audio chunk"));
        }
        let mut next = lock(&self.next_chunk);
        if sequence != *next {
            return Err(error("Microphone audio arrived out of order"));
        }
        let stream = lock(&self.stream);
        let Some(stream) = stream.as_ref() else {
            return Ok(false);
        };
        if stream.feed(pcm).map_err(error)? == voice::CaptureFeedResult::Closed {
            return Ok(false);
        }
        *next += 1;
        let peak = pcm
            .as_chunks::<2>()
            .0
            .iter()
            .map(|s| f32::from(i16::from_le_bytes([s[0], s[1]])).abs() / 32768.0)
            .fold(0.0_f32, f32::max);
        self.level.store(peak.to_bits(), Ordering::Relaxed);
        Ok(true)
    }

    fn capture_failed(&self, message: String) {
        *lock(&self.capture_error) = Some(message);
        self.capturing.store(false, Ordering::Release);
        let mut state = lock(&self.dictation);
        let _ = state.session.stop(voice::StopReason::Failure);
        if let Some(stream) = lock(&self.stream).as_ref() {
            stream.finish();
        } else {
            self.cancel.cancel();
        }
    }

    fn emit(&self, window: &WebviewWindow) {
        let state = lock(&self.dictation);
        let phase = match state.session.phase() {
            voice::VoicePhase::Preparing => "preparing",
            voice::VoicePhase::Listening => "listening",
            voice::VoicePhase::Countdown => "countdown",
            voice::VoicePhase::Finishing => "finishing",
            voice::VoicePhase::Ready => "ready",
            voice::VoicePhase::Closed => "closed",
        };
        let _ = window.emit(
            "voice-event",
            Event::Snapshot {
                id: &self.id,
                phase,
                text: state.text(),
                hypothesis: state.hypothesis(),
                level: f32::from_bits(self.level.load(Ordering::Relaxed)),
            },
        );
    }
}

fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex.lock().unwrap_or_else(PoisonError::into_inner)
}

fn error(error: impl std::fmt::Display) -> ApiError {
    ApiError::new("voice", error.to_string())
}

fn should_release_chat_model(preparing: bool) -> bool {
    let memory = platform::memory();
    let has_reserve = if preparing {
        let budget = memory_budget(
            ModelRuntimeSurface::Desktop,
            MemoryOperation::Voice,
            None,
            None,
        );
        memory
            .available
            .is_none_or(|bytes| bytes >= budget.required_bytes)
    } else {
        has_required_work_reserve(memory.available)
    };
    memory.pressure || !has_reserve
}

#[derive(Serialize, Clone)]
#[serde(tag = "type", rename_all = "camelCase")]
enum Event<'a> {
    Capture {
        id: &'a str,
        running: bool,
    },
    Progress {
        id: &'a str,
        percent: f64,
        status: String,
    },
    Snapshot {
        id: &'a str,
        phase: &'static str,
        text: &'a str,
        hypothesis: String,
        level: f32,
    },
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Outcome {
    text: String,
    incomplete: bool,
    warning: Option<String>,
}

#[tauri::command]
pub fn voice_unavailable_reason() -> Option<String> {
    runtime::unsupported_reason()
}

#[tauri::command]
pub fn voice_create(
    state: TauriState<'_, State>,
    window: WebviewWindow,
) -> Result<String, ApiError> {
    if let Some(reason) = runtime::unsupported_reason() {
        return Err(error(reason));
    }
    let mut active = lock(&state.0);
    if active.is_some() {
        return Err(ApiError::new(
            "voice_busy",
            "Voice input is still finishing",
        ));
    }
    let session = Arc::new(Session::new(window.label().to_owned()));
    let id = session.id.clone();
    *active = Some(session);
    Ok(id)
}

#[tauri::command]
pub fn voice_stop(state: TauriState<'_, State>, window: WebviewWindow, id: String, discard: bool) {
    let mut active = lock(&state.0);
    if let Some(session) = active
        .as_ref()
        .filter(|s| s.id == id && s.window == window.label())
    {
        session.stop(discard);
        if discard && !session.started.load(Ordering::Acquire) {
            *active = None;
        }
    }
}

pub fn microphone_allowed(app: &AppHandle, window: &str) -> bool {
    lock(&app.state::<State>().0)
        .as_ref()
        .is_some_and(|s| s.window == window && !s.cancel.is_cancelled())
}

fn owned_session(state: &State, window: &str, id: &str) -> Option<Arc<Session>> {
    lock(&state.0)
        .as_ref()
        .filter(|s| s.id == id && s.window == window)
        .cloned()
}

#[tauri::command]
pub fn voice_feed(
    state: TauriState<'_, State>,
    window: WebviewWindow,
    request: tauri::ipc::Request<'_>,
) -> Result<bool, ApiError> {
    let id = request
        .headers()
        .get("x-voice-session")
        .and_then(|h| h.to_str().ok())
        .ok_or_else(|| error("Missing voice session"))?;
    let Some(session) = owned_session(&state, window.label(), id) else {
        return Ok(false);
    };
    let sequence = request
        .headers()
        .get("x-voice-sequence")
        .and_then(|h| h.to_str().ok())
        .and_then(|s| s.parse().ok())
        .ok_or_else(|| error("Missing audio sequence"))?;
    let tauri::ipc::InvokeBody::Raw(pcm) = request.body() else {
        return Err(error("Expected PCM audio bytes"));
    };
    session.feed(sequence, pcm)
}

#[tauri::command]
pub fn voice_capture_failed(
    state: TauriState<'_, State>,
    window: WebviewWindow,
    id: String,
    message: String,
) {
    if let Some(session) = owned_session(&state, window.label(), &id) {
        session.capture_failed(message.chars().take(512).collect());
    }
}

pub fn clear_for_window(app: &AppHandle, window: Option<&str>) {
    let state = app.state::<State>();
    let mut active = lock(&state.0);
    if let Some(session) = active
        .as_ref()
        .filter(|s| window.is_none_or(|w| s.window == w))
    {
        session.stop(true);
        if !session.started.load(Ordering::Acquire) {
            *active = None;
        }
    }
}

struct ActiveRun<'a>(&'a State);
impl Drop for ActiveRun<'_> {
    fn drop(&mut self) {
        if let Some(session) = lock(&self.0.0).take() {
            session.stop(true);
        }
    }
}

#[tauri::command]
pub async fn voice_run(
    state: TauriState<'_, State>,
    llm_state: TauriState<'_, llm::State>,
    downloads: TauriState<'_, llm::ModelDownloadState>,
    window: WebviewWindow,
    id: String,
    sample_rate: u32,
) -> Result<Outcome, ApiError> {
    let session = {
        let active = lock(&state.0);
        let session = active
            .as_ref()
            .filter(|s| s.id == id && s.window == window.label())
            .cloned()
            .ok_or_else(|| ApiError::new("cancelled", "Voice session has ended"))?;
        if session.started.swap(true, Ordering::AcqRel) {
            return Err(ApiError::new(
                "voice_busy",
                "Voice input is already running",
            ));
        }
        session
    };
    let _active = ActiveRun(&state);
    session.check()?;
    let runtime = runtime::path(window.app_handle())?;
    let stream = Arc::new(
        LiveTranscription::new(voice::CaptureFormat {
            sample_rate,
            channels: 1,
        })
        .map_err(error)?,
    );
    let store = downloads.store();
    let download = store
        .download(
            &[
                model::transcription_model_asset(),
                model::voice_activity_model_asset(),
            ],
            |progress| {
                let _ = window.emit(
                    "voice-event",
                    Event::Progress {
                        id: &session.id,
                        percent: progress.batch_percentage.min(99.0),
                        status: model::display_progress(&progress).status,
                    },
                );
            },
            session.cancel.clone(),
        )
        .await;
    session.check()?;
    download.map_err(|err| ApiError::new(llm::download_code(&err), err.to_string()))?;
    let _ = window.emit(
        "voice-event",
        Event::Progress {
            id: &session.id,
            percent: 100.0,
            status: "Preparing microphone…".into(),
        },
    );

    let _lifecycle = llm_state.lifecycle().lock().await;
    session.check()?;
    let released = should_release_chat_model(true);
    if released {
        llm::replace_state(&llm_state, None, None)?;
        if !has_required_work_reserve(platform::memory().available) {
            return Err(error(
                "Not enough memory for voice input. Close other apps and try again.",
            ));
        }
    }
    let cache = window
        .app_handle()
        .path()
        .app_cache_dir()
        .map_err(error)?
        .join("voice-graphs");
    async_runtime::spawn_blocking(move || {
        catch_unwind(AssertUnwindSafe(|| {
            session.check()?;
            ente_ensu::transcription::load_runtime_from(runtime).map_err(error)?;
            let transcriber = Transcriber::with_cache(
                store.asset_dir(&model::transcription_model_asset()),
                model::voice_activity_model_path(&store),
                cache,
                format!(
                    "desktop-{}-{}",
                    std::env::consts::OS,
                    std::env::consts::ARCH
                ),
            );
            run_capture(&session, &window, &stream, &transcriber, released)
        }))
        .unwrap_or_else(|panic| {
            Err(error(format!(
                "Voice input failed: {}",
                panic_message(panic)
            )))
        })
    })
    .await
    .map_err(error)?
}

fn run_capture(
    session: &Arc<Session>,
    window: &WebviewWindow,
    stream: &Arc<LiveTranscription>,
    transcriber: &Transcriber,
    mut released: bool,
) -> Result<Outcome, ApiError> {
    session.check()?;
    let mut last_memory_check = Instant::now();
    run_stream(session, stream, transcriber, |signal| {
        match signal {
            Signal::Start | Signal::Close => {
                window
                    .emit(
                        "voice-event",
                        Event::Capture {
                            id: &session.id,
                            running: matches!(signal, Signal::Start),
                        },
                    )
                    .map_err(|e| voice::VoiceError::ProcessingFailed(e.to_string()))?;
            }
            Signal::Change => session.emit(window),
            Signal::Tick => {
                if !released && last_memory_check.elapsed() >= Duration::from_secs(1) {
                    last_memory_check = Instant::now();
                    if should_release_chat_model(false) {
                        llm::replace_state(&window.state::<llm::State>(), None, None)
                            .map_err(|e| voice::VoiceError::ProcessingFailed(e.message))?;
                        released = true;
                    }
                }
            }
        }
        Ok(())
    })
}

enum Signal {
    Start,
    Close,
    Change,
    Tick,
}

fn run_stream(
    session: &Arc<Session>,
    stream: &Arc<LiveTranscription>,
    transcriber: &Transcriber,
    mut notify: impl FnMut(Signal) -> voice::Result<()>,
) -> Result<Outcome, ApiError> {
    {
        let mut state = lock(&session.dictation);
        session.check()?;
        state.session.begin_capture().map_err(error)?;
        *lock(&session.stream) = Some(Arc::clone(stream));
    }
    let mut last_emit = Instant::now();
    let mut last_audio = Instant::now();
    let mut submitted = 0;
    let result = stream.run(transcriber, &mut |event| {
        if session.cancel.is_cancelled() { return Ok(LiveControl::Cancel); }
        notify(Signal::Tick)?;
        let received = stream.submitted_samples();
        if received != submitted {
            submitted = received;
            last_audio = Instant::now();
        } else if session.capturing.load(Ordering::Acquire) && last_audio.elapsed() >= Duration::from_secs(5) {
            session.capture_failed("The microphone stopped delivering audio. Check the input device and microphone permission.".into());
        }
        if matches!(event, LiveEvent::Ready) {
            if let Some(failure) = lock(&session.capture_error).as_ref() {
                return Err(voice::VoiceError::InvalidAudio(failure.clone()));
            }
            session.capturing.store(true, Ordering::Release);
            last_audio = Instant::now();
            notify(Signal::Start)?;
        }
        let immediate = matches!(event, LiveEvent::Ready | LiveEvent::Commit { .. } | LiveEvent::CaptureClosed);
        let control = {
            let mut state = lock(&session.dictation);
            let control = state.apply(event, || stream.finish_if_empty())?;
            if state.session.stop_reason().is_some() {
                session.capturing.store(false, Ordering::Release);
                notify(Signal::Close)?;
            }
            control
        };
        if immediate || last_emit.elapsed() >= Duration::from_millis(100) {
            notify(Signal::Change)?;
            last_emit = Instant::now();
        }
        Ok(control)
    });
    session.capturing.store(false, Ordering::Release);
    let _ = notify(Signal::Close);
    stream.finish();
    let capture_error = lock(&session.capture_error).take();
    let mut state = lock(&session.dictation);
    if state.session.phase() != voice::VoicePhase::Closed {
        if result.is_err() || capture_error.is_some() {
            state
                .session
                .stop(voice::StopReason::Failure)
                .map_err(error)?;
        } else if state.session.stop_reason().is_none() {
            state.session.stop(voice::StopReason::Done).map_err(error)?;
        }
        let accepted = state.session.accepted_samples();
        let submitted = stream.submitted_samples();
        if submitted > accepted {
            state
                .session
                .observe_drained_audio(accepted, submitted)
                .map_err(error)?;
        }
    }
    state
        .finish(result.is_ok() && capture_error.is_none())
        .map_err(error)?;
    session.check()?;
    let warning = capture_error.or_else(|| result.err().map(|e| e.to_string()));
    if state.text().is_empty()
        && let Some(warning) = warning
    {
        return Err(error(warning));
    }
    Ok(Outcome {
        text: state.text().to_owned(),
        incomplete: state.session.incomplete(),
        warning,
    })
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Insertion {
    destination: String,
    revision: u64,
    start_utf16: u32,
    end_utf16: u32,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Inserted {
    text: String,
    caret_utf16: u32,
}

#[tauri::command]
pub fn voice_insert(
    anchor: Insertion,
    destination: String,
    mut revision: u64,
    mut text: String,
    voice_text: String,
    composing: bool,
) -> Result<Inserted, ApiError> {
    let insertion = voice::VoiceInsertion {
        anchor: voice::ComposerAnchor {
            destination: anchor.destination,
            revision: anchor.revision,
            start_utf16: anchor.start_utf16,
            end_utf16: anchor.end_utf16,
        },
        text: voice_text,
    };
    let caret_utf16 = voice::ComposerTransfer::default()
        .apply(
            &insertion,
            &destination,
            &mut revision,
            &mut text,
            true,
            composing,
        )
        .map_err(error)?;
    Ok(Inserted { text, caret_utf16 })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn capture(sample_rate: u32) -> Arc<LiveTranscription> {
        Arc::new(
            LiveTranscription::new(voice::CaptureFormat {
                sample_rate,
                channels: 1,
            })
            .unwrap(),
        )
    }

    #[test]
    fn audio_ingress_validates_ownership_order_and_closure() {
        let session = Arc::new(Session::new("main".into()));
        let state = State(Mutex::new(Some(Arc::clone(&session))));
        assert!(owned_session(&state, "other", &session.id).is_none());
        assert!(owned_session(&state, "main", "old-session").is_none());
        assert!(!session.feed(0, &[0, 0]).unwrap());
        *lock(&session.stream) = Some(capture(16000));
        session.capturing.store(true, Ordering::Release);
        assert!(session.feed(0, &[0]).is_err());
        assert!(session.feed(0, &vec![0; 9602]).is_err());
        assert!(session.feed(1, &[0, 0]).is_err());
        assert!(session.feed(0, &[0, 64]).unwrap());
        assert_eq!(f32::from_bits(session.level.load(Ordering::Relaxed)), 0.5);
        assert!(session.feed(0, &[0, 0]).is_err());
        session.stop(false);
        assert!(!session.feed(1, &[0, 0]).unwrap());
        assert_eq!(
            lock(&session.stream).as_ref().unwrap().submitted_samples(),
            1
        );
    }

    #[test]
    fn failed_or_cancelled_preparation_releases_worker_and_reservation() {
        let transcriber = Transcriber::new("/missing-ensu-model", "/missing-ensu-vad");
        let state = State::default();
        let session = Session::new("main".into());
        let download = session.cancel.clone();
        session.capture_failed("The microphone disconnected.".into());
        assert!(download.is_cancelled());
        let failure = session.check().unwrap_err();
        assert_eq!(failure.name, Some("voice"));
        assert_eq!(failure.message, "The microphone disconnected.");
        for cancelled in [false, true] {
            let session = Arc::new(Session::new("main".into()));
            *lock(&state.0) = Some(Arc::clone(&session));
            let guard = ActiveRun(&state);
            if cancelled {
                session.stop(true);
            }
            let mut closed = false;
            let failure = run_stream(&session, &capture(16000), &transcriber, |signal| {
                assert!(!cancelled);
                assert!(!matches!(signal, Signal::Start));
                closed |= matches!(signal, Signal::Close);
                Ok(())
            })
            .err()
            .unwrap();
            assert_eq!(
                failure.name,
                Some(if cancelled { "cancelled" } else { "voice" })
            );
            assert_eq!(closed, !cancelled);
            assert!(!lock(&session.dictation).session.worker_active());
            assert!(!session.capturing.load(Ordering::Acquire));
            drop(guard);
            assert!(lock(&state.0).is_none());
        }
    }

    fn real_audio_fixture() -> (Transcriber, Vec<u8>, u32) {
        ente_ensu::transcription::load_runtime_from(std::env::var("ENSU_TEST_RUNTIME").unwrap())
            .unwrap();
        let transcriber = Transcriber::new(
            std::env::var("ENSU_TEST_TRANSCRIPTION_MODEL").unwrap(),
            std::env::var("ENSU_TEST_VAD").unwrap(),
        );
        let pcm = std::fs::read(std::env::var("ENSU_TEST_PCM").unwrap()).unwrap();
        let rate: u32 = std::env::var("ENSU_TEST_SAMPLE_RATE")
            .ok()
            .and_then(|r| r.parse().ok())
            .unwrap_or(16000);
        assert!(!pcm.is_empty() && pcm.len() <= 8 * rate as usize * 2);
        (transcriber, pcm, rate)
    }

    #[test]
    #[ignore = "requires ENSU_TEST_TRANSCRIPTION_MODEL, ENSU_TEST_VAD, ENSU_TEST_PCM (16 kHz mono PCM16) and ENSU_TEST_RUNTIME"]
    fn microphone_failure_drains_captured_speech_before_returning_a_warning() {
        let (transcriber, mut pcm, rate) = real_audio_fixture();
        pcm.truncate(rate as usize * 2);
        assert!(!pcm.is_empty());
        let mut expected = String::new();
        for failure in [false, true] {
            let session = Arc::new(Session::new("main".into()));
            let stream = capture(rate);
            let outcome = run_stream(&session, &stream, &transcriber, |signal| {
                if matches!(signal, Signal::Start) {
                    for (sequence, chunk) in pcm.chunks(rate as usize / 10 * 2).enumerate() {
                        assert!(session.feed(sequence as u64, chunk).unwrap());
                    }
                    if failure {
                        session.capture_failed("The microphone disconnected.".into());
                    } else {
                        session.stop(false);
                    }
                }
                Ok(())
            })
            .unwrap();
            assert!(!lock(&session.dictation).session.worker_active());
            assert!(!session.capturing.load(Ordering::Acquire));
            assert_eq!(outcome.incomplete, failure);
            if failure {
                assert_eq!(outcome.text, expected);
                assert_eq!(
                    outcome.warning.as_deref(),
                    Some("The microphone disconnected.")
                );
            } else {
                assert!(!outcome.text.trim().is_empty());
                assert!(outcome.warning.is_none());
                expected = outcome.text;
            }
        }
    }

    #[test]
    #[ignore = "requires ENSU_TEST_TRANSCRIPTION_MODEL, ENSU_TEST_VAD, ENSU_TEST_PCM (16 kHz mono PCM16) and ENSU_TEST_RUNTIME"]
    fn real_audio_reaches_desktop_preview_finalization_and_composer() {
        let (transcriber, pcm, rate) = real_audio_fixture();
        for discard in [false, true] {
            let session = Arc::new(Session::new("main".into()));
            let stream = capture(rate);
            let mut changes = 0;
            let result = std::thread::scope(|scope| {
                let mut feeder = None;
                let session_ref = &session;
                let pcm_ref = &pcm;
                let result = run_stream(&session, &stream, &transcriber, |signal| {
                    match signal {
                        Signal::Start => {
                            feeder = Some(scope.spawn(move || {
                                for (sequence, chunk) in
                                    pcm_ref.chunks(rate as usize / 10 * 2).enumerate()
                                {
                                    if !session_ref.feed(sequence as u64, chunk)? {
                                        break;
                                    }
                                    std::thread::sleep(Duration::from_millis(100));
                                }
                                session_ref.stop(discard);
                                Ok::<(), ApiError>(())
                            }));
                        }
                        Signal::Change => changes += 1,
                        _ => {}
                    }
                    Ok(())
                });
                feeder.unwrap().join().unwrap().unwrap();
                result
            });
            assert!(!lock(&session.dictation).session.worker_active());
            if discard {
                assert_eq!(result.err().unwrap().name, Some("cancelled"));
            } else {
                let outcome = result.unwrap();
                assert!(!outcome.incomplete, "{:?}", outcome.warning);
                assert!(
                    outcome.text.to_lowercase().contains("hello"),
                    "{}",
                    outcome.text
                );
                assert!(changes > 0);
                let inserted = voice_insert(
                    Insertion {
                        destination: "chat".into(),
                        revision: 0,
                        start_utf16: 7,
                        end_utf16: 7,
                    },
                    "chat".into(),
                    0,
                    "Draft: ".into(),
                    outcome.text,
                    false,
                )
                .unwrap();
                assert!(inserted.text.starts_with("Draft: "));
                assert_eq!(
                    inserted.caret_utf16 as usize,
                    inserted.text.encode_utf16().count()
                );
            }
        }
    }
}
