use std::collections::HashMap;
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicU64, Ordering},
};

use super::{chat_db::ChatDbState, common::ApiError};
use ente_ensu::{
    conversation::{self, Effects, PrepareError},
    db::{ChatDb, SqliteBackend, chat::ConversationSnapshot},
    llm,
    retrieval::IncludedPassage,
};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, Manager, State as TauriState, WebviewWindow, async_runtime};
use uuid::Uuid;

#[derive(Default)]
pub struct State {
    slots: Mutex<HashMap<String, Slot>>,
}
struct Slot {
    token: String,
    snapshot: ConversationSnapshot,
    db: Arc<ChatDb<SqliteBackend>>,
    passages: Vec<IncludedPassage>,
    model_epoch: u64,
    cancel_epoch: u64,
}

impl State {
    pub(crate) fn validate_answer(
        &self,
        app: &AppHandle,
        window: &str,
        token: &str,
        model_epoch: u64,
        cancel_epoch: u64,
    ) -> Result<(), ApiError> {
        let slots = self
            .slots
            .lock()
            .map_err(|_| error("Preparation state is unavailable"))?;
        let slot = slots
            .get(window)
            .filter(|slot| {
                slot.token == token
                    && slot.model_epoch == model_epoch
                    && slot.cancel_epoch == cancel_epoch
            })
            .ok_or_else(|| error("Conversation or model changed; retry the reply"))?;
        if !slot
            .db
            .conversation_snapshot_matches(&slot.snapshot)
            .map_err(ApiError::from)?
        {
            return Err(error("Conversation changed; retry the reply"));
        }
        if !Arc::ptr_eq(&slot.db, &app.state::<ChatDbState>().database()?) {
            return Err(error("Conversation database changed; retry the reply"));
        }
        Ok(())
    }
    pub(crate) fn take_answer(
        &self,
        app: &AppHandle,
        window: &str,
        token: &str,
    ) -> Result<(ConversationSnapshot, Vec<IncludedPassage>), ApiError> {
        let mut slots = self
            .slots
            .lock()
            .map_err(|_| error("Preparation state is unavailable"))?;
        let slot = slots
            .get(window)
            .filter(|slot| slot.token == token)
            .ok_or_else(|| error("Conversation preparation has expired; retry the reply"))?;
        if !Arc::ptr_eq(&slot.db, &app.state::<ChatDbState>().database()?) {
            return Err(error("Conversation database changed; retry the reply"));
        }
        slots
            .remove(window)
            .map(|slot| (slot.snapshot, slot.passages))
            .ok_or_else(|| error("Preparation has expired"))
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Request {
    session_uuid: Uuid,
    path: Vec<Uuid>,
    system: String,
    current: String,
    expected_user_text: String,
    history_query: Option<String>,
    grounding_candidates: Option<conversation::GroundingCandidates>,
    max_tokens: usize,
    preparation_token: String,
    cancellation_epoch: u64,
    resolution_token: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Response {
    preparation_token: String,
    messages: Vec<llm::ChatMessage>,
    grounded_context: Option<super::knowledge::GroundedPromptContextDto>,
}

fn error(message: impl Into<String>) -> ApiError {
    ApiError::new("conversation", message)
}
fn preparation_error(cause: PrepareError) -> ApiError {
    match cause {
        PrepareError::Cancelled => ApiError::new("cancelled", cause.to_string()),
        _ => error(cause.to_string()),
    }
}

struct NativeEffects<'a> {
    app: AppHandle,
    window: WebviewWindow,
    token: &'a str,
    context: llm::ContextRef,
    db: Arc<ChatDb<SqliteBackend>>,
    snapshot: &'a mut ConversationSnapshot,
    epoch: Arc<AtomicU64>,
    expected_epoch: u64,
}
impl Effects for NativeEffects<'_> {
    fn check_current(&mut self) -> Result<(), PrepareError> {
        self.check_cancelled()?;
        if !self
            .db
            .conversation_snapshot_matches(self.snapshot)
            .map_err(|_| PrepareError::Backend("History validation failed".into()))?
        {
            return Err(PrepareError::Stale);
        }
        Ok(())
    }
    fn check_cancelled(&mut self) -> Result<(), PrepareError> {
        if self.epoch.load(Ordering::Relaxed) != self.expected_epoch {
            return Err(PrepareError::Cancelled);
        }
        let active = self
            .app
            .state::<ChatDbState>()
            .database()
            .map_err(|_| PrepareError::Cancelled)?;
        if !Arc::ptr_eq(&active, &self.db) {
            return Err(PrepareError::Cancelled);
        }
        Ok(())
    }
    fn measure(&mut self, messages: &[llm::ChatMessage]) -> Result<usize, PrepareError> {
        self.context
            .measure_text_chat_prompt(&llm::ChatRequest {
                messages: messages.to_vec(),
                ..Default::default()
            })
            .map_err(|e| PrepareError::Backend(e.to_string()))
    }
    fn summarize(
        &mut self,
        messages: Vec<llm::ChatMessage>,
        output: usize,
    ) -> Result<(String, llm::FinishReason), PrepareError> {
        self.check_current()?;
        let _ = self.window.emit(
            "conversation-progress",
            serde_json::json!({"preparationToken": self.token}),
        );
        let prompt_tokens = self.measure(&messages)?;
        let generation = conversation::summary_request(messages, output, prompt_tokens)?;
        let mut text = String::new();
        let epoch = self.epoch.clone();
        let expected = self.expected_epoch;
        let summary = self
            .context
            .generate_chat_stream(generation, &mut |event| {
                if let llm::GenerationEvent::Text {
                    text: delta,
                    job_id,
                    ..
                } = event
                {
                    if epoch.load(Ordering::Relaxed) != expected {
                        llm::cancel(job_id);
                    } else {
                        text.push_str(&delta);
                    }
                }
            })
            .map_err(|e| match e {
                llm::Error::Cancelled => PrepareError::Cancelled,
                other => PrepareError::Backend(other.to_string()),
            })?;
        self.check_current()?;
        Ok((text, summary.finish_reason))
    }
    fn checkpoint(&mut self, state: &conversation::ConversationState) -> Result<(), PrepareError> {
        self.check_current()?;
        if !self
            .db
            .replace_conversation_state(self.snapshot, Some(state.clone()))
            .map_err(|_| {
                PrepareError::Backend(
                    "Unable to save conversation memory; retry after checking available storage"
                        .into(),
                )
            })?
        {
            return Err(PrepareError::Stale);
        }
        Ok(())
    }
}

#[tauri::command]
pub async fn conversation_prepare(
    app: AppHandle,
    window: WebviewWindow,
    state: TauriState<'_, State>,
    llm_state: TauriState<'_, super::llm::State>,
    db_state: TauriState<'_, ChatDbState>,
    mut input: Request,
) -> Result<Response, ApiError> {
    if Uuid::parse_str(&input.preparation_token).is_err()
        || input.path.is_empty()
        || input.path.len() > conversation::MAX_HISTORY_MESSAGES
    {
        return Err(error("Invalid preparation request"));
    }
    let _lifecycle = llm_state.lifecycle().lock().await;
    let context = llm_state.context_ref()?;
    let db = db_state.database()?;
    let epoch = llm_state.retrieval_epoch();
    let expected_epoch = epoch.load(Ordering::Relaxed);
    if input.cancellation_epoch != expected_epoch {
        return Err(ApiError::new(
            "cancelled",
            "Conversation preparation was cancelled",
        ));
    }
    let model_epoch = llm_state.model_state_epoch();
    state
        .slots
        .lock()
        .map_err(|_| error("Preparation state unavailable"))?
        .remove(window.label());
    let work_window = window.clone();
    let token = input.preparation_token.clone();
    let (response, slot) = async_runtime::spawn_blocking(move || -> Result<_, ApiError> {
        let mut snapshot = db
            .conversation_snapshot(input.session_uuid, &input.path)
            .map_err(ApiError::from)?;
        if let Some(token) = &input.resolution_token {
            let selection = app.state::<super::followup::State>().take_selection(
                work_window.label(),
                token,
                &db,
                &snapshot,
            )?;
            input.history_query = Some(selection.question);
            input.grounding_candidates = Some(selection.candidates);
        }
        let candidates = match input.grounding_candidates.take() {
            Some(candidates) => candidates,
            None => conversation::GroundingCandidates::new(vec![], vec![], conversation::MAX_GROUNDING_BYTES)
                .map_err(preparation_error)?,
        };
        candidates.validate().map_err(|e| error(e.to_string()))?;
        let turn = conversation::TurnInput {
            session: input.session_uuid,
            messages: snapshot.messages().to_vec(),
            expected_user_text: input.expected_user_text,
            system: input.system,
            current: input.current,
            history_query: input.history_query,
            context: context.context_size() as usize,
            output: Some(input.max_tokens),
            state: snapshot.state().cloned(),
            candidates,
        };
        let mut effects = NativeEffects {
            app,
            window: work_window,
            token: &token,
            context,
            db: db.clone(),
            snapshot: &mut snapshot,
            epoch,
            expected_epoch,
        };
        let mut prepared = conversation::prepare_turn(turn, &mut effects)
            .map_err(preparation_error)?;
        crate::logging::log("Conversation", format!(
            "generation budget context={} output={} input={} source_repacked={} evidence_tokens={}",
            prepared.budget.context, prepared.budget.output, prepared.budget.input,
            prepared.grounding.repacked, prepared.grounding.evidence_tokens,
        ));
        let result = prepared.preparation.run(&mut effects).map_err(preparation_error)?;
        effects.check_current().map_err(preparation_error)?;
        let mut grounded = prepared.grounding.context;
        let passages = grounded.as_mut()
            .map(|context| std::mem::take(&mut context.included_passages))
            .unwrap_or_default();
        Ok((
            Response {
                preparation_token: token.clone(),
                messages: result.messages,
                grounded_context: grounded.map(Into::into),
            },
            Slot {
                token,
                snapshot,
                db,
                passages,
                model_epoch,
                cancel_epoch: expected_epoch,
            },
        ))
    })
    .await
    .map_err(|_| error("Conversation preparation failed"))??;
    let mut slots = state
        .slots
        .lock()
        .map_err(|_| error("Preparation state unavailable"))?;
    if slots.len() >= 8 && !slots.contains_key(window.label()) {
        return Err(error("Too many active chat windows"));
    }
    slots.insert(window.label().to_owned(), slot);
    Ok(response)
}
