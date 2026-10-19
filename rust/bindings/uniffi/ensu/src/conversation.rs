use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, AtomicI64, Ordering},
};

use ente_ensu::{conversation as core, db, llm, retrieval};
use thiserror::Error;
use uuid::Uuid;

use crate::db::{DbAttachmentMeta, DbMessage, EnsuDb, to_message};
use crate::llm::{LlmChatMessage, LlmContext};
use crate::retrieval::GroundedExcerpt;

#[derive(Debug, Error, uniffi::Error)]
pub enum ConversationError {
    #[error("Conversation preparation was cancelled")]
    Cancelled,
    #[error("Conversation changed; retry the reply")]
    Stale,
    #[error("{detail}")]
    Other { detail: String },
}

pub(crate) fn error(cause: impl std::fmt::Display) -> ConversationError {
    ConversationError::Other {
        detail: cause.to_string(),
    }
}

impl From<core::PrepareError> for ConversationError {
    fn from(cause: core::PrepareError) -> Self {
        match cause {
            core::PrepareError::Cancelled => Self::Cancelled,
            core::PrepareError::Stale => Self::Stale,
            cause => error(cause),
        }
    }
}

#[derive(Clone, uniffi::Record)]
pub struct ConversationRequest {
    pub session_uuid: String,
    pub path: Vec<String>,
    pub system: String,
    pub current: String,
    pub expected_user_text: String,
    pub history_query: Option<String>,
    pub max_tokens: Option<u32>,
    pub searched: Vec<GroundedExcerpt>,
    pub followup: Option<Arc<crate::followup::ConversationFollowup>>,
    pub reloaded: Vec<GroundedExcerpt>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct ConversationResult {
    pub messages: Vec<LlmChatMessage>,
    pub max_tokens: u32,
}

#[uniffi::export(foreign)]
pub trait ConversationProgressCallback: Send + Sync {
    fn on_progress(&self);
}

enum Work {
    Pending(ConversationRequest),
    Ready(Box<PreparedWork>),
}

struct PreparedWork {
    snapshot: db::chat::ConversationSnapshot,
    result: ConversationResult,
    grounded: Option<retrieval::GroundedPromptContext>,
    saved: bool,
}

#[derive(uniffi::Object)]
pub struct ConversationPreparation {
    db: Arc<db::ChatDb<db::SqliteBackend>>,
    context: llm::ContextRef,
    work: Mutex<Work>,
    cancelled: AtomicBool,
    summary_job: AtomicI64,
}

#[uniffi::export]
impl EnsuDb {
    pub fn prepare_conversation(
        &self,
        context: Arc<LlmContext>,
        input: ConversationRequest,
    ) -> Result<Arc<ConversationPreparation>, ConversationError> {
        if input.path.is_empty() || input.path.len() > core::MAX_HISTORY_MESSAGES {
            return Err(error("Invalid preparation history"));
        }
        Ok(Arc::new(ConversationPreparation {
            db: self.inner.clone(),
            context: context.handle.clone(),
            work: Mutex::new(Work::Pending(input)),
            cancelled: AtomicBool::new(false),
            summary_job: AtomicI64::new(0),
        }))
    }
}

impl ConversationPreparation {
    fn check_cancelled(&self) -> Result<(), ConversationError> {
        if self.cancelled.load(Ordering::Acquire) {
            return Err(ConversationError::Cancelled);
        }
        Ok(())
    }

    fn check(&self, work: &Work) -> Result<(), ConversationError> {
        self.check_cancelled()?;
        if let Work::Ready(work) = work
            && (work.saved
                || !self
                    .db
                    .conversation_snapshot_matches(&work.snapshot)
                    .map_err(error)?)
        {
            return Err(ConversationError::Stale);
        }
        Ok(())
    }

    fn start(
        &self,
        mut input: ConversationRequest,
        callback: &dyn ConversationProgressCallback,
    ) -> Result<PreparedWork, ConversationError> {
        self.check_cancelled()?;
        let session = Uuid::parse_str(&input.session_uuid).map_err(error)?;
        let path = input
            .path
            .iter()
            .map(|id| Uuid::parse_str(id))
            .collect::<Result<Vec<_>, _>>()
            .map_err(error)?;
        let mut snapshot = self
            .db
            .conversation_snapshot(session, &path)
            .map_err(error)?;
        self.check_cancelled()?;
        let mut referenced = Vec::new();
        if let Some(turn) = &input.followup {
            let (query, references) = turn.prepare(&self.db, &snapshot, &input.searched)?;
            input.history_query = Some(query);
            for reference in references {
                self.check_cancelled()?;
                let Some(hit) = input.reloaded.iter().find(|hit| {
                    retrieval::PassageLocator::from(hit.locator.clone()) == reference.locator
                }) else {
                    continue;
                };
                let Some(passages) = reference.verified_spans(&hit.text) else {
                    continue;
                };
                referenced.push(retrieval::ReferencedPassage {
                    passages,
                    source: hit.source.clone().into(),
                    reference,
                });
            }
        }
        let candidates = core::GroundingCandidates::new(
            referenced,
            input.searched.into_iter().map(Into::into).collect(),
            core::MAX_GROUNDING_BYTES,
        )?;
        let input = core::TurnInput {
            session,
            messages: snapshot.messages().to_vec(),
            expected_user_text: input.expected_user_text,
            system: input.system,
            current: input.current,
            history_query: input.history_query,
            context: self.context.context_size() as usize,
            output: input.max_tokens.map(|value| value as usize),
            state: snapshot.state().cloned(),
            candidates,
        };
        let mut effects = NativeEffects {
            owner: self,
            snapshot: &mut snapshot,
            callback,
        };
        let mut prepared = core::prepare_turn(input, &mut effects)?;
        let result = prepared.preparation.run(&mut effects)?;
        core::Effects::check_current(&mut effects)?;
        Ok(PreparedWork {
            snapshot,
            result: ConversationResult {
                messages: result.messages.into_iter().map(Into::into).collect(),
                max_tokens: prepared.budget.output as u32,
            },
            grounded: prepared.grounding.context,
            saved: false,
        })
    }
}

#[uniffi::export]
impl ConversationPreparation {
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Release);
        let job = self.summary_job.load(Ordering::Acquire);
        if job > 0 {
            llm::cancel(job);
        }
    }

    pub fn run(
        &self,
        callback: Arc<dyn ConversationProgressCallback>,
    ) -> Result<ConversationResult, ConversationError> {
        let mut work = self.work.lock().map_err(error)?;
        self.check(&work)?;
        if let Work::Pending(input) = &*work {
            let prepared = self.start(input.clone(), callback.as_ref())?;
            *work = Work::Ready(Box::new(prepared));
        }
        let Work::Ready(work) = &*work else {
            return Err(ConversationError::Stale);
        };
        Ok(work.result.clone())
    }

    pub fn validate(&self) -> Result<(), ConversationError> {
        let work = self.work.lock().map_err(error)?;
        self.check(&work)?;
        let Work::Ready(_) = &*work else {
            return Err(error("Conversation preparation is not complete"));
        };
        Ok(())
    }

    pub fn add_answer(
        &self,
        text: String,
        attachments: Vec<DbAttachmentMeta>,
    ) -> Result<DbMessage, ConversationError> {
        let mut work = self.work.lock().map_err(error)?;
        self.check(&work)?;
        let Work::Ready(work) = &mut *work else {
            return Err(error("Conversation preparation is not complete"));
        };
        let sources = work
            .grounded
            .as_ref()
            .map(|grounded| grounded.sources.as_slice())
            .unwrap_or_default();
        let text = retrieval::finalize_grounded_assistant_text(&text, sources).map_err(error)?;
        let answer = self
            .db
            .insert_message_guarded(
                work.snapshot.session_uuid(),
                "other",
                &text,
                work.snapshot.messages().last().map(|message| message.uuid),
                attachments.into_iter().map(Into::into).collect(),
                Some(&work.snapshot),
            )
            .map_err(error)?;
        work.saved = true;
        if let Some(grounded) = work.grounded.take()
            && !grounded.included_passages.is_empty()
        {
            match self.db.save_answer_evidence(
                &work.snapshot,
                answer.uuid,
                grounded.included_passages,
            ) {
                Ok(true) => {}
                Ok(false) => ente_uniffi_log::warn!(
                    target: "Conversation",
                    "Reply saved, but its source references could not be retained"
                ),
                Err(error) => ente_uniffi_log::warn!(
                    target: "Conversation",
                    "Reply saved but source reference persistence failed: {error}"
                ),
            }
        }
        Ok(to_message(answer))
    }
}

struct NativeEffects<'a> {
    owner: &'a ConversationPreparation,
    snapshot: &'a mut db::chat::ConversationSnapshot,
    callback: &'a dyn ConversationProgressCallback,
}

impl core::Effects for NativeEffects<'_> {
    fn check_current(&mut self) -> Result<(), core::PrepareError> {
        self.check_cancelled()?;
        if !self
            .owner
            .db
            .conversation_snapshot_matches(self.snapshot)
            .map_err(|cause| core::PrepareError::Backend(cause.to_string()))?
        {
            return Err(core::PrepareError::Stale);
        }
        Ok(())
    }

    fn check_cancelled(&mut self) -> Result<(), core::PrepareError> {
        if self.owner.cancelled.load(Ordering::Acquire) {
            return Err(core::PrepareError::Cancelled);
        }
        Ok(())
    }

    fn measure(&mut self, messages: &[llm::ChatMessage]) -> Result<usize, core::PrepareError> {
        self.owner
            .context
            .measure_text_chat_prompt(&llm::ChatRequest {
                messages: messages.to_vec(),
                ..Default::default()
            })
            .map_err(|cause| core::PrepareError::Backend(cause.to_string()))
    }

    fn summarize(
        &mut self,
        messages: Vec<llm::ChatMessage>,
        output: usize,
    ) -> Result<(String, llm::FinishReason), core::PrepareError> {
        self.check_current()?;
        self.callback.on_progress();
        self.check_cancelled()?;
        let prompt_tokens = self.measure(&messages)?;
        let generation = core::summary_request(messages, output, prompt_tokens)?;
        let mut text = String::new();
        let result = self
            .owner
            .context
            .generate_chat_stream(generation, &mut |event| {
                if let llm::GenerationEvent::Text {
                    job_id,
                    text: delta,
                    ..
                } = event
                {
                    self.owner.summary_job.store(job_id, Ordering::Release);
                    if self.owner.cancelled.load(Ordering::Acquire) {
                        llm::cancel(job_id);
                    } else {
                        text.push_str(&delta);
                    }
                }
            });
        self.owner.summary_job.store(0, Ordering::Release);
        self.check_current()?;
        let summary = result.map_err(|cause| match cause {
            llm::Error::Cancelled => core::PrepareError::Cancelled,
            cause => core::PrepareError::Backend(cause.to_string()),
        })?;
        Ok((text, summary.finish_reason))
    }

    fn checkpoint(&mut self, state: &core::ConversationState) -> Result<(), core::PrepareError> {
        self.check_current()?;
        if !self
            .owner
            .db
            .replace_conversation_state(self.snapshot, Some(state.clone()))
            .map_err(|cause| core::PrepareError::Backend(cause.to_string()))?
        {
            return Err(core::PrepareError::Stale);
        }
        Ok(())
    }
}
