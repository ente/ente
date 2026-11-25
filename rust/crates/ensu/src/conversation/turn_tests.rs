use super::{tests::Fake, *};
use crate::db::chat::ConversationSnapshot;
use crate::db::{self, ChatDb, SqliteBackend};
use crate::llm::{self, GenerationEvent, GenerationSummary, ToolValue};
use crate::todo::{COMPLETE_TOOL, LIST_TOOL, SAVE_TOOL};
use crate::tools::test_support::*;
use crate::tools::turn::{self as tool_turn, Confirm, Undo};

const MIXED: &str = "Show my tasks and add buy milk.";

fn prepare(
    db: &ChatDb<SqliteBackend>,
    snapshot: &ConversationSnapshot,
    user: &str,
    no_tools: bool,
) -> Turn {
    let mut effects = Fake::default();
    effects.no_tools = no_tools;
    Turn::begin(
        db,
        snapshot,
        TurnRequest {
            session: snapshot.session_uuid(),
            system: "Be brief.".into(),
            current: user.into(),
            expected_user_text: user.into(),
            history_query: None,
            context: 4096,
            output: Some(128),
            candidates: GroundingCandidates::new(vec![], vec![], 0).unwrap(),
        },
        &zone(),
    )
    .unwrap()
    .prepare(None, &mut effects)
    .unwrap()
}

fn execute(
    turn: &Turn,
    runner: &mut ScriptedRunner,
    output: i32,
) -> (Result<GenerationSummary, llm::Error>, Vec<GenerationEvent>) {
    let mut events = Vec::new();
    let result = turn.generate(
        runner,
        ChatRequest {
            messages: turn.messages(),
            max_tokens: Some(output),
            tools: Some(crate::todo::chat_tools("other", &[])),
            ..Default::default()
        },
        &mut |event| events.push(event),
        &zone(),
    );
    runner.assert_done();
    (result, events)
}

fn list() -> Pass {
    Pass {
        calls: vec![call(LIST_TOOL, &[])],
        probability: Some(0.97),
        generated: 10,
        ..Default::default()
    }
}

fn save(probability: Option<f32>) -> Pass {
    Pass {
        calls: vec![call(SAVE_TOOL, &[("title", text("Buy milk"))])],
        probability,
        generated: 7,
        ..Default::default()
    }
}

#[test]
fn a_plain_reply_is_saved_as_text() {
    let db = db();
    let mut chat = Chat::new(&db);
    chat.user("Hi");
    let snapshot = chat.snapshot();
    let turn = prepare(&db, &snapshot, "Hi", false);
    execute(
        &turn,
        &mut ScriptedRunner::new([Pass {
            text: "Hi",
            ..Default::default()
        }]),
        128,
    )
    .0
    .unwrap();
    let finished = turn
        .finish(&db, &snapshot, "Client reply", vec![], &zone())
        .unwrap();
    assert_eq!(finished.reply.message.text, "Client reply");
    assert!(finished.reply.tool_turn.is_none());
    assert!(db.list_todos().unwrap().is_empty());
}

#[test]
fn save_is_applied_or_offered_at_the_recorded_probability() {
    for probability in [SURE, UNSURE] {
        let db = db();
        let mut chat = Chat::new(&db);
        chat.user("Add buy milk.");
        let snapshot = chat.snapshot();
        let turn = prepare(&db, &snapshot, "Add buy milk.", false);
        execute(&turn, &mut ScriptedRunner::new([save(probability)]), 128)
            .0
            .unwrap();
        let finished = turn
            .finish(&db, &snapshot, "Client reply", vec![], &zone())
            .unwrap();
        let state = finished.reply.tool_turn.unwrap();
        if probability == SURE {
            assert_eq!(finished.reply.message.text, "Saved “Buy milk”.");
            assert_eq!(state.undo, Undo::Available);
        } else {
            assert_eq!(state.confirm, Confirm::Offered);
            assert!(db.list_todos().unwrap().is_empty());
            tool_turn::confirm(&db, finished.reply.message.uuid).unwrap();
        }
        assert_eq!(db.list_todos().unwrap().len(), 1);
    }
}

#[test]
fn a_list_only_turn_runs_one_pass() {
    let db = db();
    db.create_todo("Call Ana", None).unwrap();
    let mut chat = Chat::new(&db);
    let user = "What's on my list?";
    chat.user(user);
    let snapshot = chat.snapshot();
    let turn = prepare(&db, &snapshot, user, false);
    execute(&turn, &mut ScriptedRunner::new([list()]), 128)
        .0
        .unwrap();
    assert!(
        turn.finish(&db, &snapshot, "Ignored", vec![], &zone())
            .unwrap()
            .reply
            .message
            .text
            .contains("1. Call Ana")
    );
}

#[test]
fn list_then_save_merges_both_passes() {
    for probability in [Some(0.93), UNSURE] {
        let db = db();
        db.create_todo("Call Ana", None).unwrap();
        let mut chat = Chat::new(&db);
        chat.user(MIXED);
        let snapshot = chat.snapshot();
        let turn = prepare(&db, &snapshot, MIXED, false);
        let mut runner = ScriptedRunner::new([list(), save(probability)]);
        let (result, events) = execute(&turn, &mut runner, 128);
        let result = result.unwrap();
        assert_eq!(result.prompt_tokens, Some(32));
        assert_eq!(result.generated_tokens, Some(17));
        let outcome = result.tools.unwrap();
        assert_eq!(outcome.call_probability, probability);
        assert_eq!(
            outcome
                .calls
                .iter()
                .map(|call| call.name.as_str())
                .collect::<Vec<_>>(),
            [LIST_TOOL, SAVE_TOOL]
        );
        assert!(matches!(events.as_slice(), [GenerationEvent::Done { .. }]));
        let [first, second] = runner.seen.as_slice() else {
            panic!("expected two passes")
        };
        assert_eq!(first.messages, second.messages[..first.messages.len()]);
        let a = first.tools.as_ref().unwrap();
        let b = second.tools.as_ref().unwrap();
        assert_eq!(a.tools, b.tools);
        assert_eq!(a.examples, b.examples);
        assert_eq!(b.allowed.as_deref(), Some(&[SAVE_TOOL.to_owned()][..]));
        assert_eq!(b.max_calls, 3);
        assert_eq!(second.max_tokens, Some(118));
        assert_eq!(
            second.messages[first.messages.len()].tool_calls,
            list().calls
        );
        let tool_message = second.messages.last().unwrap();
        assert_eq!(tool_message.role, "tool");
        assert!(tool_message.content.contains("1. Call Ana"));
        assert!(tool_message.content.contains("The listing is complete."));
        let finished = turn
            .finish(&db, &snapshot, "", vec![], &zone())
            .unwrap()
            .reply;
        assert_eq!(
            finished.tool_turn.unwrap().confirm == Confirm::Offered,
            probability == UNSURE
        );
    }
}

#[test]
fn list_then_reply_keeps_probability_and_stores_streamed_text() {
    let db = db();
    db.create_todo("Call Ana", None).unwrap();
    let mut chat = Chat::new(&db);
    chat.user(MIXED);
    let snapshot = chat.snapshot();
    let turn = prepare(&db, &snapshot, MIXED, false);
    let mut runner = ScriptedRunner::new([
        list(),
        Pass {
            text: "What\0 else?",
            probability: Some(0.01),
            ..Default::default()
        },
    ]);
    let (result, events) = execute(&turn, &mut runner, 128);
    assert_eq!(result.unwrap().tools.unwrap().call_probability, Some(0.97));
    assert!(matches!(
        events.as_slice(),
        [GenerationEvent::Text { .. }, GenerationEvent::Done { .. }]
    ));
    let reply = turn
        .finish(&db, &snapshot, "", vec![], &zone())
        .unwrap()
        .reply;
    assert_eq!(reply.tool_turn.unwrap().confirm, Confirm::None);
    assert!(reply.message.text.ends_with("\n\nWhat else?"));
}

#[test]
fn the_follow_up_is_skipped_when_the_budget_is_spent_or_would_overflow() {
    for (budget, measured) in [(10, 16), (128, 4090)] {
        let db = db();
        let mut chat = Chat::new(&db);
        chat.user(MIXED);
        let snapshot = chat.snapshot();
        let turn = prepare(&db, &snapshot, MIXED, false);
        let mut runner = ScriptedRunner::new([list()]);
        runner.measured.push_back(measured);
        assert_eq!(
            execute(&turn, &mut runner, budget)
                .0
                .unwrap()
                .tools
                .unwrap()
                .calls,
            list().calls
        );
    }
}

#[test]
fn interrupted_follow_up_keeps_no_outcome_and_emits_no_done() {
    for cancelled in [true, false] {
        let db = db();
        let mut chat = Chat::new(&db);
        chat.user(MIXED);
        let snapshot = chat.snapshot();
        let turn = prepare(&db, &snapshot, MIXED, false);
        let mut first = list();
        first.cancel_after = cancelled;
        let mut passes = vec![first];
        if !cancelled {
            passes.push(Pass {
                fail: true,
                ..Default::default()
            });
        }
        let (result, events) = execute(&turn, &mut ScriptedRunner::new(passes), 128);
        assert!(
            matches!(result, Err(llm::Error::Cancelled) if cancelled)
                || matches!(result, Err(llm::Error::Panicked) if !cancelled)
        );
        assert!(events.is_empty());
        assert!(!turn.has_outcome());
        assert!(!turn.is_saved());
        assert!(
            tool_turn::states(&db, snapshot.session_uuid())
                .unwrap()
                .is_empty()
        );
        assert!(db.list_todos().unwrap().is_empty());
    }
}

#[test]
fn an_abstained_follow_up_changes_nothing() {
    let db = db();
    db.create_todo("Call Ana", None).unwrap();
    let before = db.list_todos().unwrap();
    let mut chat = Chat::new(&db);
    chat.user(MIXED);
    let snapshot = chat.snapshot();
    let turn = prepare(&db, &snapshot, MIXED, false);
    let mut runner = ScriptedRunner::new([
        list(),
        Pass {
            abstained: true,
            ..Default::default()
        },
    ]);
    let outcome = execute(&turn, &mut runner, 128).0.unwrap().tools.unwrap();
    assert!(outcome.abstained);
    assert_eq!(outcome.calls, list().calls);
    turn.finish(&db, &snapshot, "", vec![], &zone()).unwrap();
    assert_eq!(db.list_todos().unwrap(), before);
}

#[test]
fn a_refused_finish_keeps_the_outcome() {
    let db = db();
    let mut chat = Chat::new(&db);
    let first = chat.send("Buy milk", &save(SURE).calls);
    chat.back();
    let snapshot = chat.snapshot();
    let turn = prepare(&db, &snapshot, "Buy milk", false);
    execute(&turn, &mut ScriptedRunner::new([save(SURE)]), 128)
        .0
        .unwrap();
    assert!(matches!(
        turn.finish(&db, &snapshot, "", vec![], &zone()),
        Err(db::Error::Refused(crate::todo::Refusal::EarlierReplyStands))
    ));
    assert!(turn.has_outcome());
    tool_turn::undo(&db, first.reply.uuid).unwrap();
    turn.finish(&db, &chat.snapshot(), "", vec![], &zone())
        .unwrap();
    assert!(turn.is_saved() && !turn.has_outcome());
}

#[test]
fn a_list_changed_before_commit_is_refused() {
    for midnight in [false, true] {
        let (db, clock) = db_with_clock();
        let bank = db
            .create_todo("Call bank", Some(local_ms("2026-11-11 18:00")))
            .unwrap();
        db.create_todo("Return books", Some(local_ms("2026-11-12 18:00")))
            .unwrap();
        clock.set(local_ms("2026-11-11 23:59"));
        let mut chat = Chat::new(&db);
        let user = "List today's tasks and mark the first one done";
        chat.user(user);
        let snapshot = chat.snapshot();
        let turn = prepare(&db, &snapshot, user, false);
        let mut first = list();
        first.calls = vec![call(LIST_TOOL, &[("filter", text("today"))])];
        let complete = Pass {
            calls: vec![call(COMPLETE_TOOL, &[("number", ToolValue::Integer(1))])],
            probability: SURE,
            ..Default::default()
        };
        execute(&turn, &mut ScriptedRunner::new([first, complete]), 128)
            .0
            .unwrap();
        if midnight {
            clock.set(local_ms("2026-11-12 00:00"));
        } else {
            db.update_todo(bank.id, bank.version, "Call insurer", bank.due_at_ms)
                .unwrap();
        }
        assert!(matches!(
            turn.finish(&db, &snapshot, "", vec![], &zone()),
            Err(db::Error::ConversationChanged)
        ));
        assert!(
            db.list_todos()
                .unwrap()
                .iter()
                .all(crate::todo::Todo::is_open)
        );
    }
}

#[test]
fn a_turn_without_tools_clears_the_clients_tools() {
    let db = db();
    let mut chat = Chat::new(&db);
    chat.user("Hi");
    let turn = prepare(&db, &chat.snapshot(), "Hi", true);
    let mut runner = ScriptedRunner::new([Pass::default()]);
    assert!(execute(&turn, &mut runner, 128).0.unwrap().tools.is_none());
    assert!(runner.seen[0].tools.is_none());
}

#[test]
fn a_time_qualified_save_after_a_title_is_kept() {
    let db = db();
    let done = db.create_todo("Research and save passwords", None).unwrap();
    db.set_todo_completed(done.id, done.version, true).unwrap();
    let user = "List research and save passwords today";
    let mut chat = Chat::new(&db);
    chat.user(user);
    let snapshot = chat.snapshot();
    let turn = prepare(&db, &snapshot, user, false);
    let mut first = list();
    first.calls = vec![call(LIST_TOOL, &[("query", text("research"))])];
    let second = Pass {
        calls: vec![call(
            SAVE_TOOL,
            &[("title", text("Save passwords")), ("when", text("today"))],
        )],
        probability: SURE,
        ..Default::default()
    };
    execute(&turn, &mut ScriptedRunner::new([first, second]), 128)
        .0
        .unwrap();
    let finished = turn.finish(&db, &snapshot, "", vec![], &zone()).unwrap();
    let open = db
        .list_todos()
        .unwrap()
        .into_iter()
        .find(crate::todo::Todo::is_open)
        .unwrap();
    assert_eq!(open.title, "Save passwords");
    let today = local_ms("2026-11-12 00:00")..local_ms("2026-11-13 00:00");
    assert!(today.contains(&open.due_at_ms.unwrap()));
    assert!(
        finished
            .reply
            .message
            .text
            .contains("Saved “Save passwords”")
    );
}
