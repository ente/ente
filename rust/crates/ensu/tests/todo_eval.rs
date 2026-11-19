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
    expect: String,
    #[serde(default)]
    calls: Vec<ExpectedCall>,
    #[serde(default)]
    todos: Option<Vec<String>>,
}

const BACKGROUND_TODOS: [&str; 4] = [
    "Order new contact lenses",
    "Repot the fern",
    "Tune the ukulele",
    "Refill the bird feeder",
];

#[derive(Deserialize)]
struct ExpectedCall {
    name: String,
    #[serde(default)]
    title: Vec<String>,
    #[serde(default, deserialize_with = "present")]
    when: Option<Option<String>>,
    #[serde(default)]
    filter: Option<String>,
    #[serde(default)]
    number: Option<i64>,
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

fn now() -> chrono::NaiveDateTime {
    chrono::NaiveDate::from_ymd_opt(2026, 11, 12)
        .unwrap()
        .and_hms_opt(14, 30, 0)
        .unwrap()
}

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
            .is_none_or(|filter| filter == actual.text("filter").unwrap_or("open"))
        && expected
            .number
            .is_none_or(|number| Some(number) == actual.integer("number"))
}

const CHANGES: [&str; 2] = [todo::SAVE_TOOL, todo::COMPLETE_TOOL];

fn shown(history: &[ChatMessage]) -> Vec<String> {
    history
        .last()
        .filter(|message| message.role == "tool")
        .map_or_else(Vec::new, |message| {
            message
                .content
                .lines()
                .filter_map(|line| {
                    let (number, rest) = line.split_once(". ")?;
                    number.parse::<usize>().ok()?;
                    Some(rest.split(" — ").next().unwrap_or(rest).to_owned())
                })
                .collect()
        })
}

fn open_todos(case: &Case) -> Vec<String> {
    if let Some(todos) = &case.todos {
        return todos.clone();
    }
    let shown = shown(&case.history);
    if shown.is_empty() {
        BACKGROUND_TODOS
            .iter()
            .map(|title| (*title).to_owned())
            .collect()
    } else {
        shown
    }
}

const NOW_MS: i64 = 1_794_493_800_000;

#[derive(serde::Serialize, Deserialize)]
struct Recorded {
    id: String,
    raw_calls: Vec<ToolCall>,
    call_probability: Option<f32>,
    calls: Vec<ToolCall>,
    unsure: bool,
    text: String,
}

fn todos(case: &Case, open: &[&str]) -> (Vec<todo::Todo>, Vec<uuid::Uuid>) {
    let shown = shown(&case.history);
    let mut titles: Vec<&str> = open.to_vec();
    for title in &shown {
        if !titles.contains(&title.as_str()) {
            titles.push(title);
        }
    }
    let todos: Vec<todo::Todo> = titles
        .iter()
        .enumerate()
        .map(|(i, title)| todo::Todo {
            id: uuid::Uuid::from_u128(i as u128 + 1),
            title: (*title).to_owned(),
            due_at_ms: None,
            completed_at_ms: None,
            created_at_ms: i as i64,
            updated_at_ms: i as i64,
            version: 1,
        })
        .collect();
    let shown = shown
        .iter()
        .filter_map(|title| todos.iter().find(|todo| &todo.title == title))
        .map(|todo| todo.id)
        .collect();
    (todos, shown)
}

fn planned(
    case: &Case,
    open: &[&str],
    calls: &[ToolCall],
    call_probability: Option<f32>,
) -> (Vec<ToolCall>, bool, String) {
    let (todos, shown) = todos(case, open);
    let mut next = 1000_u128;
    match todo::plan(
        calls,
        &case.user,
        &shown,
        todos,
        (NOW_MS, &chrono::Utc),
        call_probability,
        &mut || {
            next += 1;
            uuid::Uuid::from_u128(next)
        },
    ) {
        Ok(plan) => {
            let text = plan.text(plan.unsure, &chrono::Utc);
            (plan.calls, plan.unsure, text)
        }
        Err(name) => (calls.to_vec(), true, format!("unknown tool {name}")),
    }
}

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
    let mut raw_calls_ok = 0;
    let mut false_by_tool = std::collections::BTreeMap::<&str, usize>::new();
    let (mut applied_right, mut offered_right, mut applied_wrong, mut offered_wrong) = (0, 0, 0, 0);
    let (mut prompt_tokens, mut elapsed_ms) = (0_i64, 0_u128);
    let mut failures = Vec::new();
    let mut recorded = Vec::new();
    let mut probabilities = Vec::new();
    for case in &cases {
        let mut messages = vec![ChatMessage::new("system", system.clone())];
        messages.extend(case.history.iter().cloned());
        messages.push(ChatMessage::new("user", case.user.clone()));
        let open = open_todos(case);
        let open: Vec<&str> = open.iter().map(String::as_str).collect();
        let mut tools = todo::chat_tools(&case.user, &open);
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
        if case.expect == "reply" {
            for name in [todo::SAVE_TOOL, todo::COMPLETE_TOOL, todo::LIST_TOOL] {
                if outcome.calls.iter().any(|call| call.name == name) {
                    *false_by_tool.entry(name).or_insert(0) += 1;
                }
            }
        }
        if case.expect == "tool" && !called {
            misses += 1;
        }
        let matches = |calls: &[ToolCall]| {
            routed
                && calls.len() == case.calls.len()
                && case
                    .calls
                    .iter()
                    .zip(calls)
                    .all(|(e, a)| call_matches(e, a))
        };
        let (refined, unsure, text) =
            planned(case, &open, &outcome.calls, outcome.call_probability);
        recorded.push(Recorded {
            id: case.id.clone(),
            raw_calls: outcome.calls.clone(),
            call_probability: outcome.call_probability,
            calls: refined.clone(),
            unsure,
            text,
        });
        raw_calls_ok += usize::from(matches(&outcome.calls));
        let matched = matches(&refined);
        calls_ok += usize::from(matched);
        let changes = refined
            .iter()
            .any(|call| CHANGES.contains(&call.name.as_str()));
        if changes {
            let direct = !unsure;
            match (matched, direct) {
                (true, true) => applied_right += 1,
                (true, false) => offered_right += 1,
                (false, true) => applied_wrong += 1,
                (false, false) => offered_wrong += 1,
            }
        }
        if !matched {
            failures.push(json!({
                "id": case.id,
                "user": case.user,
                "expected": case.expect,
                "calls": refined,
                "raw_calls": outcome.calls,
                "reply": reply,
                "call_probability": outcome.call_probability,
            }));
        }
    }
    let n = cases.len() as f64;
    let reply_cases = cases.iter().filter(|case| case.expect == "reply").count();
    let tool_cases = (cases.len() - reply_cases).max(1) as f64;
    let reply_cases = reply_cases.max(1) as f64;
    let report = json!({
        "model": std::env::var("ENSU_TEST_MODEL").unwrap(),
        "cases": cases.len(),
        "route_accuracy": route_ok as f64 / n,
        "call_accuracy": calls_ok as f64 / n,
        "raw_call_accuracy": raw_calls_ok as f64 / n,
        "false_change_rate": false_changes as f64 / reply_cases,
        "changes_applied_right": applied_right as f64 / n,
        "changes_offered_right": offered_right as f64 / n,
        "changes_applied_wrong": applied_wrong as f64 / n,
        "changes_offered_wrong": offered_wrong as f64 / n,
        "false_call_rate_by_tool": false_by_tool
            .iter()
            .map(|(name, count)| ((*name).to_owned(), json!(*count as f64 / reply_cases)))
            .collect::<serde_json::Map<_, _>>(),
        "missed_tool_rate": misses as f64 / tool_cases,
        "mean_prompt_tokens": prompt_tokens as f64 / n,
        "mean_latency_ms": elapsed_ms as f64 / n,
        "call_probability": probabilities
            .iter()
            .map(|(tool, p)| json!({"expected_tool": tool, "p": p}))
            .collect::<Vec<Value>>(),
        "failures": failures,
    });
    if let Ok(out) = std::env::var("ENSU_EVAL_RECORD") {
        let lines: Vec<String> = recorded
            .iter()
            .map(|record| serde_json::to_string(record).unwrap())
            .collect();
        std::fs::write(out, lines.join("\n") + "\n").unwrap();
    }
    if let Ok(out) = std::env::var("ENSU_EVAL_OUT") {
        std::fs::write(out, serde_json::to_string_pretty(&report).unwrap()).unwrap();
    }
    println!(
        "route {:.3}  calls {:.3} (raw {:.3})  false changes {:.3}  missed {:.3}  prompt {:.0} tok  latency {:.0} ms",
        report["route_accuracy"].as_f64().unwrap(),
        report["call_accuracy"].as_f64().unwrap(),
        report["raw_call_accuracy"].as_f64().unwrap(),
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
    assert_eq!(now().and_utc().timestamp_millis(), NOW_MS);
    let cases: Vec<Case> = [
        include_str!("data/todo_eval.jsonl"),
        include_str!("data/todo_eval_holdout.jsonl"),
    ]
    .concat()
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

#[test]
fn recorded_model_calls_plan_the_same() {
    let cases: std::collections::BTreeMap<String, Case> = include_str!("data/todo_eval.jsonl")
        .lines()
        .filter(|line| !line.trim().is_empty())
        .map(|line| serde_json::from_str::<Case>(line).unwrap())
        .map(|case| (case.id.clone(), case))
        .collect();
    let mut replayed = 0;
    for line in include_str!("data/todo_replay.jsonl")
        .lines()
        .filter(|line| !line.trim().is_empty())
    {
        let record: Recorded = serde_json::from_str(line).unwrap();
        let case = &cases[&record.id];
        let open = open_todos(case);
        let open: Vec<&str> = open.iter().map(String::as_str).collect();
        let (calls, unsure, text) =
            planned(case, &open, &record.raw_calls, record.call_probability);
        assert_eq!(
            (calls, unsure, text),
            (record.calls, record.unsure, record.text),
            "{}: {}",
            record.id,
            case.user
        );
        replayed += 1;
    }
    assert_eq!(replayed, cases.len());
}
