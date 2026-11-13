use serde::{Deserialize, Serialize};

pub type JobId = i64;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FinishReason {
    Eog,
    StopSequence,
    OutputLimit,
    ContextLimit,
    #[default]
    Unknown,
}

pub trait EventSink {
    fn add(&mut self, event: GenerationEvent);
}

impl<F> EventSink for F
where
    F: FnMut(GenerationEvent),
{
    fn add(&mut self, event: GenerationEvent) {
        (self)(event);
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GenerationSummary {
    pub job_id: JobId,
    pub prompt_tokens: Option<i32>,
    pub generated_tokens: Option<i32>,
    pub total_time_ms: Option<i64>,
    #[serde(default)]
    pub finish_reason: FinishReason,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum GenerationEvent {
    PromptProgress {
        job_id: JobId,
        processed_tokens: i32,
        total_tokens: i32,
    },
    Text {
        job_id: JobId,
        text: String,
        token_id: Option<i32>,
    },
    Done {
        summary: GenerationSummary,
    },
}
