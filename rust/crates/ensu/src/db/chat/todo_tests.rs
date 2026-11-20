use std::sync::Arc;
use std::sync::atomic::{AtomicI64, Ordering};

use chrono::NaiveDateTime;

use super::*;
use crate::db::chat::ConversationSnapshot;
use crate::db::chat::tool_turn::{Confirm, ToolTurnState, Undo};
use crate::db::models::Message;
use crate::db::traits::{Clock, RandomUuidGen};
use crate::db::{ChatDb, SqliteBackend};
use crate::llm::ToolOutcome;
use crate::llm::{ToolCall, ToolValue};
use crate::todo::{COMPLETE_TOOL, LIST_TOOL, SAVE_TOOL, timing};

struct TestClock(AtomicI64);

impl Clock for TestClock {
    fn now_us(&self) -> i64 {
        self.0.fetch_add(1_000, Ordering::Relaxed)
    }
}

fn local_ms(text: &str) -> i64 {
    timing::local_millis(
        NaiveDateTime::parse_from_str(text, "%Y-%m-%d %H:%M").unwrap(),
        &chrono::Local,
    )
    .unwrap()
}

const NOW: &str = "2026-11-12 14:30";

const SURE: Option<f32> = Some(1.0);
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

struct ToolTurn {
    reply: Message,
    state: ToolTurnState,
}

fn finish(
    db: &ChatDb<SqliteBackend>,
    snapshot: &ConversationSnapshot,
    calls: &[ToolCall],
    confidence: Option<f32>,
) -> crate::db::Result<ToolTurn> {
    let outcome = ToolOutcome {
        calls: calls.to_vec(),
        call_probability: confidence,
    };
    let finished = db.finish_reply(snapshot, "", vec![], Some(&outcome))?;
    Ok(ToolTurn {
        reply: finished.message,
        state: finished.tool_turn.unwrap(),
    })
}

struct Chat<'a> {
    db: &'a ChatDb<SqliteBackend>,
    session: Uuid,
    path: Vec<Uuid>,
}

impl<'a> Chat<'a> {
    fn new(db: &'a ChatDb<SqliteBackend>) -> Self {
        let session = db.create_session("To Do").unwrap();
        Self {
            db,
            session: session.uuid,
            path: Vec::new(),
        }
    }

    fn send(&mut self, user: &str, calls: &[ToolCall]) -> ToolTurn {
        self.send_as(user, calls, SURE)
    }

    fn send_as(&mut self, user: &str, calls: &[ToolCall], confidence: Option<f32>) -> ToolTurn {
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
        let turn = self.answer(calls, confidence).unwrap();
        self.path.push(turn.reply.uuid);
        turn
    }

    fn answer(&self, calls: &[ToolCall], confidence: Option<f32>) -> crate::db::Result<ToolTurn> {
        let snapshot = self.snapshot();
        finish(self.db, &snapshot, calls, confidence)
    }

    fn snapshot(&self) -> ConversationSnapshot {
        self.db
            .conversation_snapshot(self.session, &self.path)
            .unwrap()
    }

    fn back(&mut self) {
        self.path.pop();
    }
}

fn state(db: &ChatDb<SqliteBackend>, reply: &Message) -> Option<ToolTurnState> {
    db.tool_turn_states(reply.session_uuid)
        .unwrap()
        .remove(&reply.uuid)
}

#[test]
fn chat_calls_save_list_and_complete_tasks_with_one_reply_each() {
    let db = db();
    let mut chat = Chat::new(&db);
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
    assert!(saved.state.undo == Undo::Available);
    assert_eq!(saved.reply.parent_message_uuid, Some(chat.path[0]));
    let todos = db.list_todos().unwrap();
    assert_eq!(
        todos
            .iter()
            .map(|t| (t.title.as_str(), t.due_at_ms))
            .collect::<Vec<_>>(),
        [
            ("Call Lee", Some(local_ms("2026-11-12 16:00"))),
            ("Buy apples", Some(local_ms("2026-11-13 09:00"))),
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
    assert!(!db.get_todo(todos[1].id).unwrap().unwrap().is_open());

    let third = chat.send(
        "Done with 3",
        &[call(COMPLETE_TOOL, &[("number", ToolValue::Integer(3))])],
    );
    assert_eq!(third.reply.text, "Marked “Water plants” as done.");
    let missing = chat.send(
        "And number 7",
        &[call(COMPLETE_TOOL, &[("number", ToolValue::Integer(7))])],
    );
    assert!(
        missing.reply.text.starts_with("There's no task 7"),
        "{}",
        missing.reply.text
    );
    assert!(missing.state.undo == Undo::None);

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
    let off_list = chat.send(
        "I paid the rent",
        &[call(
            COMPLETE_TOOL,
            &[("task", text("Call Lee about the trip"))],
        )],
    );
    assert_eq!(
        off_list.reply.text,
        "I couldn't find that in your open tasks."
    );
    let again = chat.send(
        "Can you try again?",
        &[call(
            COMPLETE_TOOL,
            &[("task", text("Call Lee about the trip"))],
        )],
    );
    assert_eq!(again.reply.text, off_list.reply.text);
    db.create_todo("Pay the rent", None).unwrap();
    let retried = chat.send(
        "Try again please",
        &[call(COMPLETE_TOOL, &[("task", text("Pay the rent"))])],
    );
    assert_eq!(retried.reply.text, "Marked “Pay the rent” as done.");

    db.create_todo("Zed alpha", None).unwrap();
    db.create_todo("Zed beta", None).unwrap();
    chat.send("Show my list", &[call(LIST_TOOL, &[])]);
    let narrowed = chat.send(
        "Show tasks about beta and mark the first one done",
        &[
            call(LIST_TOOL, &[("query", text("beta"))]),
            call(COMPLETE_TOOL, &[("number", ToolValue::Integer(1))]),
        ],
    );
    assert!(
        narrowed.reply.text.ends_with("Marked “Zed beta” as done."),
        "{}",
        narrowed.reply.text
    );
    let thanks = db
        .insert_message(
            chat.session,
            "self",
            "Thanks",
            chat.path.last().copied(),
            vec![],
        )
        .unwrap();
    chat.path.push(thanks.uuid);
    let welcome = db
        .finish_reply(&chat.snapshot(), "You're welcome.", vec![], None)
        .unwrap();
    chat.path.push(welcome.message.uuid);
    let later = chat.send(
        "Mark the first one done",
        &[call(COMPLETE_TOOL, &[("number", ToolValue::Integer(1))])],
    );
    assert_eq!(later.reply.text, "“Zed beta” is already done.");

    db.create_todo("Zed gamma", None).unwrap();
    let last = chat.send(
        "Show tasks about Zed and mark the last one done",
        &[
            call(LIST_TOOL, &[("query", text("Zed"))]),
            call(COMPLETE_TOOL, &[("number", ToolValue::Integer(1))]),
        ],
    );
    assert!(
        last.reply.text.ends_with("Marked “Zed gamma” as done."),
        "{}",
        last.reply.text
    );
    let again = chat.send("List again", &[call(LIST_TOOL, &[("query", text("Zed"))])]);
    assert!(
        again.reply.text.contains("Zed alpha"),
        "{}",
        again.reply.text
    );
    let it = chat.send(
        "Mark it done",
        &[call(COMPLETE_TOOL, &[("task", text("Zed alpha"))])],
    );
    assert_eq!(it.reply.text, "Mark “Zed alpha” as done?");

    let none = chat.send(
        "Show overdue",
        &[call(LIST_TOOL, &[("filter", text("overdue"))])],
    );
    assert_eq!(none.reply.text, "No tasks match.");
    let gone = chat.send(
        "Mark the first one done",
        &[call(COMPLETE_TOOL, &[("number", ToolValue::Integer(1))])],
    );
    assert!(gone.reply.text.starts_with("There's no task 1"));
    assert!(gone.state.undo == Undo::None);

    let list = [call(LIST_TOOL, &[])];
    assert!(chat.answer(&list, SURE).is_err());
    chat.back();
    let stale = chat.snapshot();
    db.update_message_text(*chat.path.last().unwrap(), "the first one")
        .unwrap();
    assert!(matches!(
        finish(&db, &stale, &list, SURE),
        Err(Error::ConversationChanged)
    ));
}

#[test]
fn prepared_completions_keep_their_original_targets() {
    for change in [
        "none",
        "unrelated",
        "edited",
        "deleted",
        "completed",
        "duplicate",
        "fallback",
        "same-batch",
    ] {
        let db = db();
        let chat = Chat::new(&db);
        let old = db.create_todo("Buy milk", None).unwrap();
        if change == "duplicate" || change == "fallback" {
            db.create_todo(
                if change == "duplicate" {
                    "Buy milk"
                } else {
                    "Buy oat milk"
                },
                None,
            )
            .unwrap();
        }
        let user = db
            .insert_message(
                chat.session,
                "self",
                if change == "same-batch" {
                    "Add Buy milk, list tasks, and mark Buy milk done"
                } else {
                    "Buy bread, list tasks, and I bought the milk"
                },
                None,
                vec![],
            )
            .unwrap();
        let snapshot = db
            .conversation_snapshot(chat.session, &[user.uuid])
            .unwrap();
        let tools = db.turn_tools(&snapshot, &user.text).unwrap().tools;
        match change {
            "unrelated" => {
                db.create_todo("Call Lee", None).unwrap();
            }
            "edited" => {
                db.update_todo(
                    old.id,
                    old.version,
                    &old.title,
                    Some(local_ms("2026-11-13 09:00")),
                )
                .unwrap();
            }
            "deleted" | "duplicate" | "fallback" | "same-batch" => {
                db.delete_todo(old.id, old.version).unwrap();
            }
            "completed" => {
                db.set_todo_completed(old.id, old.version, true).unwrap();
            }
            _ => {}
        }
        if change == "deleted" || change == "completed" {
            db.create_todo("Buy milk", Some(local_ms("2026-11-13 09:00")))
                .unwrap();
        }
        assert_eq!(tools, db.turn_tools(&snapshot, &user.text).unwrap().tools);
        let before = db.list_todos().unwrap();
        let result = finish(
            &db,
            &snapshot,
            &[
                call(
                    SAVE_TOOL,
                    &[(
                        "title",
                        text(if change == "same-batch" {
                            "Buy milk"
                        } else {
                            "Buy bread"
                        }),
                    )],
                ),
                call(LIST_TOOL, &[]),
                call(COMPLETE_TOOL, &[("task", text("milk"))]),
            ],
            SURE,
        );
        if change == "none" || change == "unrelated" {
            let turn = result.unwrap();
            assert!(!db.get_todo(old.id).unwrap().unwrap().is_open());
            assert_eq!(db.list_todos().unwrap().len(), before.len() + 1);
            if change == "unrelated" {
                assert!(turn.reply.text.contains("Call Lee"));
            }
        } else {
            assert!(
                matches!(result, Err(Error::ConversationChanged)),
                "{change}"
            );
            assert_eq!(db.list_todos().unwrap(), before, "{change}");
            assert!(db.tool_turn_states(chat.session).unwrap().is_empty());
            db.finish_reply(&snapshot, "You're welcome.", vec![], None)
                .unwrap();
        }
    }
    let db = db();
    let mut chat = Chat::new(&db);
    let turn = chat.send(
        "Add Buy milk and mark Buy milk done",
        &[
            call(SAVE_TOOL, &[("title", text("Buy milk"))]),
            call(COMPLETE_TOOL, &[("task", text("Buy milk"))]),
        ],
    );
    assert_eq!(turn.state.undo, Undo::Available);
    let todos = db.list_todos().unwrap();
    assert_eq!(todos.len(), 1);
    assert!(!todos[0].is_open());
}

#[test]
fn several_calls_in_one_message_each_use_the_list_in_effect() {
    for confidence in [SURE, UNSURE] {
        for (title, subject, target, number) in [
            (
                "Review first item in checklist",
                "\"Review first item in checklist\"",
                "the third one",
                Some(3),
            ),
            (
                "Review first item in checklist",
                "Review first item in checklist",
                "the third one",
                Some(3),
            ),
            (
                "Review first item in checklist",
                "\"Review first item in checklist\"",
                "it",
                Some(3),
            ),
            (
                "Review first item in checklist",
                "\"Review the first item in checklist\"",
                "it",
                Some(3),
            ),
            (
                "Review checklist",
                "\"Review the first item in checklist\"",
                "it",
                Some(3),
            ),
            (
                "Review checklist",
                "\"Review the first item in checklist\"",
                "it",
                None,
            ),
            (
                "Review checklist",
                "\"Review checklist\"",
                "the third one",
                Some(3),
            ),
        ] {
            let db = db();
            let mut chat = Chat::new(&db);
            let milk = db.create_todo("Buy milk", None).unwrap();
            let ana = db.create_todo("Call Ana", None).unwrap();
            let turn = chat.send_as(
                &format!("Add {subject}, show all my tasks, then mark {target} done"),
                &[
                    call(SAVE_TOOL, &[("title", text(title))]),
                    call(LIST_TOOL, &[]),
                    call(
                        COMPLETE_TOOL,
                        &number
                            .map(|number| ("number", ToolValue::Integer(number)))
                            .into_iter()
                            .collect::<Vec<_>>(),
                    ),
                ],
                confidence,
            );
            if confidence == UNSURE || target == "it" && number.is_some() {
                assert_eq!(turn.state.confirm, Confirm::Offered);
                db.confirm_tool_turn(turn.reply.uuid).unwrap();
            }
            let tasks = db.list_todos().unwrap();
            assert_eq!(
                tasks
                    .iter()
                    .find(|todo| todo.title == title)
                    .unwrap()
                    .completed_at_ms
                    .is_some(),
                number.is_some(),
            );
            if number.is_none() {
                assert!(
                    turn.reply
                        .text
                        .ends_with("Which task should I mark as done?")
                );
            }
            assert!(db.get_todo(milk.id).unwrap().unwrap().is_open());
            assert!(db.get_todo(ana.id).unwrap().unwrap().is_open());
            db.undo_tool_turn(turn.reply.uuid).unwrap();
            assert_eq!(db.list_todos().unwrap(), [milk, ana]);
        }
    }
    let db = db();
    let mut chat = Chat::new(&db);
    for title in ["Buy milk", "Write first draft", "Call Ana"] {
        db.create_todo(title, None).unwrap();
    }
    let open = |db: &ChatDb<SqliteBackend>| {
        let mut open: Vec<_> = db
            .list_todos()
            .unwrap()
            .into_iter()
            .filter(Todo::is_open)
            .map(|todo| todo.title)
            .collect();
        open.sort();
        open
    };
    let item = |number: i64| call(COMPLETE_TOOL, &[("number", ToolValue::Integer(number))]);
    chat.send("Show my list", &[call(LIST_TOOL, &[])]);
    let mixed = chat.send_as(
        "Mark Buy milk done, show remaining open tasks, and mark the last one done",
        &[
            call(COMPLETE_TOOL, &[("task", text("Buy milk"))]),
            call(LIST_TOOL, &[]),
            item(2),
        ],
        UNSURE,
    );
    assert!(
        mixed.reply.text.ends_with("Mark “Call Ana” as done?"),
        "{}",
        mixed.reply.text
    );
    chat.send("Show my list", &[call(LIST_TOOL, &[])]);
    let ends = [item(1), call(LIST_TOOL, &[]), item(2)];
    let request =
        "Mark the first task done, show remaining open tasks, then mark the last one done";
    let offered = chat.send_as(request, &ends, UNSURE);
    assert!(
        offered.reply.text.starts_with("Mark “Buy milk” as done?")
            && offered.reply.text.ends_with("Mark “Call Ana” as done?"),
        "{}",
        offered.reply.text
    );
    chat.send("Show my list", &[call(LIST_TOOL, &[])]);
    chat.send(
        "Mark Write first draft done, and mark 3 done",
        &[
            call(COMPLETE_TOOL, &[("task", text("Write first draft"))]),
            item(3),
        ],
    );
    assert_eq!(open(&db), ["Buy milk"]);
    for title in ["Write first draft", "Call Ana"] {
        db.create_todo(title, None).unwrap();
    }
    chat.send("Show my list", &[call(LIST_TOOL, &[])]);
    chat.send(request, &ends);
    assert_eq!(open(&db), ["Write first draft"]);

    for title in ["Call client 3", "Buy milk", "Call Ana"] {
        db.create_todo(title, None).unwrap();
    }
    chat.send("Show my list", &[call(LIST_TOOL, &[])]);
    let numbered = chat.send_as(
        "Mark Call client 3 done, show remaining open tasks, then mark the last one done",
        &[
            call(COMPLETE_TOOL, &[("task", text("Call client 3"))]),
            call(LIST_TOOL, &[]),
            item(3),
        ],
        UNSURE,
    );
    assert!(
        numbered.reply.text.ends_with("Mark “Call Ana” as done?"),
        "{}",
        numbered.reply.text
    );
    db.confirm_tool_turn(numbered.reply.uuid).unwrap();
    assert_eq!(open(&db), ["Buy milk", "Write first draft"]);
    chat.send(
        "Buy milk and the draft are done",
        &[
            call(COMPLETE_TOOL, &[("task", text("Buy milk"))]),
            call(COMPLETE_TOOL, &[("task", text("Write first draft"))]),
        ],
    );

    let chained = chat.send_as(
        "Add Feed cat, show my list, then mark the last one done",
        &[
            call(SAVE_TOOL, &[("title", text("Feed cat"))]),
            call(LIST_TOOL, &[]),
            item(1),
        ],
        UNSURE,
    );
    assert!(state(&db, &chained.reply).unwrap().confirm == Confirm::Offered);
    db.confirm_tool_turn(chained.reply.uuid).unwrap();
    assert!(open(&db).is_empty());

    db.create_todo("Zed one", None).unwrap();
    chat.send(
        "Show draft and mark number 1 done, then show Zed and mark number 1 done",
        &[
            call(LIST_TOOL, &[("query", text("draft"))]),
            item(1),
            call(LIST_TOOL, &[("query", text("Zed"))]),
            item(1),
        ],
    );
    assert!(open(&db).is_empty());

    for title in ["Call Lee", "Call Lee about the trip", "Buy apples"] {
        db.create_todo(title, None).unwrap();
    }
    chat.send("Show my list", &[call(LIST_TOOL, &[])]);
    let unclear = chat.send(
        "I called Lee, and mark the third one done",
        &[call(COMPLETE_TOOL, &[("task", text("Lee"))]), item(3)],
    );
    assert!(
        unclear.reply.text.starts_with("Which one")
            && unclear.reply.text.ends_with("Marked “Buy apples” as done."),
        "{}",
        unclear.reply.text
    );
    let polite = chat.send(
        "Could you mark it done?",
        &[call(COMPLETE_TOOL, &[("task", text("Call Lee"))])],
    );
    assert_eq!(polite.reply.text, "Mark “Call Lee” as done?");
    let dated = chat.send(
        "I finished it yesterday",
        &[call(COMPLETE_TOOL, &[("task", text("Call Lee"))])],
    );
    assert_eq!(dated.reply.text, polite.reply.text);
}

#[test]
fn messages_can_be_answered_again_until_a_reply_changes_tasks() {
    let db = db();
    let mut chat = Chat::new(&db);
    db.create_todo("Call Vidhi about Aadhar", None).unwrap();
    let missed = chat.send(
        "I talked to Vidhi",
        &[call(
            COMPLETE_TOOL,
            &[("task", text("Vidhi for her Aadhar"))],
        )],
    );
    assert!(missed.state.undo == Undo::None);
    chat.back();
    let offered = chat
        .answer(
            &[call(
                COMPLETE_TOOL,
                &[("task", text("Call Vidhi about Aadhar"))],
            )],
            UNSURE,
        )
        .unwrap();
    assert!(state(&db, &offered.reply).unwrap().confirm == Confirm::Offered);
    let done = chat
        .answer(
            &[call(
                COMPLETE_TOOL,
                &[("task", text("Call Vidhi about Aadhar"))],
            )],
            SURE,
        )
        .unwrap();
    assert_eq!(done.reply.text, "Marked “Call Vidhi about Aadhar” as done.");
    assert!(state(&db, &offered.reply).unwrap().confirm != Confirm::Offered);
    assert!(db.confirm_tool_turn(offered.reply.uuid).is_err());
    let list = [call(LIST_TOOL, &[])];
    assert!(matches!(chat.answer(&list, SURE), Err(Error::Refused(_))));
    db.undo_tool_turn(done.reply.uuid).unwrap();
    assert!(chat.answer(&list, SURE).is_ok());
}

#[test]
fn unsure_calls_offer_changes_and_make_them_once_confirmed() {
    for (user, task, number, offered, completed) in [
        ("I finished the first draft", None, Some(1), true, None),
        ("Finished chapter 3", None, Some(3), true, None),
        ("I finished the first draft", None, None, false, None),
        (
            "I finished the first draft",
            Some("Write first draft"),
            None,
            false,
            Some("Write first draft"),
        ),
        (
            "Finished chapter 3",
            Some("Read chapter 3"),
            None,
            false,
            Some("Read chapter 3"),
        ),
        (
            "I finished the first one",
            None,
            Some(1),
            false,
            Some("Buy milk"),
        ),
        (
            "Finished item 3",
            None,
            Some(3),
            false,
            Some("Water plants"),
        ),
    ] {
        let db = db();
        let mut chat = Chat::new(&db);
        for title in [
            "Buy milk",
            "Call Ana",
            "Water plants",
            "Write first draft",
            "Read chapter 3",
        ] {
            db.create_todo(title, None).unwrap();
        }
        chat.send("Show my list", &[call(LIST_TOOL, &[])]);
        let mut args = Vec::new();
        args.extend(task.map(|task| ("task", text(task))));
        args.extend(number.map(|number| ("number", ToolValue::Integer(number))));
        let turn = chat.send(user, &[call(COMPLETE_TOOL, &args)]);
        assert_eq!(turn.state.confirm == Confirm::Offered, offered, "{user}");
        let done: Vec<_> = db
            .list_todos()
            .unwrap()
            .into_iter()
            .filter(|todo| !todo.is_open())
            .map(|todo| todo.title)
            .collect();
        assert_eq!(done, completed.into_iter().collect::<Vec<_>>(), "{user}");
    }

    let db = db();
    let mut chat = Chat::new(&db);
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
    assert_eq!(
        turn.reply.text,
        "Add “Buy stamps”, due Fri 13 Nov 2026, 09:00 to your To Dos? No time was given, so I used 9:00.\nMark “Pay rent” as done?"
    );
    assert!(turn.state.confirm == Confirm::Offered && turn.state.undo == Undo::None);
    let list = |db: &ChatDb<SqliteBackend>| {
        db.list_todos()
            .unwrap()
            .into_iter()
            .map(|todo| (todo.title.clone(), todo.is_open()))
            .collect::<Vec<_>>()
    };
    assert_eq!(list(&db), [("Pay rent".to_owned(), true)]);
    let offer = state(&db, &turn.reply).unwrap();
    assert!(offer.confirm == Confirm::Offered && offer.undo == Undo::None);

    let history = db.tool_history(std::slice::from_ref(&turn.reply)).unwrap();
    assert_eq!(history[&turn.reply.uuid].proposal, Some(false));

    let replaced = chat.send_as(
        "Maybe buy tea",
        &[call(SAVE_TOOL, &[("title", text("Buy tea"))])],
        UNSURE,
    );
    chat.back();
    db.finish_reply(&chat.snapshot(), "Tea is nice.", vec![], None)
        .unwrap();
    assert!(db.confirm_tool_turn(replaced.reply.uuid).is_err());
    chat.back();

    assert!(db.confirm_tool_turn(turn.reply.uuid).unwrap().undo == Undo::Available);
    assert_eq!(
        list(&db),
        [
            ("Buy stamps".to_owned(), true),
            ("Pay rent".to_owned(), false)
        ]
    );
    let added = db.list_todos().unwrap().remove(0);
    assert_eq!(added.due_at_ms, Some(local_ms("2026-11-13 09:00")));
    let made_state = state(&db, &turn.reply).unwrap();
    assert!(made_state.confirm != Confirm::Offered && made_state.undo == Undo::Available);
    assert_eq!(
        db.tool_history(std::slice::from_ref(&turn.reply)).unwrap()[&turn.reply.uuid].proposal,
        Some(true)
    );
    assert_eq!(db.confirm_tool_turn(turn.reply.uuid).unwrap(), made_state);

    db.undo_tool_turn(turn.reply.uuid).unwrap();
    assert_eq!(list(&db), [("Pay rent".to_owned(), true)]);
}

#[test]
fn offers_conflict_with_edits_made_since() {
    let db = db();
    let mut chat = Chat::new(&db);
    let rent = db.create_todo("Pay rent", None).unwrap();
    let turn = chat.send_as(
        "I paid the rent",
        &[call(COMPLETE_TOOL, &[("task", text("rent"))])],
        UNSURE,
    );
    assert!(state(&db, &turn.reply).unwrap().confirm == Confirm::Offered);
    let renamed = db
        .update_todo(rent.id, rent.version, "Pay the rent", None)
        .unwrap();
    assert!(state(&db, &turn.reply).unwrap().confirm != Confirm::Offered);
    db.update_todo(renamed.id, renamed.version, "Pay rent", None)
        .unwrap();
    assert!(state(&db, &turn.reply).unwrap().confirm == Confirm::Offered);
    let renamed = db.list_todos().unwrap().remove(0);
    db.update_todo(renamed.id, renamed.version, "Pay the rent", None)
        .unwrap();
    assert!(db.confirm_tool_turn(turn.reply.uuid).is_err());
    assert!(db.list_todos().unwrap()[0].is_open());
    assert!(state(&db, &turn.reply).unwrap().confirm != Confirm::Offered);
    assert!(db.confirm_tool_turn(turn.reply.uuid).is_err());
}

#[test]
fn calls_without_a_confidence_are_offered_and_lists_always_run() {
    let db = db();
    let mut chat = Chat::new(&db);
    let saved = chat.send(
        "Buy stamps",
        &[call(SAVE_TOOL, &[("title", text("Buy stamps"))])],
    );
    assert!(db.confirm_tool_turn(saved.reply.uuid).is_err());
    let offered = chat.send_as(
        "Buy milk",
        &[call(SAVE_TOOL, &[("title", text("Buy milk"))])],
        None,
    );
    assert!(offered.state.confirm == Confirm::Offered);
    assert_eq!(db.list_todos().unwrap().len(), 1);
    let listed = chat.send_as(
        "What's on my list?",
        &[call(LIST_TOOL, &[("filter", text("open"))])],
        UNSURE,
    );
    assert_eq!(listed.reply.text, "1. Buy stamps — no due date");
    assert!(listed.state.confirm != Confirm::Offered);
}

#[test]
fn undo_reverts_a_turn_once_and_refuses_after_later_edits() {
    let db = db();
    let mut chat = Chat::new(&db);
    let existing = db.create_todo("Pay rent", None).unwrap();
    let turn = chat.send(
        "Add stamps and I paid rent",
        &[
            call(SAVE_TOOL, &[("title", text("Buy stamps"))]),
            call(COMPLETE_TOOL, &[("task", text("rent"))]),
        ],
    );
    assert_eq!(
        state(&db, &turn.reply),
        Some(ToolTurnState {
            undo: Undo::Available,
            confirm: Confirm::None,
            can_retry: false,
        })
    );
    let next = db
        .insert_message(chat.session, "self", "ok", Some(turn.reply.uuid), vec![])
        .unwrap();
    chat.path.push(next.uuid);
    let mut summarised = chat.snapshot();
    let memory = crate::conversation::ConversationState::new(
        chat.session,
        &summarised.messages()[..2],
        "Saved stamps".into(),
    )
    .unwrap();
    assert!(
        db.replace_conversation_state(&mut summarised, Some(memory))
            .unwrap()
    );
    db.undo_tool_turn(turn.reply.uuid).unwrap();
    assert!(!db.conversation_snapshot_matches(&summarised).unwrap());
    assert!(chat.snapshot().state().is_none());
    chat.back();
    let todos = db.list_todos().unwrap();
    assert_eq!(todos.len(), 1);
    assert!(todos[0].is_open());
    assert_eq!(todos[0].version, existing.version + 2);
    assert_eq!(
        db.undo_tool_turn(turn.reply.uuid).unwrap().undo,
        Undo::Undone
    );

    let again = chat.send("Add milk", &[call(SAVE_TOOL, &[("title", text("milk"))])]);
    let milk = db
        .list_todos()
        .unwrap()
        .into_iter()
        .find(|todo| todo.title == "Milk")
        .unwrap();
    db.update_todo(milk.id, milk.version, "Oat milk", None)
        .unwrap();
    assert!(db.undo_tool_turn(again.reply.uuid).is_err());
    assert_eq!(db.list_todos().unwrap().len(), 2);

    let listed = chat.send("List", &[call(LIST_TOOL, &[("filter", text("all"))])]);
    assert!(db.undo_tool_turn(listed.reply.uuid).is_err());
}

#[test]
fn undo_puts_back_the_tasks_left_alone_and_keeps_the_edited_ones() {
    let db = db();
    let mut chat = Chat::new(&db);
    let save = [
        call(SAVE_TOOL, &[("title", text("Buy stamps"))]),
        call(SAVE_TOOL, &[("title", text("Buy milk"))]),
    ];
    let turn = chat.send("Add stamps and milk", &save);
    let milk = db
        .list_todos()
        .unwrap()
        .into_iter()
        .find(|todo| todo.title == "Buy milk")
        .unwrap();
    db.update_todo(milk.id, milk.version, "Buy oat milk", None)
        .unwrap();
    assert!(state(&db, &turn.reply).unwrap().undo == Undo::Available);
    chat.back();
    assert!(matches!(chat.answer(&save, SURE), Err(Error::Refused(_))));

    assert_eq!(
        db.undo_tool_turn(turn.reply.uuid).unwrap().undo,
        Undo::PartlyUndone
    );
    assert_eq!(state(&db, &turn.reply).unwrap().undo, Undo::PartlyUndone);
    let titles: Vec<_> = db
        .list_todos()
        .unwrap()
        .into_iter()
        .map(|todo| todo.title)
        .collect();
    assert_eq!(titles, ["Buy oat milk"]);
    assert!(chat.answer(&save, SURE).is_ok());
}

#[test]
fn history_follows_stored_turns() {
    let db = db();
    let mut chat = Chat::new(&db);
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
    let messages = db.get_messages(chat.session).unwrap();
    let history = db.tool_history(&messages).unwrap();
    assert_eq!(history.len(), 1);
    assert_eq!(history[&turn.reply.uuid].calls, calls);
    assert!(!history[&turn.reply.uuid].undone);

    db.delete_session(chat.session).unwrap();
    assert!(db.tool_history(&messages).unwrap().is_empty());
    assert_eq!(db.list_todos().unwrap().len(), 2);
}

#[test]
fn manual_edits_check_versions_and_titles() {
    let db = db();
    let changes = Arc::new(AtomicI64::new(0));
    let seen = changes.clone();
    db.observe_tools(Arc::new(move || {
        seen.fetch_add(1, Ordering::Relaxed);
    }));
    let todo = db.create_todo("  read   book ", None).unwrap();
    assert_eq!(changes.load(Ordering::Relaxed), 1);
    assert_eq!(todo.title, "Read book");
    assert!(db.create_todo(" ", None).is_err());
    assert_eq!(db.create_todo(".env", None).unwrap().title, ".env");
    assert!(db.create_todo(&"x".repeat(201), None).is_err());
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
            .execute_batch("DROP TABLE tool_turns; DROP TABLE todos; PRAGMA user_version = 6;")
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
        8
    );
    db.create_todo("Works", None).unwrap();
}

#[test]
fn an_offer_to_add_goes_stale_once_the_task_is_added_another_way() {
    let db = db();
    let mut chat = Chat::new(&db);
    let save = [call(SAVE_TOOL, &[("title", text("Buy tea"))])];
    let offer = chat.send_as("Maybe buy tea", &save, UNSURE);
    assert_eq!(offer.state.confirm, Confirm::Offered);
    chat.send("Yes, buy tea", &save);
    assert_eq!(state(&db, &offer.reply).unwrap().confirm, Confirm::Stale);
    assert!(matches!(
        db.confirm_tool_turn(offer.reply.uuid),
        Err(Error::Refused(Refusal::OfferStale))
    ));
    assert_eq!(db.list_todos().unwrap().len(), 1);
}

#[test]
fn a_refused_finish_keeps_the_calls_and_a_saved_one_clears_them() {
    use crate::conversation::{Reply, finish_turn};
    let db = db();
    let mut chat = Chat::new(&db);
    let save = [call(SAVE_TOOL, &[("title", text("Buy tea"))])];
    let first = chat.send("Buy tea", &save);
    chat.back();
    let exchange = crate::llm::ToolExchange::new(crate::todo::chat_tools("Buy tea", &[]));
    let outcome = ToolOutcome {
        calls: save.to_vec(),
        call_probability: SURE,
    };
    exchange.record(Some(outcome.clone()));
    let reply = || Reply {
        text: "",
        sources: &[],
        passages: Vec::new(),
        attachments: Vec::new(),
        tools: Some(&exchange),
    };
    assert!(matches!(
        finish_turn(&db, &chat.snapshot(), reply()),
        Err(Error::Refused(Refusal::EarlierReplyStands))
    ));
    assert_eq!(exchange.outcome(), Some(outcome));
    db.undo_tool_turn(first.reply.uuid).unwrap();
    let finished = finish_turn(&db, &chat.snapshot(), reply()).unwrap();
    assert!(finished.reply.tool_turn.is_some());
    assert!(finished.warnings.is_empty());
    assert_eq!(exchange.outcome(), None);
}
