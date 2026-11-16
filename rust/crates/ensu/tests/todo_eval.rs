//! Accuracy and latency of To Do tool calls against a labelled set of chat
//! turns. Run per model:
//!
//! ```sh
//! ENSU_TEST_MODEL=/path/model.gguf cargo test -p ente-ensu --test todo_eval -- --ignored --nocapture
//! ```
//!
//! Optional: `ENSU_EVAL_CASES` (another JSONL file), `ENSU_EVAL_OUT` (write a
//! JSON report), `ENSU_EVAL_MIN_ROUTE` and `ENSU_EVAL_MAX_FALSE_CHANGE`
//! (fail below or above these rates), `ENSU_EVAL_CALL_PROBABILITY`.

#![cfg(test)]

use std::time::Instant;

use ente_ensu::llm::{self, ChatMessage, ChatRequest, Context, ContextParams, ToolCall};
use ente_ensu::todo;
use serde::Deserialize;
use serde_json::{Value, json};

#[derive(Deserialize)]
struct Case {
    id: String,
    #[serde(default)]
    history: Vec<ChatMessage>,
    user: String,
    /// "tool" or "reply".
    expect: String,
    #[serde(default)]
    calls: Vec<ExpectedCall>,
}

#[derive(Deserialize)]
struct ExpectedCall {
    name: String,
    /// Words the title must contain, case-insensitively.
    #[serde(default)]
    title: Vec<String>,
    /// The exact quoted deadline. `null` means no deadline; absent means
    /// unchecked.
    #[serde(default, deserialize_with = "present")]
    when: Option<Option<String>>,
    #[serde(default)]
    filter: Option<String>,
    #[serde(default)]
    number: Option<i64>,
    /// Words the task reference must contain.
    #[serde(default)]
    task: Vec<String>,
}

fn present<'de, D: serde::Deserializer<'de>>(d: D) -> Result<Option<Option<String>>, D::Error> {
    Ok(Some(Option::deserialize(d)?))
}

fn contains_all(value: Option<&str>, words: &[String]) -> bool {
    let value = value.unwrap_or_default().to_lowercase();
    words
        .iter()
        .all(|word| value.contains(&word.to_lowercase()))
}

/// The clock the labels assume: Thursday 12 November 2026, 14:30 local time.
fn now() -> chrono::NaiveDateTime {
    chrono::NaiveDate::from_ymd_opt(2026, 11, 12)
        .unwrap()
        .and_hms_opt(14, 30, 0)
        .unwrap()
}

/// Deadlines match when both resolve to the same time, so equivalent quotes
/// ("Thursday at 11 AM", "on Thursday at 11 AM") count as correct.
fn same_deadline(expected: Option<&str>, actual: Option<&str>) -> bool {
    let resolve = |quote: &str| todo::timing::parse_deadline(quote, now()).map(|d| d.at);
    match (expected, actual) {
        (None, None) => true,
        (Some(expected), Some(actual)) => {
            expected == actual || resolve(expected).is_some_and(|at| resolve(actual) == Some(at))
        }
        _ => false,
    }
}

fn call_matches(expected: &ExpectedCall, actual: &ToolCall) -> bool {
    expected.name == actual.name
        && contains_all(actual.text("title"), &expected.title)
        && contains_all(actual.text("task"), &expected.task)
        && expected
            .when
            .as_ref()
            .is_none_or(|when| same_deadline(when.as_deref(), actual.text("when")))
        && expected
            .filter
            .as_ref()
            .is_none_or(|filter| Some(filter.as_str()) == actual.text("filter"))
        && expected
            .number
            .is_none_or(|number| Some(number) == actual.integer("number"))
}

const CHANGES: [&str; 2] = [todo::SAVE_TOOL, todo::COMPLETE_TOOL];

#[test]
#[ignore = "requires ENSU_TEST_MODEL"]
fn todo_tool_calls_meet_accuracy_targets() {
    if let Ok(directory) = std::env::var("ENSU_TEST_BACKEND_DIR") {
        llm::init_backend_from_directory(&directory).unwrap();
    }
    let model = llm::Model::load(llm::ModelLoadParams {
        model_path: std::env::var("ENSU_TEST_MODEL").unwrap(),
        n_gpu_layers: Some(99),
        use_mmap: None,
        use_mlock: None,
    })
    .unwrap();
    let context = Context::new(
        &model,
        ContextParams {
            context_size: Some(4096),
            n_threads: Some(4),
            n_threads_generation: None,
            n_batch: Some(256),
        },
    )
    .unwrap();
    let path = std::env::var("ENSU_EVAL_CASES").unwrap_or_else(|_| {
        concat!(env!("CARGO_MANIFEST_DIR"), "/tests/data/todo_eval.jsonl").into()
    });
    let cases: Vec<Case> = std::fs::read_to_string(path)
        .unwrap()
        .lines()
        .filter(|line| !line.trim().is_empty())
        .map(|line| serde_json::from_str(line).unwrap_or_else(|err| panic!("{err}: {line}")))
        .collect();
    let defaults = ente_ensu::config::defaults();
    let system = defaults
        .mobile_system_prompt_body
        .replace(&defaults.system_prompt_date_placeholder, "2026-11-12");
    let probability = std::env::var("ENSU_EVAL_CALL_PROBABILITY")
        .ok()
        .map(|value| value.parse::<f32>().unwrap());

    let (mut route_ok, mut calls_ok, mut false_changes, mut misses) = (0, 0, 0, 0);
    let (mut prompt_tokens, mut elapsed_ms) = (0_i64, 0_u128);
    let mut failures = Vec::new();
    let mut probabilities = Vec::new();
    for case in &cases {
        let mut messages = vec![ChatMessage::new("system", system.clone())];
        messages.extend(case.history.iter().cloned());
        messages.push(ChatMessage::new("user", case.user.clone()));
        let mut tools = todo::chat_tools(&case.user);
        if let Some(probability) = probability {
            tools.min_call_probability = probability;
        }
        let request = ChatRequest {
            messages,
            temperature: Some(0.0),
            max_tokens: Some(160),
            tools: Some(tools),
            ..Default::default()
        };
        let started = Instant::now();
        let mut reply = String::new();
        let summary = context
            .generate_chat_stream(request, &mut |event| {
                if let llm::GenerationEvent::Text { text, .. } = event {
                    reply.push_str(&text);
                }
            })
            .unwrap_or_else(|err| panic!("{}: {err}", case.id));
        elapsed_ms += started.elapsed().as_millis();
        prompt_tokens += i64::from(summary.prompt_tokens.unwrap_or_default());
        let outcome = summary.tools.expect("tool outcome");
        assert!(outcome.supported, "this model has no native tool calls");
        probabilities.push((
            case.expect == "tool",
            outcome.call_probability.unwrap_or_default(),
        ));
        let called = !outcome.calls.is_empty();
        let routed = called == (case.expect == "tool");
        route_ok += usize::from(routed);
        let expected_changes = case
            .calls
            .iter()
            .any(|call| CHANGES.contains(&call.name.as_str()));
        if outcome
            .calls
            .iter()
            .any(|call| CHANGES.contains(&call.name.as_str()))
            && !expected_changes
        {
            false_changes += 1;
        }
        if case.expect == "tool" && !called {
            misses += 1;
        }
        let matched = routed
            && outcome.calls.len() == case.calls.len()
            && case
                .calls
                .iter()
                .zip(&outcome.calls)
                .all(|(e, a)| call_matches(e, a));
        calls_ok += usize::from(matched);
        if !matched {
            failures.push(json!({
                "id": case.id,
                "user": case.user,
                "expected": case.expect,
                "calls": outcome.calls,
                "reply": reply,
                "call_probability": outcome.call_probability,
            }));
        }
    }
    let n = cases.len() as f64;
    let reply_cases = cases
        .iter()
        .filter(|case| case.expect == "reply")
        .count()
        .max(1) as f64;
    let report = json!({
        "model": std::env::var("ENSU_TEST_MODEL").unwrap(),
        "cases": cases.len(),
        "route_accuracy": route_ok as f64 / n,
        "call_accuracy": calls_ok as f64 / n,
        "false_change_rate": false_changes as f64 / reply_cases,
        "missed_tool_rate": misses as f64 / (n - reply_cases).max(1.0),
        "mean_prompt_tokens": prompt_tokens as f64 / n,
        "mean_latency_ms": elapsed_ms as f64 / n,
        "call_probability": probabilities
            .iter()
            .map(|(tool, p)| json!({"expected_tool": tool, "p": p}))
            .collect::<Vec<Value>>(),
        "failures": failures,
    });
    if let Ok(out) = std::env::var("ENSU_EVAL_OUT") {
        std::fs::write(out, serde_json::to_string_pretty(&report).unwrap()).unwrap();
    }
    println!(
        "route {:.3}  calls {:.3}  false changes {:.3}  missed {:.3}  prompt {:.0} tok  latency {:.0} ms",
        report["route_accuracy"].as_f64().unwrap(),
        report["call_accuracy"].as_f64().unwrap(),
        report["false_change_rate"].as_f64().unwrap(),
        report["missed_tool_rate"].as_f64().unwrap(),
        report["mean_prompt_tokens"].as_f64().unwrap(),
        report["mean_latency_ms"].as_f64().unwrap(),
    );
    for failure in report["failures"].as_array().unwrap() {
        println!("FAIL {failure}");
    }
    if let Ok(minimum) = std::env::var("ENSU_EVAL_MIN_ROUTE") {
        assert!(report["route_accuracy"].as_f64().unwrap() >= minimum.parse::<f64>().unwrap());
    }
    if let Ok(maximum) = std::env::var("ENSU_EVAL_MAX_FALSE_CHANGE") {
        assert!(report["false_change_rate"].as_f64().unwrap() <= maximum.parse::<f64>().unwrap());
    }
}

#[test]
fn labelled_cases_parse_and_their_deadlines_resolve() {
    let cases: Vec<Case> = include_str!("data/todo_eval.jsonl")
        .lines()
        .filter(|line| !line.trim().is_empty())
        .map(|line| serde_json::from_str(line).unwrap())
        .collect();
    let mut ids = std::collections::BTreeSet::new();
    for case in &cases {
        assert!(ids.insert(case.id.as_str()), "duplicate {}", case.id);
        assert!(
            matches!(case.expect.as_str(), "tool" | "reply"),
            "{}",
            case.id
        );
        assert_eq!(case.expect == "tool", !case.calls.is_empty(), "{}", case.id);
        for call in &case.calls {
            assert!(
                [todo::SAVE_TOOL, todo::LIST_TOOL, todo::COMPLETE_TOOL]
                    .contains(&call.name.as_str()),
                "{}",
                case.id
            );
            if let Some(Some(when)) = &call.when {
                assert!(case.user.contains(when.as_str()), "{}: {when}", case.id);
                assert!(
                    todo::timing::parse_deadline(when, now()).is_some(),
                    "{}: {when}",
                    case.id
                );
            }
        }
    }
}
