use super::{chat_db::ChatDbState, common::ApiError};
use ente_ensu::{
    conversation as core,
    db::{ChatDb, SqliteBackend, chat::ConversationSnapshot},
};
use serde::Deserialize;
use std::collections::HashMap;
use std::sync::{Arc, Mutex, atomic::Ordering};
use tauri::{AppHandle, Manager, State as TauriState, WebviewWindow, async_runtime};
use uuid::Uuid;

#[derive(Default)]
pub struct State {
    guards: Mutex<HashMap<String, Guard>>,
}
struct Guard {
    token: String,
    db: Arc<ChatDb<SqliteBackend>>,
    selection: Option<Selection>,
}
pub(crate) struct Selection {
    fingerprint: String,
    pub question: String,
    pub candidates: core::GroundingCandidates,
}

fn error(message: impl Into<String>) -> ApiError {
    ApiError::new("followup", message)
}

impl State {
    pub(crate) fn take_selection(
        &self,
        window: &str,
        token: &str,
        db: &Arc<ChatDb<SqliteBackend>>,
        snapshot: &ConversationSnapshot,
    ) -> Result<Selection, ApiError> {
        let fingerprint = core::fingerprint(snapshot.messages());
        let mut guards = self
            .guards
            .lock()
            .map_err(|_| error("Follow-up state is unavailable"))?;
        guards
            .get_mut(window)
            .filter(|guard| {
                guard.token == token
                    && Arc::ptr_eq(&guard.db, db)
                    && guard
                        .selection
                        .as_ref()
                        .is_some_and(|selection| selection.fingerprint == fingerprint)
            })
            .and_then(|guard| guard.selection.take())
            .ok_or_else(|| {
                ApiError::new(
                    "stale",
                    "Source selection expired or conversation changed; retry the reply",
                )
            })
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Request {
    token: String,
    session_uuid: Uuid,
    path: Vec<Uuid>,
    question: String,
    enabled_stable_ids: Vec<String>,
    enabled_note_collection_ids: Vec<String>,
    cancellation_epoch: u64,
    candidates: Option<core::GroundingCandidates>,
}
#[tauri::command]
pub async fn conversation_resolve_followup(
    app: AppHandle,
    window: WebviewWindow,
    state: TauriState<'_, State>,
    llm_state: TauriState<'_, super::llm::State>,
    input: Request,
) -> Result<String, ApiError> {
    if Uuid::parse_str(&input.token).is_err()
        || input.path.is_empty()
        || input.path.len() > core::MAX_HISTORY_MESSAGES
        || input.question.len() > core::MAX_HISTORY_BYTES
    {
        return Err(error(
            "Please restate the source question with its subject or document name",
        ));
    }
    let db = app.state::<ChatDbState>().database()?;
    let window = window.label().to_owned();
    let epoch = llm_state.retrieval_epoch();
    let expected = input.cancellation_epoch;
    let check = move || {
        if epoch.load(Ordering::Relaxed) == expected {
            Ok(())
        } else {
            Err(ApiError::new("cancelled", "Follow-up cancelled"))
        }
    };
    check()?;
    {
        let mut guards = state
            .guards
            .lock()
            .map_err(|_| error("Follow-up state is unavailable"))?;
        check()?;
        if guards
            .get(&window)
            .is_some_and(|guard| guard.token == input.token)
        {
            return Err(error(
                "This source selection was already attempted; retry the reply",
            ));
        }
        guards.insert(
            window.clone(),
            Guard {
                token: input.token.clone(),
                db: db.clone(),
                selection: None,
            },
        );
    }
    let sources = Arc::new(super::knowledge::SourceSelection::new(
        input.enabled_stable_ids,
        input.enabled_note_collection_ids,
    ));
    let searched_sources = Arc::clone(&sources);
    let work_db = db.clone();
    let check_work = check.clone();
    let (snapshot, mut selection, references) = async_runtime::spawn_blocking(move || {
        check_work()?;
        let snapshot = work_db
            .conversation_snapshot(input.session_uuid, &input.path)
            .map_err(ApiError::from)?;
        let question = snapshot
            .messages()
            .last()
            .ok_or_else(|| error("Missing current question"))?;
        if question.sender != ente_ensu::db::Sender::SelfUser {
            return Err(error("Follow-up must end at a user question"));
        }
        check_work()?;
        let evidence = snapshot.evidence();
        let (mut searched, max_utf8_bytes) = input
            .candidates
            .map_or((Vec::new(), core::MAX_GROUNDING_BYTES), |fresh| {
                (fresh.searched, fresh.max_utf8_bytes)
            });
        searched.retain(|excerpt| searched_sources.allows(&excerpt.locator));
        let candidates = core::GroundingCandidates::new(Vec::new(), searched, max_utf8_bytes)
            .map_err(|cause| error(cause.to_string()))?;
        let references = core::direct_followup_references(
            snapshot.messages(),
            &evidence,
            &input.question,
            &candidates.searched,
        );
        let selection = Selection {
            fingerprint: core::fingerprint(snapshot.messages()),
            question: input.question,
            candidates,
        };
        check_work()?;
        Ok((snapshot, selection, references))
    })
    .await
    .map_err(|_| error("Source selection task failed"))??;
    for reference in references {
        check()?;
        match super::knowledge::reload_for_followup(&app, reference, &sources, expected).await {
            Ok(Some(passage)) => selection.candidates.referenced.push(passage),
            Ok(None) => {}
            Err(error) if error.name == Some("cancelled") => return Err(error),
            Err(error) => crate::logging::log(
                "Conversation",
                format!("Source reload skipped: {}", error.message),
            ),
        }
    }
    async_runtime::spawn_blocking(move || {
        check()?;
        selection
            .candidates
            .validate()
            .map_err(|cause| error(cause.to_string()))?;
        if !db
            .conversation_snapshot_matches(&snapshot)
            .map_err(ApiError::from)?
            || !Arc::ptr_eq(&db, &app.state::<ChatDbState>().database()?)
        {
            return Err(ApiError::new(
                "stale",
                "Conversation changed while selecting sources; retry the reply",
            ));
        }
        let state = app.state::<State>();
        let mut guards = state
            .guards
            .lock()
            .map_err(|_| error("Follow-up state is unavailable"))?;
        check()?;
        let guard = guards
            .get_mut(&window)
            .filter(|guard| guard.token == input.token)
            .ok_or_else(|| ApiError::new("stale", "Source question was superseded"))?;
        guard.selection = Some(selection);
        Ok(input.token)
    })
    .await
    .map_err(|_| error("Source selection validation task failed"))?
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture() -> (Arc<ChatDb<SqliteBackend>>, ConversationSnapshot) {
        let db = Arc::new(ChatDb::open_in_memory(vec![4; 32]).unwrap());
        let session = db.create_session("Synthetic source question").unwrap();
        let question = db
            .insert_message(
                session.uuid,
                "self",
                "Where does she track it?",
                None,
                vec![],
            )
            .unwrap();
        let snapshot = db
            .conversation_snapshot(session.uuid, &[question.uuid])
            .unwrap();
        (db, snapshot)
    }

    #[test]
    fn preparation_requires_matching_source_selection_and_consumes_it_once() {
        let (db, snapshot) = fixture();
        let state = State::default();
        state.guards.lock().unwrap().insert(
            "window".into(),
            Guard {
                token: "token".into(),
                db: db.clone(),
                selection: Some(Selection {
                    fingerprint: core::fingerprint(snapshot.messages()),
                    question: "Where does she track it?".into(),
                    candidates: core::GroundingCandidates::new(
                        vec![],
                        vec![],
                        core::MAX_GROUNDING_BYTES,
                    )
                    .unwrap(),
                }),
            },
        );
        let (other_db, other_snapshot) = fixture();
        for (case, window, token, db, snapshot) in [
            ("window", "another-window", "token", &db, &snapshot),
            ("token", "window", "another-token", &db, &snapshot),
            ("database", "window", "token", &other_db, &snapshot),
            ("history", "window", "token", &db, &other_snapshot),
        ] {
            assert!(
                state.take_selection(window, token, db, snapshot).is_err(),
                "{case}"
            );
        }
        let selection = state
            .take_selection("window", "token", &db, &snapshot)
            .unwrap();
        assert_eq!(selection.question, "Where does she track it?");
        assert!(
            state
                .take_selection("window", "token", &db, &snapshot)
                .is_err()
        );
    }
}
