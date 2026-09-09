use serde::{Deserialize, Serialize};

pub type JobId = i64;

pub trait EventSink {
    fn add(&mut self, event: GenerationEvent);

    /// Actual sequence positions consumed, including multimodal input.
    fn context_usage(&mut self, _job_id: JobId, _used: u32, _capacity: u32) {}
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
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum GenerationEvent {
    Text {
        job_id: JobId,
        text: String,
        token_id: Option<i32>,
    },
    Done {
        summary: GenerationSummary,
    },
}
