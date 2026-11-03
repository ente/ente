mod audio;
mod capture;
mod composer;
mod rolling;
mod session;

pub(crate) use audio::{AudioRing, MAX_WINDOW_SAMPLES, VOICE_SAMPLE_RATE};
pub(crate) use capture::CaptureQueue;
pub use capture::{CaptureFeedResult, CaptureFormat};
pub(crate) use composer::transcript_separator;
pub use composer::{ComposerAnchor, ComposerTransfer, VoiceInsertion, preview_insertion};
pub(crate) use rolling::RecognitionUpdate;
pub(crate) use rolling::{AlignedWord, DecodeWindow, RollingRecognizer, TranscriptBoundary};
pub use session::{StopReason, VoicePhase, VoiceSession};

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum VoiceError {
    #[error("{0}")]
    InvalidAudio(String),
    #[error("Transcription model is not downloaded")]
    NotDownloaded,
    #[error("Voice activity model is not downloaded")]
    VadNotDownloaded,
    #[error("not enough storage space")]
    StorageFull,
    #[error("{0}")]
    Io(String),
    #[error("Audio backlog limit reached")]
    BacklogFull,
    #[error("Voice recording was cancelled")]
    Cancelled,
    #[error("Speech alignment could not be preserved")]
    UnstableTranscript,
    #[error("{0}")]
    ProcessingFailed(String),
    #[error("Voice event belongs to an inactive recording")]
    StaleEvent,
    #[error("Voice operation is not valid in the current state")]
    InvalidState,
    #[error("Text range is not on a character boundary")]
    InvalidTextRange,
    #[error("Text or destination changed")]
    RevisionConflict,
    #[error("Some speech could not be finalized")]
    IncompleteAudio,
    #[error("Keyboard input is still composing")]
    PendingEdit,
}

pub type Result<T> = std::result::Result<T, VoiceError>;
