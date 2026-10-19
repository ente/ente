use crate::{
    conversation::{ConversationError, error},
    db::EnsuDb,
    retrieval::{GroundedExcerpt, PassageLocator},
};
use ente_ensu::{conversation as core, db, retrieval};
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, Ordering},
};
use uuid::Uuid;

#[derive(uniffi::Object)]
pub struct ConversationFollowup {
    db: Arc<db::ChatDb<db::SqliteBackend>>,
    snapshot: db::chat::ConversationSnapshot,
    question: String,
    selection: Mutex<Option<SourceSelection>>,
    cancelled: AtomicBool,
}

struct SourceSelection {
    references: Vec<retrieval::IncludedPassage>,
    searched: Vec<retrieval::GroundedExcerpt>,
}

fn search_excerpts(
    hits: impl IntoIterator<Item = GroundedExcerpt>,
) -> Result<Vec<retrieval::GroundedExcerpt>, ConversationError> {
    core::GroundingCandidates::new(
        Vec::new(),
        hits.into_iter().map(Into::into).collect(),
        core::MAX_GROUNDING_BYTES,
    )
    .map(|candidates| candidates.searched)
    .map_err(error)
}

#[uniffi::export]
impl EnsuDb {
    pub fn start_conversation_followup(
        &self,
        session_uuid: String,
        path: Vec<String>,
        question: String,
    ) -> Result<Arc<ConversationFollowup>, ConversationError> {
        if path.is_empty()
            || path.len() > core::MAX_HISTORY_MESSAGES
            || question.len() > core::MAX_HISTORY_BYTES
        {
            return Err(error(
                "Please name the subject or document in a shorter source question",
            ));
        }
        let path = path
            .iter()
            .map(|id| Uuid::parse_str(id))
            .collect::<Result<Vec<_>, _>>()
            .map_err(error)?;
        let snapshot = self
            .inner
            .conversation_snapshot(Uuid::parse_str(&session_uuid).map_err(error)?, &path)
            .map_err(error)?;
        if !snapshot
            .messages()
            .last()
            .is_some_and(|m| m.sender == db::Sender::SelfUser && m.text == question)
        {
            return Err(ConversationError::Stale);
        }
        Ok(Arc::new(ConversationFollowup {
            db: self.inner.clone(),
            snapshot,
            question,
            selection: Mutex::new(None),
            cancelled: AtomicBool::new(false),
        }))
    }
}

impl ConversationFollowup {
    fn check(&self) -> Result<(), ConversationError> {
        if self.cancelled.load(Ordering::Acquire) {
            return Err(ConversationError::Cancelled);
        }
        if !self
            .db
            .conversation_snapshot_matches(&self.snapshot)
            .map_err(error)?
        {
            return Err(ConversationError::Stale);
        }
        Ok(())
    }

    pub(crate) fn prepare(
        &self,
        db: &Arc<db::ChatDb<db::SqliteBackend>>,
        snapshot: &db::chat::ConversationSnapshot,
        searched: &[GroundedExcerpt],
    ) -> Result<(String, Vec<retrieval::IncludedPassage>), ConversationError> {
        self.check()?;
        if !Arc::ptr_eq(db, &self.db)
            || snapshot.session_uuid() != self.snapshot.session_uuid()
            || core::fingerprint(snapshot.messages()) != core::fingerprint(self.snapshot.messages())
        {
            return Err(ConversationError::Stale);
        }
        let stored = self.selection.lock().map_err(error)?;
        let selected = stored
            .as_ref()
            .ok_or_else(|| error("Source selection is not complete"))?;
        if search_excerpts(searched.iter().cloned())? != selected.searched {
            return Err(error(
                "Source search changed after selecting earlier passages; retry the reply",
            ));
        }
        Ok((self.question.clone(), selected.references.clone()))
    }
}

#[uniffi::export]
impl ConversationFollowup {
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Release);
    }

    pub fn search_with_history(
        &self,
        searched: Vec<GroundedExcerpt>,
    ) -> Result<Vec<PassageLocator>, ConversationError> {
        self.check()?;
        let mut stored = self.selection.lock().map_err(error)?;
        if stored.is_some() {
            return Err(error("Source selection was already attempted"));
        }
        let searched = search_excerpts(searched)?;
        let evidence = self.snapshot.evidence();
        let references = core::direct_followup_references(
            self.snapshot.messages(),
            &evidence,
            &self.question,
            &searched,
        );
        let locators = references
            .iter()
            .map(|reference| reference.locator.clone().into())
            .collect();
        *stored = Some(SourceSelection {
            references,
            searched,
        });
        Ok(locators)
    }
}
