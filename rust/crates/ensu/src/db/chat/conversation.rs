use super::*;
use crate::conversation::{
    self, AnswerEvidence, ConversationEnvelope, ConversationState, MAX_STATE_BYTES,
};
use std::collections::HashMap;

const MESSAGE_COLUMNS: &str =
    "message_uuid, session_uuid, parent_message_uuid, sender, text, attachments, created_at";
const MESSAGE_QUERY_BATCH_SIZE: usize = 100;

pub struct ConversationSnapshot {
    pub(super) session_uuid: Uuid,
    pub(super) messages: Vec<Message>,
    pub(super) state: Option<ConversationState>,
    derived: ConversationEnvelope,
    rows: Vec<crate::db::Row>,
    envelope: Value,
}

impl ConversationSnapshot {
    pub fn messages(&self) -> &[Message] {
        &self.messages
    }
    pub fn state(&self) -> Option<&ConversationState> {
        self.state.as_ref()
    }
    pub fn evidence(&self) -> Vec<AnswerEvidence> {
        self.derived
            .evidence
            .iter()
            .filter(|entry| entry.matches(&self.messages))
            .cloned()
            .collect()
    }
    pub fn session_uuid(&self) -> Uuid {
        self.session_uuid
    }
}

impl<B: Backend> ChatDb<B> {
    pub fn conversation_snapshot(
        &self,
        session: Uuid,
        path: &[Uuid],
    ) -> Result<ConversationSnapshot> {
        if path.len() > conversation::MAX_HISTORY_MESSAGES {
            return Err(Error::UnsupportedOperation(
                "Conversation history is too large".into(),
            ));
        }
        let (envelope, rows) = self.backend.transaction(|tx| {
            let envelope = session_envelope(tx, session)?.ok_or(Error::NotFound {
                entity: EntityType::Session,
                id: session,
            })?;
            let mut rows = Vec::with_capacity(path.len());
            let mut remaining_bytes = conversation::MAX_HISTORY_BYTES;
            for ids in path.chunks(MESSAGE_QUERY_BATCH_SIZE) {
                let mut batch = message_rows(tx, ids, &mut remaining_bytes)?.ok_or_else(|| {
                    Error::UnsupportedOperation("Conversation history is too large".into())
                })?;
                for id in ids {
                    let row = batch.remove(id).ok_or(Error::NotFound {
                        entity: EntityType::Message,
                        id: *id,
                    })?;
                    rows.push(row);
                }
            }
            if has_existing_parent(tx, &rows)? {
                return Err(Error::UnsupportedOperation(
                    "Conversation history omits an existing ancestor".into(),
                ));
            }
            Ok((envelope, rows))
        })?;
        let messages = rows
            .iter()
            .map(|row| self.message_from_row(row))
            .collect::<Result<Vec<_>>>()?;
        if messages
            .iter()
            .any(|message| message.session_uuid != session)
        {
            return Err(Error::UnsupportedOperation(
                "History belongs to another conversation".into(),
            ));
        }
        conversation::validate_path(&messages)
            .map_err(|e| Error::UnsupportedOperation(e.to_string()))?;
        let derived = self
            .decode_conversation(&envelope, session)
            .unwrap_or_else(|| ConversationEnvelope::empty(session));
        let state = derived.summary_state();
        Ok(ConversationSnapshot {
            session_uuid: session,
            messages,
            state,
            derived,
            rows,
            envelope,
        })
    }

    fn decode_conversation(&self, value: &Value, session: Uuid) -> Option<ConversationEnvelope> {
        let Value::Blob(blob) = value else {
            return None;
        };
        if blob.len() > MAX_STATE_BYTES + 1024 {
            return None;
        }
        let bytes = crypto::decrypt_blob(blob, &self.key).ok()?;
        ConversationEnvelope::decode(&bytes, session)
    }

    pub fn conversation_snapshot_matches(&self, snapshot: &ConversationSnapshot) -> Result<bool> {
        self.backend
            .transaction(|tx| snapshot_matches(tx, snapshot, false))
    }

    pub fn replace_conversation_state(
        &self,
        snapshot: &mut ConversationSnapshot,
        state: Option<ConversationState>,
    ) -> Result<bool> {
        if let Some(state) = &state {
            if state.session_uuid != snapshot.session_uuid
                || state.coverage(&snapshot.messages).is_none()
            {
                return Err(Error::UnsupportedOperation(
                    "Summary does not match the captured history".into(),
                ));
            }
            state
                .validate()
                .map_err(|_| Error::UnsupportedOperation("Invalid conversation state".into()))?;
        }
        let mut derived = snapshot.derived.clone();
        derived.summary = state.as_ref().map(|state| state.summary.clone());
        let envelope = self.encode_conversation(&derived)?;
        let applied = self.replace_conversation_envelope(snapshot, envelope.clone())?;
        if applied {
            snapshot.envelope = envelope;
            snapshot.state = state;
            snapshot.derived = derived;
        }
        Ok(applied)
    }

    fn encode_conversation(&self, derived: &ConversationEnvelope) -> Result<Value> {
        if derived.summary.is_none() && derived.evidence.is_empty() {
            return Ok(Value::Null);
        }
        let bytes = serde_json::to_vec(derived)?;
        if bytes.len() > MAX_STATE_BYTES {
            return Err(Error::UnsupportedOperation(
                "Conversation state is too large".into(),
            ));
        }
        Ok(Value::Blob(crypto::encrypt_blob(&bytes, &self.key)?))
    }

    pub fn save_answer_evidence(
        &self,
        snapshot: &ConversationSnapshot,
        answer: Uuid,
        passages: Vec<crate::retrieval::IncludedPassage>,
    ) -> Result<bool> {
        if !conversation::valid_answer_passages(&passages) {
            return Ok(false);
        }
        let mut path: Vec<_> = snapshot.messages.iter().map(|m| m.uuid).collect();
        path.push(answer);
        let mut current = self.conversation_snapshot(snapshot.session_uuid, &path)?;
        if current.envelope != snapshot.envelope
            || current.rows[..snapshot.rows.len()] != snapshot.rows
        {
            return Ok(false);
        }
        let saved = current
            .messages
            .last()
            .ok_or(Error::UnsupportedOperation("Missing saved answer".into()))?;
        let sources = crate::retrieval::parse_grounded_assistant_text(&saved.text).sources;
        if !passages.iter().all(|passage| {
            sources
                .iter()
                .any(|source| passage.locator.matches_source(source))
        }) {
            return Ok(false);
        }
        if !current.derived.add_evidence(&current.messages, passages) {
            return Ok(false);
        }
        let envelope = self.encode_conversation(&current.derived)?;
        self.replace_conversation_envelope(&current, envelope)
    }

    fn replace_conversation_envelope(
        &self,
        snapshot: &ConversationSnapshot,
        envelope: Value,
    ) -> Result<bool> {
        self.backend.transaction(|tx| {
            if !snapshot_matches(tx, snapshot, true)? {
                return Ok(false);
            }
            Ok(tx.execute(
                "UPDATE sessions SET conversation_state = ? WHERE session_uuid = ?",
                &[envelope, Value::Text(snapshot.session_uuid.to_string())],
            )? == 1)
        })
    }

    pub(super) fn invalidate_conversation_for_edit<T: BackendTx>(
        &self,
        tx: &T,
        session: Uuid,
        edited: Uuid,
    ) -> Result<()> {
        let Some(envelope) = session_envelope(tx, session)? else {
            return Ok(());
        };
        if envelope == Value::Null {
            return Ok(());
        }
        let Some(mut derived) = self.decode_conversation(&envelope, session) else {
            tx.execute(
                "UPDATE sessions SET conversation_state = NULL WHERE session_uuid = ?",
                &[Value::Text(session.to_string())],
            )?;
            return Ok(());
        };
        let mut changed = false;
        if let Some(summary) = &derived.summary
            && depends_on(tx, summary.covered_boundary_message_uuid, edited)?
        {
            derived.summary = None;
            changed = true;
        }
        let mut retained = Vec::new();
        for entry in derived.evidence.drain(..) {
            if depends_on(tx, entry.assistant_message_uuid, edited)? {
                changed = true;
            } else {
                retained.push(entry);
            }
        }
        derived.evidence = retained;
        if changed {
            tx.execute(
                "UPDATE sessions SET conversation_state = ? WHERE session_uuid = ?",
                &[
                    self.encode_conversation(&derived)?,
                    Value::Text(session.to_string()),
                ],
            )?;
        }
        Ok(())
    }
}

fn depends_on<T: BackendTx>(tx: &T, boundary: Uuid, edited: Uuid) -> Result<bool> {
    let rows = tx.query("WITH RECURSIVE prefix(id, parent) AS (
        SELECT message_uuid, parent_message_uuid FROM messages WHERE message_uuid = ?
        UNION ALL
        SELECT m.message_uuid, m.parent_message_uuid FROM messages m JOIN prefix p ON m.message_uuid = p.parent
        LIMIT 20001) SELECT id FROM prefix", &[Value::Text(boundary.to_string())])?;
    let edited = Value::Text(edited.to_string());
    Ok(rows.is_empty()
        || rows.len() > conversation::MAX_HISTORY_MESSAGES
        || rows.iter().any(|row| row.first() == Some(&edited)))
}

fn session_envelope<T: BackendTx>(tx: &T, session: Uuid) -> Result<Option<Value>> {
    Ok(tx
        .query_row(
            "SELECT conversation_state FROM sessions WHERE session_uuid = ?",
            &[Value::Text(session.to_string())],
        )?
        .and_then(|row| row.into_iter().next()))
}

fn message_row<T: BackendTx>(tx: &T, id: Uuid) -> Result<Option<crate::db::Row>> {
    tx.query_row(
        &format!("SELECT {MESSAGE_COLUMNS} FROM messages WHERE message_uuid = ?"),
        &[Value::Text(id.to_string())],
    )
}

fn message_rows<T: BackendTx>(
    tx: &T,
    ids: &[Uuid],
    remaining_bytes: &mut usize,
) -> Result<Option<HashMap<Uuid, crate::db::Row>>> {
    let placeholders = vec!["?"; ids.len()].join(", ");
    let params = ids
        .iter()
        .map(|id| Value::Text(id.to_string()))
        .collect::<Vec<_>>();
    let size = tx
        .query_row(
            &format!(
                "SELECT COALESCE(SUM(octet_length(text) + COALESCE(octet_length(attachments), 0)), 0)
                 FROM messages WHERE message_uuid IN ({placeholders})"
            ),
            &params,
        )?
        .ok_or_else(|| Error::Row("Missing message payload size".into()))?
        .get_i64(0)?;
    let Ok(size) = usize::try_from(size) else {
        return Ok(None);
    };
    let Some(remaining) = remaining_bytes.checked_sub(size) else {
        return Ok(None);
    };
    let rows = tx
        .query(
            &format!(
                "SELECT {MESSAGE_COLUMNS} FROM messages WHERE message_uuid IN ({placeholders})"
            ),
            &params,
        )?
        .into_iter()
        .map(|row| Ok((Uuid::parse_str(&row.get_string(0)?)?, row)))
        .collect::<Result<_>>()?;
    *remaining_bytes = remaining;
    Ok(Some(rows))
}

fn has_existing_parent<T: BackendTx>(tx: &T, rows: &[crate::db::Row]) -> Result<bool> {
    let Some(root) = rows.first() else {
        return Ok(false);
    };
    let Some(parent) = root.get_optional_string(2)? else {
        return Ok(false);
    };
    Ok(message_row(tx, Uuid::parse_str(&parent)?)?.is_some())
}

pub(super) fn snapshot_matches<T: BackendTx>(
    tx: &T,
    snapshot: &ConversationSnapshot,
    compare_envelope: bool,
) -> Result<bool> {
    let Some(envelope) = session_envelope(tx, snapshot.session_uuid)? else {
        return Ok(false);
    };
    if (compare_envelope && envelope != snapshot.envelope)
        || has_existing_parent(tx, &snapshot.rows)?
    {
        return Ok(false);
    }
    let mut remaining_bytes = conversation::MAX_HISTORY_BYTES;
    for (messages, expected_rows) in snapshot
        .messages
        .chunks(MESSAGE_QUERY_BATCH_SIZE)
        .zip(snapshot.rows.chunks(MESSAGE_QUERY_BATCH_SIZE))
    {
        let ids = messages
            .iter()
            .map(|message| message.uuid)
            .collect::<Vec<_>>();
        let Some(rows) = message_rows(tx, &ids, &mut remaining_bytes)? else {
            return Ok(false);
        };
        for (message, expected) in messages.iter().zip(expected_rows) {
            if rows.get(&message.uuid) != Some(expected) {
                return Ok(false);
            }
        }
    }
    Ok(true)
}

#[cfg(test)]
#[cfg(feature = "sqlite")]
mod tests {
    use super::*;
    fn seeded() -> (ChatDb<crate::db::SqliteBackend>, Uuid, Vec<Message>) {
        let db = ChatDb::open_in_memory(vec![7; 32]).unwrap();
        let session = db.create_session("Original title").unwrap();
        let first = db
            .insert_message(session.uuid, "self", "Keep data offline", None, vec![])
            .unwrap();
        let answer = db
            .insert_message(
                session.uuid,
                "other",
                "A suggestion",
                Some(first.uuid),
                vec![],
            )
            .unwrap();
        let current = db
            .insert_message(
                session.uuid,
                "self",
                "Next question",
                Some(answer.uuid),
                vec![],
            )
            .unwrap();
        (db, session.uuid, vec![first, answer, current])
    }
    fn state(session: Uuid, messages: &[Message], text: &str) -> ConversationState {
        ConversationState::new(session, &messages[..2], text.into()).unwrap()
    }
    fn snapshot(
        db: &ChatDb<crate::db::SqliteBackend>,
        session: Uuid,
        messages: &[Message],
    ) -> ConversationSnapshot {
        db.conversation_snapshot(
            session,
            &messages.iter().map(|m| m.uuid).collect::<Vec<_>>(),
        )
        .unwrap()
    }

    fn passages() -> Vec<crate::retrieval::IncludedPassage> {
        vec![crate::retrieval::passage_fixture().0]
    }

    fn sourced_answer(
        db: &ChatDb<crate::db::SqliteBackend>,
        captured: &ConversationSnapshot,
    ) -> Message {
        let source = crate::retrieval::GroundedSource::LocalNote {
            reference: crate::notes::NoteSourceReference {
                collection_id: "123e4567-e89b-12d3-a456-426614174000".into(),
                collection_label: None,
                document_id: "trip.md".into(),
                indexed_revision: "a".repeat(64),
                title: "Trip".into(),
                section: None,
            },
        };
        let text =
            crate::retrieval::finalize_grounded_assistant_text("Saved answer", &[source]).unwrap();
        db.insert_message_guarded(
            captured.session_uuid,
            "other",
            &text,
            captured.messages.last().map(|m| m.uuid),
            vec![],
            Some(captured),
        )
        .unwrap()
    }

    #[test]
    fn migrated_orphan_history_supports_summary_restore_and_continuation() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("conversation.db");
        let db = ChatDb::open_sqlite_with_defaults(&file, vec![7; 32]).unwrap();
        let session = db.create_session("Memory").unwrap().uuid;
        let deleted = db
            .insert_message(session, "other", "Deleted parent", None, vec![])
            .unwrap();
        let question = db
            .insert_message(
                session,
                "self",
                "Keep data offline",
                Some(deleted.uuid),
                vec![],
            )
            .unwrap();
        let answer = db
            .insert_message(session, "other", "Understood", Some(question.uuid), vec![])
            .unwrap();
        let full = vec![question.clone(), answer];
        db.backend
            .execute_batch(
                "ALTER TABLE sessions DROP COLUMN conversation_state;
            ALTER TABLE sessions ADD COLUMN deleted_at INTEGER;
            ALTER TABLE messages ADD COLUMN deleted_at INTEGER;
            PRAGMA user_version = 4;",
            )
            .unwrap();
        db.backend
            .execute(
                "UPDATE messages SET deleted_at = 1 WHERE message_uuid = ?",
                &[Value::Text(deleted.uuid.to_string())],
            )
            .unwrap();
        drop(db);
        let db = ChatDb::open_sqlite_with_defaults(&file, vec![7; 32]).unwrap();
        assert!(db.get_message(deleted.uuid).unwrap().is_none());
        assert_eq!(
            db.get_message(question.uuid)
                .unwrap()
                .unwrap()
                .parent_message_uuid,
            Some(deleted.uuid)
        );
        let mut captured = snapshot(&db, session, &full);
        let memory = ConversationState::new(session, &full, "Keep data offline".into()).unwrap();
        assert!(
            db.replace_conversation_state(&mut captured, Some(memory.clone()))
                .unwrap()
        );
        drop(captured);
        drop(db);
        let db = ChatDb::open_sqlite_with_defaults(&file, vec![7; 32]).unwrap();
        let reopened = snapshot(&db, session, &full);
        assert_eq!(reopened.state(), Some(&memory));
        let user = db
            .insert_message(session, "self", "Continue", Some(full[1].uuid), vec![])
            .unwrap();
        let mut continued = full.clone();
        continued.push(user.clone());
        let captured = snapshot(&db, session, &continued);
        assert_eq!(captured.state(), Some(&memory));
        assert!(
            db.insert_message_guarded(
                session,
                "other",
                "Reply",
                Some(user.uuid),
                vec![],
                Some(&captured)
            )
            .is_ok()
        );
        let sibling = db
            .insert_message(
                session,
                "other",
                "Other branch",
                Some(question.uuid),
                vec![],
            )
            .unwrap();
        assert!(memory.coverage(&[question, sibling]).is_none());
        assert_eq!(snapshot(&db, session, &full).state(), Some(&memory));
    }

    #[test]
    fn snapshots_reject_omitted_ancestors_and_malformed_paths() {
        let (db, session, messages) = seeded();
        let other = db.create_session("Other").unwrap().uuid;
        let foreign = db
            .insert_message(other, "self", "Other root", None, vec![])
            .unwrap();
        for path in [
            vec![messages[1].uuid, messages[2].uuid],
            vec![messages[0].uuid, messages[2].uuid],
            vec![messages[0].uuid, messages[0].uuid],
            vec![messages[0].uuid, foreign.uuid],
        ] {
            assert!(db.conversation_snapshot(session, &path).is_err());
        }
    }

    #[test]
    fn restored_parent_invalidates_orphan_snapshots_and_guarded_writes() {
        let (db, session, mut messages) = seeded();
        let parent = messages.remove(0);
        let row = message_row(&db.backend, parent.uuid).unwrap().unwrap();
        db.backend
            .execute(
                "DELETE FROM messages WHERE message_uuid = ?",
                &[Value::Text(parent.uuid.to_string())],
            )
            .unwrap();
        let mut captured = snapshot(&db, session, &messages);
        assert!(db.conversation_snapshot_matches(&captured).unwrap());
        db.backend
            .execute(
                &format!("INSERT INTO messages ({MESSAGE_COLUMNS}) VALUES (?, ?, ?, ?, ?, ?, ?)"),
                &row,
            )
            .unwrap();
        assert!(!db.conversation_snapshot_matches(&captured).unwrap());
        assert!(!db.replace_conversation_state(&mut captured, None).unwrap());
        assert!(
            db.insert_message_guarded(
                session,
                "other",
                "Stale reply",
                Some(messages[1].uuid),
                vec![],
                Some(&captured)
            )
            .is_err()
        );
    }

    #[test]
    fn evidence_and_summary_survive_encrypted_reopen_and_branch_selection() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("evidence.db");
        let db = ChatDb::open_sqlite_with_defaults(&file, vec![7; 32]).unwrap();
        let session = db.create_session("Sources").unwrap().uuid;
        let question = db
            .insert_message(session, "self", "Tell me about my trip", None, vec![])
            .unwrap();
        let captured = snapshot(&db, session, std::slice::from_ref(&question));
        let answer = sourced_answer(&db, &captured);
        assert!(
            db.save_answer_evidence(&captured, answer.uuid, passages())
                .unwrap()
        );
        let full = vec![question.clone(), answer];
        let mut restored = snapshot(&db, session, &full);
        assert!(restored.state().is_none());
        assert_eq!(restored.evidence()[0].passages, passages());
        let Value::Blob(bytes) = &restored.envelope else {
            panic!("encrypted")
        };
        assert!(!bytes.windows(7).any(|w| w == b"trip.md"));
        let memory = ConversationState::new(session, &full, "Trip discussed".into()).unwrap();
        assert!(
            db.replace_conversation_state(&mut restored, Some(memory.clone()))
                .unwrap()
        );
        drop(restored);
        drop(captured);
        drop(db);
        let db = ChatDb::open_sqlite_with_defaults(&file, vec![7; 32]).unwrap();
        let reopened = snapshot(&db, session, &full);
        assert_eq!(reopened.evidence().len(), 1);
        assert_eq!(reopened.state(), Some(&memory));
        let sibling = db
            .insert_message(
                session,
                "other",
                "Other branch",
                Some(question.uuid),
                vec![],
            )
            .unwrap();
        assert!(
            snapshot(&db, session, &[question, sibling])
                .evidence()
                .is_empty()
        );
        assert_eq!(snapshot(&db, session, &full).evidence().len(), 1);
    }

    #[test]
    fn summary_updates_preserve_evidence_and_edits_invalidate_only_dependents() {
        let (db, session, mut messages) = seeded();
        let captured = snapshot(&db, session, &messages);
        let answer = sourced_answer(&db, &captured);
        assert!(
            db.save_answer_evidence(&captured, answer.uuid, passages())
                .unwrap()
        );
        messages.push(answer);
        let mut current = snapshot(&db, session, &messages);
        let memory = state(session, &messages, "Memory");
        for next in [Some(memory.clone()), None, Some(memory)] {
            assert!(db.replace_conversation_state(&mut current, next).unwrap());
            assert_eq!(snapshot(&db, session, &messages).evidence().len(), 1);
        }
        db.update_message_text(messages[2].uuid, "Edited question")
            .unwrap();
        let current = snapshot(&db, session, &messages);
        assert!(current.state().is_some());
        assert!(current.evidence().is_empty());
    }

    #[test]
    fn evidence_write_races_and_failures_keep_the_answer_and_prior_state() {
        let (db, session, messages) = seeded();
        let captured = snapshot(&db, session, &messages);
        let answer = sourced_answer(&db, &captured);
        let mut other_writer = snapshot(&db, session, &messages);
        let memory = state(session, &messages, "Other writer");
        assert!(
            db.replace_conversation_state(&mut other_writer, Some(memory.clone()))
                .unwrap()
        );
        assert!(
            !db.save_answer_evidence(&captured, answer.uuid, passages())
                .unwrap()
        );
        assert_eq!(db.get_message(answer.uuid).unwrap().unwrap(), answer);
        db.backend.execute("CREATE TRIGGER fail_evidence BEFORE UPDATE OF conversation_state ON sessions BEGIN SELECT RAISE(ABORT, 'storage failure'); END", &[]).unwrap();
        assert!(
            db.save_answer_evidence(&other_writer, answer.uuid, passages())
                .is_err()
        );
        assert_eq!(db.get_message(answer.uuid).unwrap().unwrap(), answer);
        assert_eq!(snapshot(&db, session, &messages).state(), Some(&memory));
    }

    #[test]
    fn evidence_rejects_changed_history_missing_citations_and_deleted_sessions() {
        let (db, session, messages) = seeded();
        let captured = snapshot(&db, session, &messages);
        let uncited = db
            .insert_message_guarded(
                session,
                "other",
                "No sources",
                Some(messages[2].uuid),
                vec![],
                Some(&captured),
            )
            .unwrap();
        assert!(
            !db.save_answer_evidence(&captured, uncited.uuid, passages())
                .unwrap()
        );
        let answer = sourced_answer(&db, &captured);
        db.update_message_text(messages[0].uuid, "Changed history")
            .unwrap();
        assert!(
            !db.save_answer_evidence(&captured, answer.uuid, passages())
                .unwrap()
        );
        db.delete_session(session).unwrap();
        assert!(
            db.save_answer_evidence(&captured, answer.uuid, passages())
                .is_err()
        );
    }

    #[test]
    fn encrypted_memory_survives_titles_appends_and_recent_edits() {
        let (db, session, messages) = seeded();
        let original = db.get_session(session).unwrap().unwrap();
        let mut captured = snapshot(&db, session, &messages);
        let memory = state(session, &messages, "CONFIDENTIAL_SUMMARY_TEXT");
        assert!(
            db.replace_conversation_state(&mut captured, Some(memory.clone()))
                .unwrap()
        );
        assert_eq!(db.get_session(session).unwrap().unwrap(), original);
        let Value::Blob(bytes) = &captured.envelope else {
            panic!("encrypted blob")
        };
        assert!(!bytes.windows(12).any(|w| w == b"CONFIDENTIAL"));
        db.update_session_title(session, "New title").unwrap();
        db.insert_message(
            session,
            "other",
            "Later append",
            Some(messages[2].uuid),
            vec![],
        )
        .unwrap();
        db.update_message_text(messages[2].uuid, "Edited recent question")
            .unwrap();
        assert_eq!(snapshot(&db, session, &messages).state, Some(memory));
        db.update_message_text(messages[0].uuid, "Constraint changed")
            .unwrap();
        assert!(snapshot(&db, session, &messages).state.is_none());
        assert!(
            !db.replace_conversation_state(&mut captured, Some(state(session, &messages, "stale")))
                .unwrap()
        );
    }

    #[test]
    fn concurrent_replacements_clears_and_guarded_answers() {
        let (db, session, messages) = seeded();
        let mut first = snapshot(&db, session, &messages);
        let mut second = snapshot(&db, session, &messages);
        assert!(
            db.replace_conversation_state(
                &mut first,
                Some(state(session, &messages, "Current memory"))
            )
            .unwrap()
        );
        assert!(!db.replace_conversation_state(&mut second, None).unwrap());
        assert!(
            !db.replace_conversation_state(
                &mut second,
                Some(state(session, &messages, "Old memory"))
            )
            .unwrap()
        );
        assert!(
            db.insert_message_guarded(
                session,
                "other",
                "Answer",
                Some(messages[2].uuid),
                vec![],
                Some(&second)
            )
            .is_ok()
        );
        db.update_message_text(messages[0].uuid, "Edited from another caller")
            .unwrap();
        assert!(
            db.insert_message_guarded(
                session,
                "other",
                "Stale answer",
                Some(messages[2].uuid),
                vec![],
                Some(&second)
            )
            .is_err()
        );
        db.delete_session(session).unwrap();
        assert!(!db.replace_conversation_state(&mut first, None).unwrap());
        assert!(db.get_session(session).unwrap().is_none());
    }

    #[test]
    fn corrupt_state_does_not_block_chat_and_failed_write_keeps_previous() {
        let (db, session, messages) = seeded();
        db.backend
            .execute(
                "UPDATE sessions SET conversation_state = ? WHERE session_uuid = ?",
                &[Value::Blob(vec![0; 16]), Value::Text(session.to_string())],
            )
            .unwrap();
        let mut captured = snapshot(&db, session, &messages);
        assert!(captured.state.is_none());
        assert_eq!(db.get_messages(session).unwrap().len(), 3);
        assert!(
            db.replace_conversation_state(
                &mut captured,
                Some(state(session, &messages, "Valid memory"))
            )
            .unwrap()
        );
        let mut encoded = ConversationEnvelope::empty(session);
        encoded.summary = captured.state().map(|state| state.summary.clone());
        encoded.format_version = 1;
        assert!(
            ConversationEnvelope::decode(&serde_json::to_vec(&encoded).unwrap(), session).is_none()
        );
        for text in [" \n".to_owned(), "x".repeat(MAX_STATE_BYTES)] {
            let mut invalid = state(session, &messages, "Valid memory");
            invalid.summary.text = text;
            assert!(
                db.replace_conversation_state(&mut captured, Some(invalid))
                    .is_err()
            );
            assert_eq!(captured.state().unwrap().summary.text, "Valid memory");
        }
        let escaped = state(session, &messages, &"\u{0001}".repeat(MAX_STATE_BYTES / 2));
        assert!(escaped.validate().is_ok());
        assert!(
            db.replace_conversation_state(&mut captured, Some(escaped))
                .is_err()
        );
        assert_eq!(
            snapshot(&db, session, &messages)
                .state()
                .unwrap()
                .summary
                .text,
            "Valid memory"
        );
        db.backend.execute_batch("CREATE TRIGGER fail_memory BEFORE UPDATE OF conversation_state ON sessions BEGIN SELECT RAISE(ABORT, 'write failed'); END;").unwrap();
        assert!(
            db.replace_conversation_state(
                &mut captured,
                Some(state(session, &messages, "Replacement"))
            )
            .is_err()
        );
        assert_eq!(
            snapshot(&db, session, &messages)
                .state
                .unwrap()
                .summary
                .text,
            "Valid memory"
        );
    }
}
