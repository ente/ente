use super::*;

#[derive(Debug, thiserror::Error)]
pub enum PrepareError {
    #[error(transparent)]
    Policy(#[from] Error),
    #[error("Conversation changed during preparation; retry the reply")]
    Stale,
    #[error("Conversation preparation was cancelled")]
    Cancelled,
    #[error(
        "The current message and instructions exceed the model's input budget. Shorten the message or adjust model limits."
    )]
    CurrentInputTooLarge,
    #[error("Conversation memory cannot be shortened enough for these model limits")]
    CannotFit,
    #[error("Conversation preparation failed: {0}")]
    Backend(String),
}

pub trait Effects {
    fn supports_partial_prompt_reuse(&self) -> bool {
        false
    }
    fn prefer_large_summary_chunks(&self) -> bool {
        false
    }
    fn check_current(&mut self) -> Result<(), PrepareError>;
    fn check_cancelled(&mut self) -> Result<(), PrepareError> {
        self.check_current()
    }
    fn measure(&mut self, messages: &[ChatMessage]) -> Result<usize, PrepareError>;
    fn summarize(
        &mut self,
        messages: Vec<ChatMessage>,
        output: usize,
    ) -> Result<(String, FinishReason), PrepareError>;
    fn checkpoint(&mut self, state: &ConversationState) -> Result<(), PrepareError>;
}

pub struct PreparationResult {
    pub messages: Vec<ChatMessage>,
    pub prompt_tokens: usize,
    pub(super) grounding_anchor: Option<GroundingAnchor>,
    pub(super) saved: bool,
}

impl PreparationResult {
    pub fn is_saved(&self) -> bool {
        self.saved
    }
}

pub struct Preparation {
    session: Uuid,
    history: Vec<Message>,
    system: String,
    current: String,
    history_query: Option<String>,
    input_budget: usize,
    summary_input_budget: usize,
    summary_output: usize,
    state: Option<ConversationState>,
    covered: usize,
    grounding: Option<PromptGrounding>,
}

struct PendingChunk {
    end: usize,
    payload: String,
    offset: usize,
    memory: Option<String>,
}

impl Preparation {
    pub(super) fn new(
        session: Uuid,
        history: Vec<Message>,
        system: String,
        current: String,
        context: usize,
        output: usize,
        state: Option<ConversationState>,
    ) -> Result<Self, PrepareError> {
        validate_path(&history)?;
        if history
            .iter()
            .any(|message| message.session_uuid != session)
        {
            return Err(Error::InvalidHistory.into());
        }
        let covered = state
            .as_ref()
            .filter(|state| state.session_uuid == session)
            .and_then(|state| state.coverage(&history))
            .filter(|end| {
                history
                    .get(*end)
                    .is_none_or(|message| message.sender == Sender::SelfUser)
            });
        let state = state.filter(|_| covered.is_some());
        let covered = covered.unwrap_or(0);
        let answer_input_budget = input_budget(context, output)?;
        let summary_output = SUMMARY_OUTPUT_TOKENS
            .min(context / 4)
            .min(context - SAFETY_TOKENS - 1);
        Ok(Self {
            session,
            history,
            system,
            history_query: Some(current.clone()),
            current,
            input_budget: answer_input_budget,
            summary_input_budget: input_budget(context, summary_output)?,
            summary_output,
            state,
            covered,
            grounding: None,
        })
    }

    #[cfg(test)]
    pub(super) fn state(&self) -> Option<&ConversationState> {
        self.state.as_ref()
    }
    #[cfg(test)]
    pub(super) fn covered(&self) -> usize {
        self.covered
    }

    pub(super) fn with_history_query(mut self, query: Option<String>) -> Self {
        self.history_query = query;
        self
    }

    pub(super) fn with_grounding(mut self, grounding: Option<PromptGrounding>) -> Self {
        self.grounding = grounding;
        self
    }

    fn answer_messages(
        &self,
        memory: Option<&str>,
        tail: &[Message],
        current: &str,
    ) -> Vec<ChatMessage> {
        let mut messages = answer_messages(&self.system, memory, tail, current);
        if let Some(grounding) = &self.grounding {
            grounding.apply(tail, &mut messages);
        }
        messages
    }

    fn result(
        &self,
        messages: Vec<ChatMessage>,
        prompt_tokens: usize,
        tail: &[Message],
    ) -> PreparationResult {
        PreparationResult {
            messages,
            prompt_tokens,
            saved: false,
            grounding_anchor: self
                .grounding
                .as_ref()
                .map(|grounding| grounding.anchor(tail)),
        }
    }

    fn fallback(&self, effects: &mut impl Effects) -> Result<PreparationResult, PrepareError> {
        effects.check_current()?;
        let mut memory = self.state.as_ref().map(|s| s.summary.text.as_str());
        let mut messages = self.answer_messages(memory, &[], &self.current);
        let mut prompt_tokens = effects.measure(&messages)?;
        if prompt_tokens > self.input_budget {
            memory = None;
            messages = self.answer_messages(None, &[], &self.current);
            prompt_tokens = effects.measure(&messages)?;
        }
        if prompt_tokens > self.input_budget {
            return Err(PrepareError::CurrentInputTooLarge);
        }
        let start = if memory.is_some() { self.covered } else { 0 };
        let history = &self.history[start..];
        let ranges = exchanges(history);
        let mut retained_start = history.len();
        let (mut low, mut high) = (0, ranges.len());
        while low < high {
            effects.check_current()?;
            let mid = low + (high - low) / 2;
            let candidate =
                self.answer_messages(memory, &history[ranges[mid].start..], &self.current);
            let count = effects.measure(&candidate)?;
            if count <= self.input_budget {
                messages = candidate;
                prompt_tokens = count;
                retained_start = ranges[mid].start;
                high = mid;
            } else {
                low = mid + 1;
            }
        }
        effects.check_current()?;
        Ok(self.result(messages, prompt_tokens, &history[retained_start..]))
    }

    pub fn run(&mut self, effects: &mut impl Effects) -> Result<PreparationResult, PrepareError> {
        let mut pending_chunk: Option<PendingChunk> = None;
        let mut retrying = false;
        let mut use_retry_instruction = false;
        effects.check_current()?;
        let mandatory = self.answer_messages(None, &[], &self.current);
        if effects.measure(&mandatory)? > self.input_budget {
            return Err(PrepareError::CurrentInputTooLarge);
        }
        if self.covered > 0 {
            let messages = self.answer_messages(None, &self.history, &self.current);
            let prompt_tokens = effects.measure(&messages)?;
            if prompt_tokens <= self.input_budget {
                effects.check_current()?;
                return Ok(self.result(messages, prompt_tokens, &self.history));
            }
        }
        loop {
            effects.check_current()?;
            let memory = self.state.as_ref().map(|s| s.summary.text.as_str());
            let messages =
                self.answer_messages(memory, &self.history[self.covered..], &self.current);
            let count = effects.measure(&messages)?;
            if count <= self.input_budget {
                if self.covered > 0
                    && let Some(query) = &self.history_query
                {
                    let lookup = lookup_history(&self.history[..self.covered], query, || {
                        effects.check_cancelled()
                    })?;
                    let allowance = 512
                        .min(self.input_budget / 8)
                        .min(self.input_budget - count);
                    for take in (0..=lookup.excerpts.len()).rev() {
                        let recovered = self.answer_messages(
                            memory,
                            &self.history[self.covered..],
                            &lookup.prepend_to(&self.current, take),
                        );
                        let tokens = effects.measure(&recovered)?;
                        if tokens <= self.input_budget && tokens.saturating_sub(count) <= allowance
                        {
                            effects.check_current()?;
                            return Ok(self.result(
                                recovered,
                                tokens,
                                &self.history[self.covered..],
                            ));
                        }
                    }
                }
                effects.check_current()?;
                return Ok(self.result(messages, count, &self.history[self.covered..]));
            }
            let memory_tokens = if memory.is_some() {
                effects.measure(&self.answer_messages(memory, &[], &self.current))?
            } else {
                0
            };
            if memory.is_some()
                && (memory_tokens > self.input_budget || self.covered == self.history.len())
            {
                let mut request = summary_messages(memory, &[]);
                request[0].content.push_str(" Shorten the previous memory substantially by removing redundant detail. Keep active constraints and decisions.");
                if effects.measure(&request)? > self.summary_input_budget {
                    return self.fallback(effects);
                }
                let (text, finish) = match effects.summarize(request, self.summary_output) {
                    Ok(result) => result,
                    Err(error @ (PrepareError::Cancelled | PrepareError::Stale)) => {
                        return Err(error);
                    }
                    Err(_) => return self.fallback(effects),
                };
                effects.check_current()?;
                let Ok(text) = completed_summary(&text, finish) else {
                    return self.fallback(effects);
                };
                let after = self.answer_messages(Some(&text), &[], &self.current);
                if effects.measure(&after)? >= memory_tokens {
                    return self.fallback(effects);
                }
                effects.check_current()?;
                let next =
                    ConversationState::new(self.session, &self.history[..self.covered], text)?;
                effects.checkpoint(&next)?;
                self.state = Some(next);
                continue;
            }
            if pending_chunk.is_none() {
                let full_summary_budget = effects.prefer_large_summary_chunks();
                let ranges = exchanges(&self.history[self.covered..]);
                let mut end = self.covered + ranges.first().ok_or(PrepareError::CannotFit)?.end;
                let preferred = ranges.len().saturating_sub(2).max(1);
                for range in ranges.iter().take(preferred) {
                    let candidate = self.covered + range.end;
                    let request = summary_messages(memory, &self.history[self.covered..candidate]);
                    let tokens = effects.measure(&request)?;
                    if tokens > self.summary_input_budget
                        || (!full_summary_budget
                            && candidate > end
                            && tokens > self.input_budget / 2)
                    {
                        break;
                    }
                    end = candidate;
                }
                let payload =
                    serde_json::json!(history_rows(&self.history[self.covered..end])).to_string();
                pending_chunk = Some(PendingChunk {
                    end,
                    payload,
                    offset: 0,
                    memory: memory.map(str::to_owned),
                });
            }
            let pending = pending_chunk.as_ref().ok_or(PrepareError::CannotFit)?;
            let remaining = &pending.payload[pending.offset..];
            let make_request = |length: usize| {
                vec![
                ChatMessage { role: "system".into(), content: summary_instruction(use_retry_instruction || retrying) },
                ChatMessage { role: "user".into(), content: serde_json::json!({
                    "previous_summary": pending.memory.as_deref().unwrap_or(""),
                    "history_fragment": &remaining[..length], "fragment_start_byte": pending.offset,
                    "history_total_bytes": pending.payload.len(), "last_fragment": length == remaining.len()
                }).to_string() }
            ]
            };
            let mut length = remaining.len();
            while effects.measure(&make_request(length))? > self.summary_input_budget {
                length /= 2;
                while length > 0 && !remaining.is_char_boundary(length) {
                    length -= 1;
                }
                if length == 0 {
                    return self.fallback(effects);
                }
            }
            let request = make_request(length);
            let output = if !retrying && effects.measure(&request)? > self.summary_output * 2 {
                self.summary_output.min(384)
            } else {
                self.summary_output
            };
            let (text, finish) = match effects.summarize(request, output) {
                Ok(result) => result,
                Err(error @ (PrepareError::Cancelled | PrepareError::Stale)) => return Err(error),
                Err(_) => return self.fallback(effects),
            };
            effects.check_current()?;
            let text = match completed_summary(&text, finish) {
                Ok(text) => text,
                Err(_) if !retrying => {
                    use_retry_instruction |= finish == FinishReason::StopSequence;
                    retrying = true;
                    continue;
                }
                Err(_) => return self.fallback(effects),
            };
            retrying = false;
            let pending = pending_chunk.as_mut().ok_or(PrepareError::CannotFit)?;
            pending.offset += length;
            pending.memory = Some(text.clone());
            if pending.offset == pending.payload.len() {
                let end = pending.end;
                let next = ConversationState::new(self.session, &self.history[..end], text)?;
                effects.checkpoint(&next)?;
                self.state = Some(next);
                self.covered = end;
                pending_chunk = None;
            }
        }
    }
}
