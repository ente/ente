use std::sync::Arc;
use std::sync::atomic::{AtomicI64, Ordering};

use chrono::NaiveDateTime;

use super::*;
use crate::db::traits::{Clock, RandomUuidGen};
use crate::db::{ChatDb, SqliteBackend};
use crate::llm::{ToolCall, ToolValue};

struct TestClock(AtomicI64);

impl Clock for TestClock {
    fn now_us(&self) -> i64 {
        self.0.fetch_add(1_000, Ordering::Relaxed)
    }
}

fn local_ms(text: &str) -> i64 {
    timing::local_millis(NaiveDateTime::parse_from_str(text, "%Y-%m-%d %H:%M").unwrap()).unwrap()
}

const NOW: &str = "2026-11-12 14:30";

/// Confidence high enough for changes to apply directly.
const SURE: Option<f32> = Some(1.0);
/// Confidence in the band where changes are offered for confirmation.
const UNSURE: Option<f32> = Some(0.6);

fn db() -> ChatDb<SqliteBackend> {
    ChatDb::new(
        SqliteBackend::open_in_memory().unwrap(),
        vec![7; 32],
        Arc::new(TestClock(AtomicI64::new(local_ms(NOW) * 1000))),
        Arc::new(RandomUuidGen),
    )
    .unwrap()
}

fn call(name: &str, args: &[(&str, ToolValue)]) -> ToolCall {
    ToolCall {
        name: name.into(),
        arguments: args
            .iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    }
}

fn text(value: &str) -> ToolValue {
    ToolValue::Text(value.into())
}

struct Chat<'a> {
    db: &'a ChatDb<SqliteBackend>,
    session: Uuid,
    parent: Option<Uuid>,
}

impl Chat<'_> {
    fn send(&mut self, user: &str, calls: &[ToolCall]) -> TodoTurn {
        self.send_as(user, calls, SURE)
    }

    fn send_as(&mut self, user: &str, calls: &[ToolCall], confidence: Option<f32>) -> TodoTurn {
        let message = self
            .db
            .insert_message(self.session, "self", user, self.parent, vec![])
            .unwrap();
        let turn = self
            .db
            .apply_todo_calls(message.uuid, calls, local_ms(NOW), confidence)
            .unwrap();
        self.parent = Some(turn.reply.uuid);
        turn
    }
}

#[test]
fn chat_calls_save_list_and_complete_tasks_with_one_reply_each() {
    let db = db();
    let session = db.create_session("To Do").unwrap();
    let mut chat = Chat {
        db: &db,
        session: session.uuid,
        parent: None,
    };
    let saved = chat.send(
        "Buy apples tomorrow and call Lee at 4 PM. Also water plants someday",
        &[
            call(
                SAVE_TOOL,
                &[("title", text("buy apples")), ("when", text("tomorrow"))],
            ),
            call(
                SAVE_TOOL,
                &[("title", text("Call Lee")), ("when", text("at 4 PM"))],
            ),
            call(
                SAVE_TOOL,
                &[("title", text("Water plants")), ("when", text("someday"))],
            ),
        ],
    );
    assert_eq!(
        saved.reply.text,
        [
            "Saved “Buy apples”, due Fri 13 Nov 2026, 09:00. No time was given, so I used 9:00.",
            "Saved “Call Lee”, due Thu 12 Nov 2026, 16:00.",
            "Saved “Water plants”. I couldn't work out the deadline “someday”, so it has no due date.",
        ]
        .join("\n")
    );
    assert_eq!(saved.changes.len(), 3);
    assert_eq!(
        saved.reply.parent_message_uuid,
        chat.parent.and(saved.reply.parent_message_uuid)
    );
    let todos = db.list_todos().unwrap();
    assert_eq!(
        todos
            .iter()
            .map(|t| (t.title.as_str(), t.due_at_ms))
            .collect::<Vec<_>>(),
        [
            ("Buy apples", Some(local_ms("2026-11-13 09:00"))),
            ("Call Lee", Some(local_ms("2026-11-12 16:00"))),
            ("Water plants", None),
        ]
    );

    let listed = chat.send(
        "What's on my list?",
        &[call(LIST_TOOL, &[("filter", text("open"))])],
    );
    assert_eq!(
        listed.reply.text,
        "1. Call Lee — due Thu 12 Nov 2026, 16:00\n2. Buy apples — due Fri 13 Nov 2026, 09:00\n3. Water plants — no due date"
    );
    let done = chat.send(
        "The second one is done",
        &[call(COMPLETE_TOOL, &[("number", ToolValue::Integer(2))])],
    );
    assert_eq!(done.reply.text, "Marked “Buy apples” as done.");
    assert!(!db.get_todo(todos[0].id).unwrap().unwrap().is_open());

    let missing = chat.send(
        "Done with 3",
        &[call(COMPLETE_TOOL, &[("number", ToolValue::Integer(3))])],
    );
    assert!(
        missing.reply.text.starts_with("There's no task 3"),
        "{}",
        missing.reply.text
    );
    assert!(missing.changes.is_empty());

    db.create_todo("Call Lee about the trip", None).unwrap();
    let ambiguous = chat.send(
        "I called Lee",
        &[call(COMPLETE_TOOL, &[("task", text("Lee"))])],
    );
    assert!(
        ambiguous
            .reply
            .text
            .starts_with("Which one should I mark as done?\n1. Call Lee")
    );
    let chosen = chat.send(
        "the first",
        &[call(COMPLETE_TOOL, &[("number", ToolValue::Integer(1))])],
    );
    assert_eq!(chosen.reply.text, "Marked “Call Lee” as done.");
    let unknown = chat.send(
        "I finished the dentist",
        &[call(COMPLETE_TOOL, &[("task", text("dentist"))])],
    );
    assert_eq!(
        unknown.reply.text,
        "I couldn't find an open task matching “dentist”."
    );

    let source = db
        .get_message(saved.reply.parent_message_uuid.unwrap())
        .unwrap()
        .unwrap();
    assert!(
        db.apply_todo_calls(source.uuid, &[], local_ms(NOW), SURE)
            .is_err()
    );
    assert!(
        db.apply_todo_calls(saved.reply.uuid, &[], local_ms(NOW), SURE)
            .is_err()
    );
}

#[test]
fn unsure_calls_offer_changes_and_make_them_once_confirmed() {
    let db = db();
    let session = db.create_session("To Do").unwrap();
    let mut chat = Chat {
        db: &db,
        session: session.uuid,
        parent: None,
    };
    db.create_todo("Pay rent", None).unwrap();
    let turn = chat.send_as(
        "Buy stamps tomorrow, and I paid the rent",
        &[
            call(
                SAVE_TOOL,
                &[("title", text("Buy stamps")), ("when", text("tomorrow"))],
            ),
            call(COMPLETE_TOOL, &[("task", text("rent"))]),
        ],
        UNSURE,
    );
    // Both changes are only offered.
    assert_eq!(
        turn.reply.text,
        "Add “Buy stamps”, due Fri 13 Nov 2026, 09:00 to your To Dos? No time was given, so I used 9:00.\nMark “Pay rent” as done?"
    );
    assert_eq!(turn.proposed.len(), 2);
    assert!(turn.changes.is_empty());
    let list = |db: &ChatDb<SqliteBackend>| {
        db.list_todos()
            .unwrap()
            .into_iter()
            .map(|todo| (todo.title.clone(), todo.is_open()))
            .collect::<Vec<_>>()
    };
    assert_eq!(list(&db), [("Pay rent".to_owned(), true)]);
    let state = db.todo_turn_state(turn.reply.uuid).unwrap().unwrap();
    assert!(state.pending && !state.changed);

    // The model hears the offer is still open.
    let history = db.tool_history(std::slice::from_ref(&turn.reply)).unwrap();
    assert_eq!(history[&turn.reply.uuid].proposal, Some(false));

    let made = db.confirm_todo_turn(turn.reply.uuid).unwrap();
    assert_eq!(made.len(), 2);
    assert_eq!(
        list(&db),
        [
            ("Pay rent".to_owned(), false),
            ("Buy stamps".to_owned(), true)
        ]
    );
    let added = made[0].after.clone().unwrap();
    assert_eq!(added.due_at_ms, Some(local_ms("2026-11-13 09:00")));
    let state = db.todo_turn_state(turn.reply.uuid).unwrap().unwrap();
    assert!(!state.pending && state.changed);
    assert_eq!(
        db.tool_history(std::slice::from_ref(&turn.reply)).unwrap()[&turn.reply.uuid].proposal,
        Some(true)
    );
    assert!(db.confirm_todo_turn(turn.reply.uuid).is_err());

    // Undo reverts both.
    db.undo_todo_turn(turn.reply.uuid).unwrap();
    assert_eq!(list(&db), [("Pay rent".to_owned(), true)]);
}

#[test]
fn offers_conflict_with_edits_made_since() {
    let db = db();
    let session = db.create_session("To Do").unwrap();
    let mut chat = Chat {
        db: &db,
        session: session.uuid,
        parent: None,
    };
    let rent = db.create_todo("Pay rent", None).unwrap();
    let turn = chat.send_as(
        "I paid the rent",
        &[call(COMPLETE_TOOL, &[("task", text("rent"))])],
        UNSURE,
    );
    db.update_todo(rent.id, rent.version, "Pay the rent", None)
        .unwrap();
    assert!(db.confirm_todo_turn(turn.reply.uuid).is_err());
    assert!(db.list_todos().unwrap()[0].is_open());
}

#[test]
fn calls_without_a_confidence_are_offered_and_lists_always_run() {
    let db = db();
    let session = db.create_session("To Do").unwrap();
    let mut chat = Chat {
        db: &db,
        session: session.uuid,
        parent: None,
    };
    let saved = chat.send(
        "Buy stamps",
        &[call(SAVE_TOOL, &[("title", text("Buy stamps"))])],
    );
    // Nothing to confirm on a turn that made its changes.
    assert!(db.confirm_todo_turn(saved.reply.uuid).is_err());
    let offered = chat.send_as(
        "Buy milk",
        &[call(SAVE_TOOL, &[("title", text("Buy milk"))])],
        None,
    );
    assert_eq!(offered.proposed.len(), 1);
    assert_eq!(db.list_todos().unwrap().len(), 1);
    let listed = chat.send_as(
        "What's on my list?",
        &[call(LIST_TOOL, &[("filter", text("open"))])],
        UNSURE,
    );
    assert_eq!(listed.reply.text, "1. Buy stamps — no due date");
    assert!(listed.proposed.is_empty());
}

#[test]
fn undo_reverts_a_turn_once_and_refuses_after_later_edits() {
    let db = db();
    let session = db.create_session("To Do").unwrap();
    let mut chat = Chat {
        db: &db,
        session: session.uuid,
        parent: None,
    };
    let existing = db.create_todo("Pay rent", None).unwrap();
    let turn = chat.send(
        "Add stamps and I paid rent",
        &[
            call(SAVE_TOOL, &[("title", text("Buy stamps"))]),
            call(COMPLETE_TOOL, &[("task", text("rent"))]),
        ],
    );
    assert_eq!(
        db.todo_turn_state(turn.reply.uuid).unwrap(),
        Some(TodoTurnState {
            changed: true,
            undone: false,
            pending: false,
        })
    );
    db.undo_todo_turn(turn.reply.uuid).unwrap();
    let todos = db.list_todos().unwrap();
    assert_eq!(todos.len(), 1);
    assert!(todos[0].is_open());
    assert_eq!(todos[0].version, existing.version + 2);
    assert!(db.undo_todo_turn(turn.reply.uuid).is_err());
    assert!(db.todo_turn_state(turn.reply.uuid).unwrap().unwrap().undone);

    let again = chat.send("Add milk", &[call(SAVE_TOOL, &[("title", text("milk"))])]);
    let milk = again.changes[0].after.clone().unwrap();
    db.update_todo(milk.id, milk.version, "Oat milk", None)
        .unwrap();
    assert!(db.undo_todo_turn(again.reply.uuid).is_err());
    assert_eq!(db.list_todos().unwrap().len(), 2);

    let listed = chat.send("List", &[call(LIST_TOOL, &[("filter", text("all"))])]);
    assert!(db.undo_todo_turn(listed.reply.uuid).is_err());
}

#[test]
fn history_and_alarms_follow_stored_turns_and_open_deadlines() {
    let db = db();
    let session = db.create_session("To Do").unwrap();
    let mut chat = Chat {
        db: &db,
        session: session.uuid,
        parent: None,
    };
    let calls = [
        call(
            SAVE_TOOL,
            &[("title", text("Late")), ("when", text("Friday at 6 PM"))],
        ),
        call(
            SAVE_TOOL,
            &[("title", text("Soon")), ("when", text("in 20 minutes"))],
        ),
    ];
    let turn = chat.send("Late on Friday at 6 PM, and soon in 20 minutes", &calls);
    let messages = db.get_messages(session.uuid).unwrap();
    let history = db.tool_history(&messages).unwrap();
    assert_eq!(history.len(), 1);
    assert_eq!(history[&turn.reply.uuid].calls, calls);
    assert!(!history[&turn.reply.uuid].undone);

    let alarms = db.todo_alarms(local_ms(NOW), 10).unwrap();
    assert_eq!(
        alarms.iter().map(|a| a.title.as_str()).collect::<Vec<_>>(),
        ["Soon", "Late"]
    );
    assert_eq!(db.todo_alarms(local_ms(NOW), 1).unwrap().len(), 1);
    let soon = db.get_todo(alarms[0].todo_id).unwrap().unwrap();
    let moved = db
        .update_todo(
            soon.id,
            soon.version,
            "Soon",
            Some(local_ms("2026-11-12 15:30")),
        )
        .unwrap();
    let moved_alarm = &db.todo_alarms(local_ms(NOW), 10).unwrap()[0];
    assert_ne!(moved_alarm.key, alarms[0].key);
    db.set_todo_completed(moved.id, moved.version, true)
        .unwrap();
    assert_eq!(db.todo_alarms(local_ms(NOW), 10).unwrap().len(), 1);
    assert!(
        db.todo_alarms(local_ms("2026-11-20 00:00"), 10)
            .unwrap()
            .is_empty()
    );

    db.delete_session(session.uuid).unwrap();
    assert!(db.tool_history(&messages).unwrap().is_empty());
    assert_eq!(db.list_todos().unwrap().len(), 2);
}

#[test]
fn manual_edits_check_versions_and_titles() {
    let db = db();
    let todo = db.create_todo("  read   book ", None).unwrap();
    assert_eq!(todo.title, "Read book");
    assert!(db.create_todo(" ", None).is_err());
    let renamed = db
        .update_todo(todo.id, todo.version, "Read the book", Some(1))
        .unwrap();
    assert_eq!(renamed.version, 2);
    assert!(
        db.update_todo(todo.id, todo.version, "Stale", None)
            .is_err()
    );
    let done = db
        .set_todo_completed(renamed.id, renamed.version, true)
        .unwrap();
    assert_eq!(
        db.set_todo_completed(done.id, done.version, true).unwrap(),
        done
    );
    assert!(db.delete_todo(done.id, renamed.version).is_err());
    db.delete_todo(done.id, done.version).unwrap();
    assert!(db.get_todo(done.id).unwrap().is_none());
}

#[test]
fn version_six_databases_gain_to_do_tables_and_keep_chats() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("chat.db");
    let session = {
        let db = ChatDb::open_sqlite_with_defaults(&path, vec![7; 32]).unwrap();
        let session = db.create_session("Kept").unwrap();
        db.backend
            .execute_batch("DROP TABLE todo_turns; DROP TABLE todos; PRAGMA user_version = 6;")
            .unwrap();
        session
    };
    let db = ChatDb::open_sqlite_with_defaults(&path, vec![7; 32]).unwrap();
    assert_eq!(db.get_session(session.uuid).unwrap().unwrap().title, "Kept");
    assert_eq!(
        db.backend
            .query_row("PRAGMA user_version", &[])
            .unwrap()
            .unwrap()
            .get_i64(0)
            .unwrap(),
        7
    );
    db.create_todo("Works", None).unwrap();
}
