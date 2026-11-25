use std::sync::{
    Arc,
    atomic::{AtomicI64, Ordering},
};

use chrono::NaiveDateTime;
use uuid::Uuid;

use crate::db::chat::ConversationSnapshot;
use crate::db::{ChatDb, Clock, Message, RandomUuidGen, SqliteBackend};
use crate::llm::{ToolCall, ToolOutcome, ToolValue};
use crate::todo::timing;
use crate::tools::turn::{self as tool_turn, ToolTurnState};

pub(crate) struct TestClock(AtomicI64);

impl Clock for TestClock {
    fn now_us(&self) -> i64 {
        self.0.fetch_add(1_000, Ordering::Relaxed)
    }
}

pub(crate) fn zone() -> chrono::FixedOffset {
    chrono::FixedOffset::east_opt(5 * 3600 + 30 * 60).unwrap()
}

pub(crate) fn local_ms(text: &str) -> i64 {
    timing::local_millis(
        NaiveDateTime::parse_from_str(text, "%Y-%m-%d %H:%M").unwrap(),
        &zone(),
    )
    .unwrap()
}

pub(crate) const NOW: &str = "2026-11-12 14:30";

pub(crate) const SURE: Option<f32> = Some(1.0);
pub(crate) const UNSURE: Option<f32> = Some(0.6);

impl TestClock {
    pub(crate) fn set(&self, at: i64) {
        self.0.store(at * 1000, Ordering::Relaxed);
    }
}

pub(crate) fn db() -> ChatDb<SqliteBackend> {
    db_with_clock().0
}

pub(crate) fn db_with_clock() -> (ChatDb<SqliteBackend>, Arc<TestClock>) {
    let clock = Arc::new(TestClock(AtomicI64::new(local_ms(NOW) * 1000)));
    let db = ChatDb::new(
        SqliteBackend::open_in_memory().unwrap(),
        vec![7; 32],
        clock.clone(),
        Arc::new(RandomUuidGen),
    )
    .unwrap();
    (db, clock)
}

pub(crate) fn call(name: &str, args: &[(&str, ToolValue)]) -> ToolCall {
    ToolCall {
        name: name.into(),
        arguments: args
            .iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    }
}

pub(crate) fn text(value: &str) -> ToolValue {
    ToolValue::Text(value.into())
}

pub(crate) struct ToolTurn {
    pub(crate) reply: Message,
    pub(crate) state: ToolTurnState,
}

pub(crate) fn finish(
    db: &ChatDb<SqliteBackend>,
    snapshot: &ConversationSnapshot,
    calls: &[ToolCall],
    confidence: Option<f32>,
) -> crate::db::Result<ToolTurn> {
    let outcome = ToolOutcome {
        calls: calls.to_vec(),
        call_probability: confidence,
        ..Default::default()
    };
    let finished = tool_turn::finish_reply(db, snapshot, "", vec![], Some(&outcome), &zone())?;
    Ok(ToolTurn {
        reply: finished.message,
        state: finished.tool_turn.unwrap(),
    })
}

pub(crate) struct Chat<'a> {
    db: &'a ChatDb<SqliteBackend>,
    pub(crate) session: Uuid,
    pub(crate) path: Vec<Uuid>,
}

impl<'a> Chat<'a> {
    pub(crate) fn new(db: &'a ChatDb<SqliteBackend>) -> Self {
        let session = db.create_session("To Do").unwrap();
        Self {
            db,
            session: session.uuid,
            path: Vec::new(),
        }
    }

    pub(crate) fn send(&mut self, user: &str, calls: &[ToolCall]) -> ToolTurn {
        self.send_as(user, calls, SURE)
    }

    pub(crate) fn user(&mut self, user: &str) {
        let message = self
            .db
            .insert_message(
                self.session,
                "self",
                user,
                self.path.last().copied(),
                vec![],
            )
            .unwrap();
        self.path.push(message.uuid);
    }

    pub(crate) fn send_as(
        &mut self,
        user: &str,
        calls: &[ToolCall],
        confidence: Option<f32>,
    ) -> ToolTurn {
        self.user(user);
        let turn = self.answer(calls, confidence).unwrap();
        self.path.push(turn.reply.uuid);
        turn
    }

    pub(crate) fn answer(
        &self,
        calls: &[ToolCall],
        confidence: Option<f32>,
    ) -> crate::db::Result<ToolTurn> {
        let snapshot = self.snapshot();
        finish(self.db, &snapshot, calls, confidence)
    }

    pub(crate) fn snapshot(&self) -> ConversationSnapshot {
        self.db
            .conversation_snapshot(self.session, &self.path)
            .unwrap()
    }

    pub(crate) fn back(&mut self) {
        self.path.pop();
    }
}

pub(crate) fn state(db: &ChatDb<SqliteBackend>, reply: &Message) -> Option<ToolTurnState> {
    tool_turn::states(db, reply.session_uuid)
        .unwrap()
        .remove(&reply.uuid)
}
