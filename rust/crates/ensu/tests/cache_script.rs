#![cfg(feature = "sqlite")]

use std::io::{BufWriter, Write};
use std::sync::{
    Arc,
    atomic::{AtomicI64, AtomicU64, Ordering},
};
use std::time::Duration;

use ente_ensu::conversation::GroundingCache;
use ente_ensu::db::chat::{Confirm, Undo};
use ente_ensu::db::{ChatDb, Clock, SqliteBackend, UuidGen};
use ente_ensu::llm::GenerationEvent;
use ente_ensu::todo;
use serde::Serialize;
use serde_json::{Value, json};
use uuid::Uuid;

mod support;

const CONTEXT_SIZE: i32 = 4096;

struct StepClock(AtomicI64);

impl Clock for StepClock {
    fn now_us(&self) -> i64 {
        self.0.fetch_add(1_000, Ordering::Relaxed)
    }
}

struct SeqUuid(AtomicU64);

impl UuidGen for SeqUuid {
    fn new_uuid(&self) -> Uuid {
        Uuid::from_u128(self.0.fetch_add(1, Ordering::Relaxed).into())
    }
}

enum Step {
    Say(&'static str, &'static str),
    UndoLast,
    Regenerate,
}

#[derive(Serialize)]
struct Pass {
    prompt_tokens: i32,
    reused: i32,
    redecoded: i32,
    prefill_ms: u128,
    first_text_ms: Option<u128>,
    #[serde(skip)]
    started: Duration,
    #[serde(skip)]
    prefilled: bool,
}

fn passes(events: &[(Duration, GenerationEvent)]) -> Vec<Pass> {
    let mut passes: Vec<Pass> = Vec::new();
    for (elapsed, event) in events {
        match *event {
            GenerationEvent::PromptProgress {
                processed_tokens,
                total_tokens,
                ..
            } => {
                if passes
                    .last()
                    .is_none_or(|pass| pass.prefilled || pass.prompt_tokens != total_tokens)
                {
                    passes.push(Pass {
                        prompt_tokens: total_tokens,
                        reused: processed_tokens,
                        redecoded: total_tokens - processed_tokens,
                        prefill_ms: 0,
                        first_text_ms: None,
                        started: *elapsed,
                        prefilled: false,
                    });
                }
                if processed_tokens == total_tokens {
                    let pass = passes.last_mut().unwrap();
                    pass.prefill_ms = (*elapsed - pass.started).as_millis();
                    pass.prefilled = true;
                }
            }
            GenerationEvent::Text { ref text, .. } if !text.is_empty() => {
                let pass = passes.last_mut().unwrap();
                pass.first_text_ms
                    .get_or_insert_with(|| (*elapsed - pass.started).as_millis());
            }
            _ => {}
        }
    }
    passes
}

fn write_line(output: &mut impl Write, value: &Value) {
    serde_json::to_writer(&mut *output, value).unwrap();
    writeln!(output).unwrap();
}

#[test]
#[ignore = "requires ENSU_TEST_MODEL"]
fn scripted_conversation_reports_prompt_reuse_per_turn() {
    let context = support::model_context(CONTEXT_SIZE);
    let cache = GroundingCache::default();
    let system = support::system_prompt();
    let temp = tempfile::tempdir().unwrap();
    let now = chrono::NaiveDate::from_ymd_opt(2026, 11, 12)
        .unwrap()
        .and_hms_opt(14, 30, 0)
        .unwrap();
    let now_us = todo::timing::local_millis(now, &chrono::Local).unwrap() * 1_000;
    let db = ChatDb::new(
        SqliteBackend::open(temp.path().join("chat.sqlite")).unwrap(),
        vec![7; 32],
        Arc::new(StepClock(AtomicI64::new(now_us))),
        Arc::new(SeqUuid(AtomicU64::new(1))),
    )
    .unwrap();
    for task in [
        "Renew passport",
        "Water the plants",
        "Return library books",
        "Call the electrician",
        "Wash the car",
    ] {
        db.create_todo(task, None).unwrap();
    }
    let session = db.create_session("Prompt cache").unwrap();
    let mut path = Vec::new();
    let steps = [
        Step::Say("chat", "Say hello in three words."),
        Step::Say("add", "Add buy milk to my to-do list."),
        Step::Say("chat", "What is 2 + 2? Reply with just the number."),
        Step::Say(
            "mention",
            "What do I need to renew my passport? One sentence.",
        ),
        Step::Say("chat", "What is the capital of France? One word."),
        Step::Say("list_then_act", "Show my open tasks and add buy eggs."),
        Step::Say("chat", "Say good morning in French."),
        Step::Say("complete", "Mark Water the plants as done."),
        Step::Say("retry", "Try again"),
        Step::UndoLast,
        Step::Say("chat", "What color is the sky on a clear day? One word."),
        Step::Regenerate,
        Step::Say(
            "mention",
            "How long can I keep library books? One sentence.",
        ),
        Step::Say("add", "Add pick up dry cleaning tomorrow to my to-do list."),
        Step::Say("retry", "Try again"),
        Step::UndoLast,
        Step::Say("chat", "What is 8 + 6? Reply with just the number."),
        Step::Regenerate,
        Step::Say("list_then_act", "Show my open tasks and add buy bread."),
        Step::Say("chat", "Say good evening in Spanish."),
        Step::Say("mention", "How often should I wash the car? One sentence."),
        Step::Say("complete", "Mark Return library books as done."),
        Step::Say("retry", "Try again"),
        Step::UndoLast,
        Step::Say("chat", "What is 12 + 9? Reply with just the number."),
        Step::Regenerate,
        Step::Say("list_then_act", "Show my open tasks and add buy coffee."),
        Step::Say("chat", "Say goodbye in three words."),
    ];
    let model = std::env::var("ENSU_TEST_MODEL").unwrap();
    let model = std::path::Path::new(&model)
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap();
    let out = std::env::var("ENSU_CACHE_OUT").unwrap();
    let mut output = BufWriter::new(std::fs::File::create(&out).unwrap());
    write_line(
        &mut output,
        &json!({
            "model": model,
            "partial_prompt_reuse": context.supports_partial_prompt_reuse(),
            "supports_tools": context.supports_tools(),
        }),
    );
    for (index, step) in steps.iter().enumerate() {
        let turn = index + 1;
        let (label, run) = match step {
            Step::Say(label, text) => {
                let user = db
                    .insert_message(session.uuid, "self", text, path.last().copied(), vec![])
                    .unwrap();
                path.push(user.uuid);
                (*label, true)
            }
            Step::UndoLast => {
                let states = db.tool_turn_states(session.uuid).unwrap();
                let target = path.iter().rev().find(|uuid| {
                    states
                        .get(uuid)
                        .is_some_and(|state| state.undo == Undo::Available)
                });
                if let Some(&reply) = target {
                    db.undo_tool_turn(reply).unwrap();
                }
                write_line(
                    &mut output,
                    &json!({
                        "turn": turn, "label": "undo", "skipped": target.is_none(),
                        "passes": [], "generated_tokens": null, "called": [],
                        "offered": false, "applied": false,
                    }),
                );
                continue;
            }
            Step::Regenerate => {
                let states = db.tool_turn_states(session.uuid).unwrap();
                let allowed = path
                    .last()
                    .is_some_and(|reply| states.get(reply).is_none_or(|state| state.can_retry));
                if allowed {
                    path.pop();
                }
                ("regenerate", allowed)
            }
        };
        if !run {
            write_line(
                &mut output,
                &json!({
                    "turn": turn, "label": label, "skipped": true,
                    "passes": [], "generated_tokens": null, "called": [],
                    "offered": false, "applied": false,
                }),
            );
            continue;
        }
        let snapshot = db.conversation_snapshot(session.uuid, &path).unwrap();
        let run = support::run_turn(&db, &context, &cache, &snapshot, &system, 96, |_| {});
        let passes = passes(&run.events);
        let calls = run
            .summary
            .tools
            .as_ref()
            .map(|outcome| outcome.calls.as_slice())
            .unwrap_or_default();
        let names: Vec<_> = calls.iter().map(|call| call.name.as_str()).collect();
        assert!((1..=2).contains(&passes.len()), "step {turn}");
        assert_eq!(
            run.summary.prompt_tokens,
            Some(passes.iter().map(|pass| pass.prompt_tokens).sum()),
            "step {turn}"
        );
        if passes.len() == 2 {
            assert_eq!(names.first(), Some(&todo::LIST_TOOL), "step {turn}");
            assert!(passes[0].first_text_ms.is_none(), "step {turn}");
        }
        for pass in &passes {
            assert!(pass.prefilled, "step {turn}");
            assert!(
                (0..=pass.prompt_tokens).contains(&pass.reused),
                "step {turn}"
            );
            assert!(pass.prompt_tokens <= CONTEXT_SIZE, "step {turn}");
            assert_eq!(
                pass.reused + pass.redecoded,
                pass.prompt_tokens,
                "step {turn}"
            );
        }
        if index == 0 {
            assert_eq!(passes[0].reused, 0);
        }
        assert_eq!(
            passes.iter().any(|pass| pass.first_text_ms.is_some()),
            !run.reply.is_empty(),
            "step {turn}"
        );
        path.push(run.finished.message.uuid);
        let state = run.finished.tool_turn;
        write_line(
            &mut output,
            &json!({
                "turn": turn, "label": label, "skipped": false, "passes": passes,
                "generated_tokens": run.summary.generated_tokens, "called": names,
                "offered": state.is_some_and(|state| state.confirm == Confirm::Offered),
                "applied": state.is_some_and(|state| state.undo == Undo::Available),
            }),
        );
    }
    output.flush().unwrap();
    assert_eq!(
        std::fs::read_to_string(out).unwrap().lines().count(),
        steps.len() + 1
    );
}
