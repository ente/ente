#![cfg(test)]
#![cfg(feature = "sqlite")]

use std::sync::Arc;

use ente_ensu::conversation::GroundingCache;
use ente_ensu::db::chat::{Confirm, ConversationSnapshot, FinishedReply};
use ente_ensu::db::{ChatDb, Clock, RandomUuidGen, SqliteBackend};
use ente_ensu::llm::{self, ChatMessage, ToolCall};
use ente_ensu::todo;
use serde::Deserialize;
use serde_json::{Value, json};

mod support;

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
    #[serde(default)]
    initial: Option<Vec<TaskState>>,
    #[serde(default)]
    state: Option<Vec<TaskState>>,
    #[serde(default)]
    listed: Option<Vec<Vec<String>>>,
    #[serde(default)]
    confirmation: Option<bool>,
    #[serde(default)]
    undo: bool,
    #[serde(default)]
    probe: Vec<ToolCall>,
}

impl Case {
    fn expects_change(&self) -> bool {
        self.calls
            .iter()
            .any(|call| CHANGES.contains(&call.name.as_str()))
    }
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
    #[serde(default, deserialize_with = "present")]
    query: Option<Option<String>>,
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

fn normalized(text: &str) -> String {
    text.split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase()
}

#[derive(Clone, Default)]
struct CompletionContext {
    tasks: Vec<todo::Todo>,
    shown: Vec<Option<uuid::Uuid>>,
}

impl CompletionContext {
    fn capture(tasks: Vec<todo::Todo>, shown: &[String]) -> Self {
        let mut context = Self {
            tasks,
            shown: Vec::new(),
        };
        context.set_shown(shown);
        context
    }

    fn unique(&self, matches: impl Fn(&todo::Todo) -> bool) -> Option<uuid::Uuid> {
        let mut tasks = self.tasks.iter().filter(|task| matches(task));
        let first = tasks.next()?;
        tasks.next().is_none().then_some(first.id)
    }

    fn set_shown(&mut self, shown: &[String]) {
        self.shown = shown
            .iter()
            .map(|title| self.unique(|task| normalized(&task.title) == normalized(title)))
            .collect();
    }

    fn position(&self, number: i64) -> Option<uuid::Uuid> {
        let index = usize::try_from(number).ok()?.checked_sub(1)?;
        self.shown.get(index).copied().flatten()
    }

    fn named(&self, name: &str) -> Option<uuid::Uuid> {
        self.unique(|task| task.is_open() && normalized(&task.title) == normalized(name))
    }

    fn expected(&self, expected: &ExpectedCall) -> Option<uuid::Uuid> {
        if let Some(number) = expected.number {
            let id = self.position(number)?;
            return self
                .tasks
                .iter()
                .find(|task| task.id == id)
                .filter(|task| contains_all(Some(&task.title), &expected.task))
                .map(|task| task.id);
        }
        if expected.task.is_empty() {
            return None;
        }
        self.unique(|task| task.is_open() && contains_all(Some(&task.title), &expected.task))
    }

    fn actual(&self, actual: &ToolCall) -> Option<uuid::Uuid> {
        match (actual.integer("number"), actual.text("task")) {
            (Some(number), Some(task)) => {
                let id = self.position(number)?;
                (self.named(task) == Some(id)).then_some(id)
            }
            (Some(number), None) => self.position(number),
            (None, Some(task)) => self.named(task),
            (None, None) => None,
        }
    }
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

fn call_matches(
    expected: &ExpectedCall,
    actual: &ToolCall,
    context: Option<&CompletionContext>,
) -> bool {
    let references_match = contains_all(actual.text("task"), &expected.task)
        && expected
            .number
            .is_none_or(|number| Some(number) == actual.integer("number"));
    let equivalent = expected.name == todo::COMPLETE_TOOL
        && context.is_some_and(|context| {
            context
                .expected(expected)
                .is_some_and(|id| context.actual(actual) == Some(id))
        });
    let consistent = expected.name != todo::COMPLETE_TOOL
        || actual.integer("number").is_none()
        || actual.text("task").is_none()
        || context.is_none_or(|context| context.actual(actual).is_some());
    expected.name == actual.name
        && contains_all(actual.text("title"), &expected.title)
        && (references_match || equivalent)
        && consistent
        && expected
            .when
            .as_ref()
            .is_none_or(|when| same_deadline(when.as_deref(), actual.text("when")))
        && expected
            .filter
            .as_ref()
            .is_none_or(|filter| filter == actual.text("filter").unwrap_or("open"))
        && expected.query.as_ref().is_none_or(|query| {
            query.as_deref().map(str::to_lowercase) == actual.text("query").map(str::to_lowercase)
        })
}

fn calls_match(expected: &[ExpectedCall], actual: &[ToolCall]) -> bool {
    calls_match_with_context(expected, actual, None, &[])
}

fn calls_match_with_context(
    expected: &[ExpectedCall],
    actual: &[ToolCall],
    mut context: Option<CompletionContext>,
    listed: &[Vec<String>],
) -> bool {
    if expected.len() != actual.len() {
        return false;
    }
    if expected.iter().all(|call| call.name == todo::SAVE_TOOL) {
        return unordered_matches(expected, actual, |expected, actual| {
            call_matches(expected, actual, None)
        });
    }
    let mut listed = listed.iter();
    for (expected, actual) in expected.iter().zip(actual) {
        if !call_matches(expected, actual, context.as_ref()) {
            return false;
        }
        if expected.name == todo::LIST_TOOL
            && let Some(context) = context.as_mut()
        {
            context.set_shown(listed.next().map(Vec::as_slice).unwrap_or_default());
        }
    }
    true
}

fn unordered_matches<E, A: Clone>(
    expected: &[E],
    actual: &[A],
    matches: impl Fn(&E, &A) -> bool + Copy,
) -> bool {
    if expected.len() != actual.len() {
        return false;
    }
    let Some((first, rest)) = expected.split_first() else {
        return true;
    };
    actual.iter().enumerate().any(|(i, call)| {
        matches(first, call)
            && unordered_matches(
                rest,
                &actual
                    .iter()
                    .enumerate()
                    .filter(|(j, _)| *j != i)
                    .map(|(_, call)| call.clone())
                    .collect::<Vec<_>>(),
                matches,
            )
    })
}

const CHANGES: [&str; 2] = [todo::SAVE_TOOL, todo::COMPLETE_TOOL];

const MIN_ROUTE_ACCURACY: f64 = 0.95;
const MIN_CALL_ACCURACY: f64 = 0.90;
const MAX_FALSE_CHANGE_RATE: f64 = 0.02;

fn non_mutating_cases(cases: &[Case]) -> usize {
    cases
        .iter()
        .filter(|case| case.expect != "safe" && !case.expects_change())
        .count()
}

fn threshold(name: &str, default: f64) -> f64 {
    let value = std::env::var(name)
        .map(|value| {
            value
                .parse::<f64>()
                .unwrap_or_else(|_| panic!("Invalid {name}: {value}"))
        })
        .unwrap_or(default);
    assert!(
        (0.0..=1.0).contains(&value),
        "{name} must be between 0 and 1"
    );
    value
}

fn accuracy_failures(
    report: &Value,
    min_route: f64,
    min_calls: f64,
    max_false_change: f64,
) -> Vec<String> {
    [
        ("route_accuracy", min_route, true),
        ("call_accuracy", min_calls, true),
        ("false_change_call_rate", max_false_change, false),
    ]
    .into_iter()
    .filter_map(|(metric, target, minimum)| {
        let actual = report[metric].as_f64().unwrap();
        let meets_target = if minimum {
            actual >= target
        } else {
            actual <= target
        };
        (!meets_target).then(|| {
            format!(
                "{metric}: {actual:.3}, expected {} {target:.3}",
                if minimum { ">=" } else { "<=" }
            )
        })
    })
    .collect()
}

fn shown(response: &str) -> Vec<String> {
    response
        .lines()
        .filter_map(|line| {
            let (number, rest) = line.split_once(". ")?;
            number.parse::<usize>().ok()?;
            Some(rest.split(" — ").next().unwrap_or(rest).to_owned())
        })
        .collect()
}

#[derive(serde::Serialize, Deserialize)]
struct Recorded {
    id: String,
    raw_calls: Vec<ToolCall>,
    call_probability: Option<f32>,
    calls: Vec<ToolCall>,
    unsure: bool,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    abstained: bool,
    #[serde(default, skip_serializing_if = "is_zero")]
    rejected_steps: u32,
    text: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    reply: String,
    state: StateResult,
}

fn is_zero(value: &u32) -> bool {
    *value == 0
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, Deserialize)]
struct TaskState {
    title: String,
    completed: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    due_at: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    aliases: Vec<String>,
}

impl TaskState {
    fn matches(&self, actual: &Self) -> bool {
        self.completed == actual.completed
            && self.due_at == actual.due_at
            && std::iter::once(&self.title)
                .chain(&self.aliases)
                .any(|title| normalized(title) == normalized(&actual.title))
    }
}

#[derive(Debug, PartialEq, serde::Serialize, Deserialize)]
struct StateResult {
    tasks: Vec<TaskState>,
    changed: bool,
    confirmation: bool,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    listed: Vec<Vec<String>>,
}

impl StateResult {
    fn matches(&self, case: &Case) -> bool {
        case.state
            .as_ref()
            .is_none_or(|expected| unordered_matches(expected, &self.tasks, TaskState::matches))
            && (case.expects_change() || !self.changed)
            && case
                .confirmation
                .is_none_or(|required| self.confirmation == required)
            && case
                .listed
                .as_ref()
                .is_none_or(|listed| &self.listed == listed)
    }
}

struct EvalClock;

impl Clock for EvalClock {
    fn now_us(&self) -> i64 {
        todo::timing::local_millis(now(), &chrono::Local).unwrap() * 1000
    }
}

struct ConversationCase {
    db: ChatDb<SqliteBackend>,
    snapshot: ConversationSnapshot,
}

impl ConversationCase {
    fn new(case: &Case) -> Self {
        let db = ChatDb::new(
            SqliteBackend::open_in_memory().unwrap(),
            vec![7; 32],
            Arc::new(EvalClock),
            Arc::new(RandomUuidGen),
        )
        .unwrap();
        if let Some(initial) = &case.initial {
            for task in initial {
                let due_at = task.due_at.as_ref().map(|at| {
                    let local =
                        chrono::NaiveDateTime::parse_from_str(at, "%Y-%m-%d %H:%M").unwrap();
                    todo::timing::local_millis(local, &chrono::Local).unwrap()
                });
                let stored = db.create_todo(&task.title, due_at).unwrap();
                if task.completed {
                    db.set_todo_completed(stored.id, stored.version, true)
                        .unwrap();
                }
            }
        } else {
            let titles = case.todos.as_ref().map_or_else(
                || BACKGROUND_TODOS.to_vec(),
                |todos| todos.iter().map(String::as_str).collect(),
            );
            for title in titles {
                db.create_todo(title, None).unwrap();
            }
        }
        let session = db.create_session(&case.id).unwrap();
        let mut path = Vec::new();
        for message in &case.history {
            let message = match message.role.as_str() {
                "user" => db
                    .insert_message(
                        session.uuid,
                        "self",
                        &message.content,
                        path.last().copied(),
                        vec![],
                    )
                    .unwrap(),
                "assistant" => {
                    db.finish_reply(
                        &db.conversation_snapshot(session.uuid, &path).unwrap(),
                        &message.content,
                        vec![],
                        Some(&llm::ToolOutcome {
                            calls: message.tool_calls.clone(),
                            call_probability: Some(1.0),
                            ..Default::default()
                        }),
                    )
                    .unwrap()
                    .message
                }
                "tool" => continue,
                role => panic!("unsupported history role: {role}"),
            };
            path.push(message.uuid);
        }
        if case.undo {
            db.undo_tool_turn(*path.last().unwrap()).unwrap();
        }
        let user = db
            .insert_message(
                session.uuid,
                "self",
                &case.user,
                path.last().copied(),
                vec![],
            )
            .unwrap();
        path.push(user.uuid);
        let snapshot = db.conversation_snapshot(session.uuid, &path).unwrap();
        Self { db, snapshot }
    }

    fn completion_context(&self) -> CompletionContext {
        let shown = self
            .snapshot
            .messages()
            .iter()
            .rev()
            .nth(1)
            .and_then(|message| {
                self.db
                    .tool_history(std::slice::from_ref(message))
                    .unwrap()
                    .remove(&message.uuid)
            })
            .and_then(|turn| {
                turn.calls
                    .iter()
                    .zip(&turn.responses)
                    .rev()
                    .find(|(call, _)| call.name == todo::LIST_TOOL)
                    .map(|(_, response)| shown(response))
            })
            .unwrap_or_default();
        CompletionContext::capture(self.db.list_todos().unwrap(), &shown)
    }

    fn finish(&self, case: &Case, outcome: &llm::ToolOutcome, reply: &str) -> Recorded {
        let before = self.db.list_todos().unwrap();
        let finished = self
            .db
            .finish_reply(&self.snapshot, reply, vec![], Some(outcome))
            .unwrap();
        let changed = self.db.list_todos().unwrap() != before;
        self.record(case, outcome, reply, finished, changed)
    }

    fn record(
        &self,
        case: &Case,
        outcome: &llm::ToolOutcome,
        reply: &str,
        finished: FinishedReply,
        changed: bool,
    ) -> Recorded {
        let confirmation = finished
            .tool_turn
            .is_some_and(|turn| turn.confirm == Confirm::Offered);
        if confirmation && case.expects_change() {
            self.db.confirm_tool_turn(finished.message.uuid).unwrap();
        }
        let history = self
            .db
            .tool_history(std::slice::from_ref(&finished.message))
            .unwrap();
        let calls = history
            .get(&finished.message.uuid)
            .map(|turn| turn.calls.clone())
            .unwrap_or_default();
        let listed = history
            .get(&finished.message.uuid)
            .map(|turn| {
                turn.calls
                    .iter()
                    .zip(&turn.responses)
                    .filter(|(call, _)| call.name == todo::LIST_TOOL)
                    .map(|(_, response)| shown(response))
                    .collect()
            })
            .unwrap_or_default();
        Recorded {
            id: case.id.clone(),
            raw_calls: outcome.calls.clone(),
            call_probability: outcome.call_probability,
            calls,
            unsure: confirmation,
            abstained: outcome.abstained,
            rejected_steps: outcome.rejected_steps,
            text: finished.message.text,
            reply: reply.to_owned(),
            state: StateResult {
                tasks: self
                    .db
                    .list_todos()
                    .unwrap()
                    .into_iter()
                    .map(|task| TaskState {
                        completed: !task.is_open(),
                        due_at: task.due_at_ms.map(|at| {
                            todo::timing::local_time(at, &chrono::Local)
                                .unwrap()
                                .format("%Y-%m-%d %H:%M")
                                .to_string()
                        }),
                        title: task.title,
                        aliases: Vec::new(),
                    })
                    .collect(),
                changed,
                confirmation,
                listed,
            },
        }
    }
}

#[derive(Default)]
struct Tally {
    route_ok: usize,
    calls_ok: usize,
    false_changes: usize,
    misses: usize,
    raw_calls_ok: usize,
    false_by_tool: std::collections::BTreeMap<&'static str, usize>,
    failures: Vec<Value>,
    probabilities: Vec<(Option<bool>, f32)>,
    state_ok: usize,
    state_ok_unconfirmed: usize,
    unsafe_state_changes: usize,
    state_failures: Vec<Value>,
    correct_changes: usize,
    unnecessary_confirmations: usize,
    offers: usize,
    wrong_offers: usize,
    applied_false_changes: usize,
    offered_false_changes: usize,
    forced_turns: usize,
    abstained_turns: usize,
    abstained_changes: usize,
}

impl Tally {
    fn add(
        &mut self,
        case: &Case,
        outcome: &llm::ToolOutcome,
        record: &Recorded,
        completion: &CompletionContext,
    ) -> bool {
        self.forced_turns += usize::from(record.rejected_steps > 0);
        self.abstained_turns += usize::from(record.abstained);
        self.abstained_changes +=
            usize::from(record.abstained && (record.unsure || record.state.changed));
        self.probabilities.push((
            (case.expect != "safe").then_some(case.expect == "tool"),
            outcome.call_probability.unwrap_or_default(),
        ));
        let called = !outcome.calls.is_empty();
        let scored = case.expect != "safe";
        let routed = scored && called == (case.expect == "tool");
        self.route_ok += usize::from(routed);
        let expected_changes = case.expects_change();
        if scored
            && outcome
                .calls
                .iter()
                .any(|call| CHANGES.contains(&call.name.as_str()))
            && !expected_changes
        {
            self.false_changes += 1;
        }
        if case.expect == "reply" {
            for name in [todo::SAVE_TOOL, todo::COMPLETE_TOOL, todo::LIST_TOOL] {
                if outcome.calls.iter().any(|call| call.name == name) {
                    *self.false_by_tool.entry(name).or_insert(0) += 1;
                }
            }
        }
        if case.expect == "tool" && !called {
            self.misses += 1;
        }
        self.unsafe_state_changes += usize::from(!expected_changes && record.state.changed);
        let state_matches = record.state.matches(case);
        if case.state.is_some() {
            if state_matches {
                self.state_ok += 1;
                self.state_ok_unconfirmed += usize::from(!(expected_changes && record.unsure));
            } else {
                self.state_failures
                    .push(json!({"id": case.id, "expected": case.state, "listed": case.listed, "confirmation": case.confirmation, "actual": record.state}));
            }
        }
        let refined = &record.calls;
        let matches = |calls: &[ToolCall]| {
            routed
                && calls_match_with_context(
                    &case.calls,
                    calls,
                    Some(completion.clone()),
                    &record.state.listed,
                )
        };
        self.raw_calls_ok += usize::from(matches(&outcome.calls));
        let matched = matches(refined);
        self.calls_ok += usize::from(matched);
        let right = matched && case.state.as_ref().is_none_or(|_| state_matches);
        self.correct_changes += usize::from(expected_changes && right);
        self.unnecessary_confirmations += usize::from(expected_changes && right && record.unsure);
        self.offers += usize::from(record.unsure);
        self.wrong_offers += usize::from(record.unsure && !(expected_changes && right));
        self.applied_false_changes +=
            usize::from(scored && !expected_changes && record.state.changed);
        self.offered_false_changes += usize::from(scored && !expected_changes && record.unsure);
        if scored && !matched {
            self.failures.push(json!({
                "id": case.id,
                "user": case.user,
                "expected": case.expect,
                "calls": refined,
                "raw_calls": outcome.calls,
                "reply": record.reply,
                "call_probability": outcome.call_probability,
            }));
        }
        matched
    }

    fn report(&self, cases: &[Case]) -> Value {
        let route_cases = cases.iter().filter(|case| case.expect != "safe").count();
        let state_cases = cases.iter().filter(|case| case.state.is_some()).count();
        let reply_cases = cases.iter().filter(|case| case.expect == "reply").count();
        let tool_cases = (route_cases - reply_cases).max(1) as f64;
        let reply_cases = reply_cases.max(1) as f64;
        let non_mutating = non_mutating_cases(cases);
        json!({
            "cases": cases.len(),
            "route_cases": route_cases,
            "route_accuracy": self.route_ok as f64 / route_cases.max(1) as f64,
            "call_accuracy": self.calls_ok as f64 / route_cases.max(1) as f64,
            "raw_call_accuracy": self.raw_calls_ok as f64 / route_cases.max(1) as f64,
            "state_cases": state_cases,
            "state_accuracy": self.state_ok as f64 / state_cases.max(1) as f64,
            "state_accuracy_unconfirmed": self.state_ok_unconfirmed as f64 / state_cases.max(1) as f64,
            "state_failures": self.state_failures,
            "unsafe_state_changes": self.unsafe_state_changes,
            "non_mutating_cases": non_mutating,
            "false_change_call_rate": self.false_changes as f64 / non_mutating.max(1) as f64,
            "false_change_applied_rate": self.applied_false_changes as f64 / non_mutating.max(1) as f64,
            "false_change_offered_rate": self.offered_false_changes as f64 / non_mutating.max(1) as f64,
            "unnecessary_confirmation_rate": self.unnecessary_confirmations as f64 / self.correct_changes.max(1) as f64,
            "wrong_offer_rate": self.wrong_offers as f64 / cases.len().max(1) as f64,
            "offers": self.offers,
            "wrong_offers": self.wrong_offers,
            "forced_turns": self.forced_turns,
            "abstained_turns": self.abstained_turns,
            "abstained_changes": self.abstained_changes,
            "false_call_rate_by_tool": self.false_by_tool
                .iter()
                .map(|(name, count)| ((*name).to_owned(), json!(*count as f64 / reply_cases)))
                .collect::<serde_json::Map<_, _>>(),
            "missed_tool_rate": self.misses as f64 / tool_cases,
            "call_probability": self.probabilities
                .iter()
                .map(|(tool, p)| json!({"expected_tool": tool, "p": p}))
                .collect::<Vec<Value>>(),
            "failures": self.failures,
        })
    }
}

#[test]
#[ignore = "requires ENSU_TEST_MODEL"]
fn todo_tool_calls_meet_accuracy_targets() {
    let context = support::model_context(4096);
    let path = std::env::var("ENSU_EVAL_CASES").unwrap_or_else(|_| {
        concat!(env!("CARGO_MANIFEST_DIR"), "/tests/data/todo_eval.jsonl").into()
    });
    let cases: Vec<Case> = std::fs::read_to_string(path)
        .unwrap()
        .lines()
        .filter(|line| !line.trim().is_empty())
        .map(|line| serde_json::from_str(line).unwrap_or_else(|err| panic!("{err}: {line}")))
        .collect();
    let system = support::system_prompt();
    let probability = std::env::var("ENSU_EVAL_CALL_PROBABILITY")
        .ok()
        .map(|value| value.parse::<f32>().unwrap());

    let mut tally = Tally::default();
    let (mut prompt_tokens, mut elapsed_ms) = (0_i64, 0_u128);
    let mut recorded = Vec::new();
    let mut guard_results = Vec::new();
    for case in &cases {
        let conversation = ConversationCase::new(case);
        let completion_context = conversation.completion_context();
        let before = conversation.db.list_todos().unwrap();
        let run = support::run_turn(
            &conversation.db,
            &context,
            &GroundingCache::default(),
            &conversation.snapshot,
            &system,
            160,
            |request| {
                if let Some(probability) = probability
                    && let Some(tools) = request.tools.as_mut()
                {
                    tools.min_call_probability = probability;
                }
            },
        );
        elapsed_ms += run.events.last().unwrap().0.as_millis();
        prompt_tokens += i64::from(run.summary.prompt_tokens.unwrap_or_default());
        let outcome = run.summary.tools.unwrap_or_default();
        let changed = conversation.db.list_todos().unwrap() != before;
        let record = conversation.record(case, &outcome, &run.reply, run.finished, changed);
        tally.add(case, &outcome, &record, &completion_context);
        if !case.probe.is_empty() {
            let probe = ConversationCase::new(case).finish(
                case,
                &llm::ToolOutcome {
                    calls: case.probe.clone(),
                    call_probability: Some(1.0),
                    ..Default::default()
                },
                "",
            );
            let state = probe.state;
            guard_results
                .push(json!({"id": case.id, "passed": state.matches(case), "actual": state}));
        }
        recorded.push(record);
    }
    let guard_ok = guard_results
        .iter()
        .filter(|result| result["passed"] == true)
        .count();
    let n = cases.len() as f64;
    let mut report = tally.report(&cases);
    report["model"] = json!(std::env::var("ENSU_TEST_MODEL").unwrap());
    report["mean_prompt_tokens"] = json!(prompt_tokens as f64 / n);
    report["mean_latency_ms"] = json!(elapsed_ms as f64 / n);
    report["guard_cases"] = json!(guard_results.len());
    report["guard_accuracy"] = json!(guard_ok as f64 / guard_results.len().max(1) as f64);
    report["guard_results"] = json!(guard_results);
    report["partial_prompt_reuse"] = json!(context.supports_partial_prompt_reuse());
    report["supports_tools"] = json!(context.supports_tools());
    let state_cases = cases.iter().filter(|case| case.state.is_some()).count();
    let state_ok = tally.state_ok;
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
        "route {:.3}  calls {:.3} (raw {:.3})  false change calls {:.3}  missed {:.3}  prompt {:.0} tok  latency {:.0} ms",
        report["route_accuracy"].as_f64().unwrap(),
        report["call_accuracy"].as_f64().unwrap(),
        report["raw_call_accuracy"].as_f64().unwrap(),
        report["false_change_call_rate"].as_f64().unwrap(),
        report["missed_tool_rate"].as_f64().unwrap(),
        report["mean_prompt_tokens"].as_f64().unwrap(),
        report["mean_latency_ms"].as_f64().unwrap(),
    );
    for failure in report["failures"].as_array().unwrap() {
        println!("FAIL {failure}");
    }
    for failure in &tally.state_failures {
        println!("STATE FAIL {failure}");
    }
    println!(
        "state {state_ok}/{state_cases}  guards {guard_ok}/{}",
        guard_results.len()
    );
    let mut failures = accuracy_failures(
        &report,
        threshold("ENSU_EVAL_MIN_ROUTE", MIN_ROUTE_ACCURACY),
        threshold("ENSU_EVAL_MIN_CALL", MIN_CALL_ACCURACY),
        threshold("ENSU_EVAL_MAX_FALSE_CHANGE", MAX_FALSE_CHANGE_RATE),
    );
    if tally.abstained_changes != 0 {
        failures.push(format!("abstained changes: {}", tally.abstained_changes));
    }
    if state_ok != state_cases {
        failures.push(format!("persisted state: {state_ok}/{state_cases}"));
    }
    if guard_ok != guard_results.len() {
        failures.push(format!(
            "execution guards: {guard_ok}/{}",
            guard_results.len()
        ));
    }
    assert!(
        failures.is_empty(),
        "To Do accuracy targets failed:\n{}",
        failures.join("\n")
    );
}

#[test]
fn accuracy_targets_reject_routing_argument_and_false_change_regressions() {
    let check = |route, calls, false_changes| {
        accuracy_failures(
            &json!({"route_accuracy": route, "call_accuracy": calls, "false_change_call_rate": false_changes}),
            MIN_ROUTE_ACCURACY,
            MIN_CALL_ACCURACY,
            MAX_FALSE_CHANGE_RATE,
        )
    };
    assert!(check(0.95, 0.90, 0.02).is_empty());
    for (route, calls, false_changes) in [(0.94, 1.0, 0.0), (1.0, 0.89, 0.0), (1.0, 1.0, 0.03)] {
        assert_eq!(check(route, calls, false_changes).len(), 1);
    }
    assert_eq!(check(0.863, 0.707, 0.205).len(), 3);

    let expected = |value| serde_json::from_value::<Vec<ExpectedCall>>(value).unwrap();
    let actual = |value| serde_json::from_value::<Vec<ToolCall>>(value).unwrap();
    let query = expected(json!([{"name":"list_to_dos","query":"bank"}]));
    assert!(calls_match(
        &query,
        &actual(json!([{"name":"list_to_dos","arguments":{"query":"bank"}}]))
    ));
    for arguments in [json!({}), json!({"query":"dentist"})] {
        assert!(!calls_match(
            &query,
            &actual(json!([{"name":"list_to_dos","arguments":arguments}]))
        ));
    }
    let saves = expected(json!([
        {"name":"save_to_do","title":["milk"]},
        {"name":"save_to_do","title":["bread"]}
    ]));
    let reversed = actual(json!([
        {"name":"save_to_do","arguments":{"title":"Buy bread"}},
        {"name":"save_to_do","arguments":{"title":"Buy milk"}}
    ]));
    assert!(calls_match(&saves, &reversed));
    assert!(!calls_match(&saves, &reversed[..1]));
    assert!(!calls_match(
        &saves,
        &[reversed[0].clone(), reversed[0].clone()]
    ));
    let dependent = expected(json!([{"name":"list_to_dos"},{"name":"complete_to_do","number":1}]));
    assert!(!calls_match(
        &dependent,
        &actual(json!([
            {"name":"complete_to_do","arguments":{"number":1}}, {"name":"list_to_dos"}
        ]))
    ));
    let completion_case: Case = serde_json::from_value(json!({
        "id":"completion-scoring", "user":"Finish #2 and #4", "expect":"tool",
        "calls":[{"name":"complete_to_do","number":2},{"name":"complete_to_do","number":4}],
        "initial":[
            {"title":"Feed cat","completed":false},
            {"title":"Post letter","completed":false},
            {"title":"Water plants","completed":false},
            {"title":"Book flights","completed":false}
        ],
        "history":[
            {"role":"user","content":"Show my tasks"},
            {"role":"assistant","content":"","tool_calls":[{"name":"list_to_dos","arguments":{"filter":"open"}}]}
        ]
    }))
    .unwrap();
    let context = ConversationCase::new(&completion_case).completion_context();
    let named = actual(json!([
        {"name":"complete_to_do","arguments":{"task":"Post letter"}},
        {"name":"complete_to_do","arguments":{"task":"Book flights"}}
    ]));
    assert!(calls_match_with_context(
        &completion_case.calls,
        &named,
        Some(context.clone()),
        &[]
    ));
    assert!(!calls_match(&completion_case.calls, &named));
    for arguments in [
        json!({"task":"Feed cat"}),
        json!({"task":"letter"}),
        json!({"number":4,"task":"Post letter"}),
        json!({"number":2,"task":"Book flights"}),
    ] {
        assert!(!calls_match_with_context(
            &completion_case.calls,
            &[
                actual(json!([{"name":"complete_to_do","arguments":arguments}]))[0].clone(),
                named[1].clone()
            ],
            Some(context.clone()),
            &[]
        ));
    }
    let mut ambiguous = context.clone();
    let mut duplicate = ambiguous
        .tasks
        .iter()
        .find(|task| task.title == "Post letter")
        .unwrap()
        .clone();
    duplicate.id = uuid::Uuid::from_u128(1000);
    ambiguous.tasks.push(duplicate);
    assert!(!calls_match_with_context(
        &completion_case.calls,
        &named,
        Some(ambiguous),
        &[]
    ));
    assert!(calls_match_with_context(
        &expected(json!([{"name":"complete_to_do","task":["letter"]}])),
        &actual(json!([{"name":"complete_to_do","arguments":{"number":2}}])),
        Some(context.clone()),
        &[]
    ));
    let listed = vec![vec!["Book flights".to_owned()]];
    assert!(calls_match_with_context(
        &dependent,
        &actual(json!([
            {"name":"list_to_dos"},
            {"name":"complete_to_do","arguments":{"task":"Book flights"}}
        ])),
        Some(context.clone()),
        &listed
    ));
    assert!(!calls_match_with_context(
        &dependent,
        &actual(json!([
            {"name":"list_to_dos"},
            {"name":"complete_to_do","arguments":{"task":"Feed cat"}}
        ])),
        Some(context),
        &listed
    ));
    let packing = expected(json!([{
        "name":"save_to_do","title":["pack", "trip"],"when":"the day after tomorrow"
    }]));
    assert!(calls_match(
        &packing,
        &actual(
            json!([{"name":"save_to_do","arguments":{"title":"Pack for the trip","when":"the day after tomorrow"}}])
        )
    ));
    for arguments in [
        json!({"title":"Pack for work","when":"the day after tomorrow"}),
        json!({"title":"Pack for the trip"}),
        json!({"title":"Pack for the trip","when":"tomorrow"}),
    ] {
        assert!(!calls_match(
            &packing,
            &actual(json!([{"name":"save_to_do","arguments":arguments}]))
        ));
    }

    let case: Case = serde_json::from_value(json!({
        "id":"scoring", "user":"List tasks", "expect":"tool", "calls":[{"name":"list_to_dos"}],
        "state":[{"title":"Call bank","completed":false,"due_at":"2026-11-13 10:00","aliases":["Call the bank"]},{"title":"Buy milk","completed":false}],
        "listed":[["Call bank","Buy milk"]], "confirmation":false
    }))
    .unwrap();
    let valid = || {
        serde_json::from_value::<StateResult>(json!({
            "tasks":[{"title":"Call the bank","completed":false,"due_at":"2026-11-13 10:00"},{"title":"Buy milk","completed":false}],
            "changed":false,"confirmation":false,"listed":[["Call bank","Buy milk"]]
        }))
        .unwrap()
    };
    assert!(valid().matches(&case));
    let a: TaskState =
        serde_json::from_value(json!({"title":"Read a book","completed":false})).unwrap();
    let b: TaskState =
        serde_json::from_value(json!({"title":"Read the book","completed":false})).unwrap();
    assert!(!a.matches(&b));
    for due in [None, Some("2026-11-14 10:00".to_owned())] {
        let mut result = valid();
        result.tasks[0].due_at = due;
        assert!(!result.matches(&case));
    }
    for listed in [
        vec!["Buy milk", "Call bank"],
        vec!["Call bank"],
        vec!["Call bank", "Buy milk", "Other"],
    ] {
        let mut result = valid();
        result.listed = vec![listed.into_iter().map(str::to_owned).collect()];
        assert!(!result.matches(&case));
    }
    let mut result = valid();
    result.confirmation = true;
    assert!(!result.matches(&case));
    let mut result = valid();
    result.changed = true;
    assert!(!result.matches(&case));
    let reply: Case =
        serde_json::from_value(json!({"id":"reply","user":"Hello","expect":"reply"})).unwrap();
    let record = ConversationCase::new(&reply).finish(
        &reply,
        &llm::ToolOutcome::default(),
        "Hello! How can I help?",
    );
    assert_eq!(record.reply, "Hello! How can I help?");
    assert_eq!(record.text, record.reply);
    let denominator = non_mutating_cases(&[case, reply]) as f64;
    assert_eq!(1.0 / denominator, 0.5);
    assert_eq!(2.0 / denominator, 1.0);
}

#[test]
fn offers_and_applied_changes_are_tallied_apart() {
    let change: Case = serde_json::from_value(json!({
        "id": "correct_offer",
        "user": "Add Buy milk to my to-do list",
        "expect": "tool",
        "calls": [{"name": "save_to_do", "title": ["buy milk"]}],
        "initial": [],
        "state": [{"title": "Buy milk", "completed": false}]
    }))
    .unwrap();
    let reply: Case = serde_json::from_value(json!({
        "id": "false_change",
        "user": "Add Buy milk to my to-do list",
        "expect": "reply",
        "initial": []
    }))
    .unwrap();
    let mut tally = Tally::default();
    for (case, probability) in [(&change, 0.6), (&reply, 0.6), (&reply, 1.0)] {
        let conversation = ConversationCase::new(case);
        let completion = conversation.completion_context();
        let outcome = llm::ToolOutcome {
            calls: serde_json::from_value(json!([
                {"name": "save_to_do", "arguments": {"title": "Buy milk"}}
            ]))
            .unwrap(),
            call_probability: Some(probability),
            ..Default::default()
        };
        let record = conversation.finish(case, &outcome, "");
        assert_eq!(
            tally.add(case, &outcome, &record, &completion),
            case.expects_change()
        );
    }
    assert_eq!(tally.state_ok, 1);
    assert_eq!(tally.state_ok_unconfirmed, 0);
    assert_eq!(tally.correct_changes, 1);
    assert_eq!(tally.unnecessary_confirmations, 1);
    assert_eq!(tally.offers, 2);
    assert_eq!(tally.wrong_offers, 1);
    assert_eq!(tally.applied_false_changes, 1);
    assert_eq!(tally.offered_false_changes, 1);
}

#[test]
fn labelled_cases_parse_and_their_deadlines_resolve() {
    let cases: Vec<Case> = [
        include_str!("data/todo_eval.jsonl"),
        include_str!("data/todo_eval_holdout.jsonl"),
    ]
    .into_iter()
    .flat_map(|data| {
        let cases: Vec<Case> = data
            .lines()
            .filter(|line| !line.trim().is_empty())
            .map(|line| serde_json::from_str(line).unwrap())
            .collect();
        assert_eq!(cases.len(), 50);
        cases
    })
    .collect();
    let mut ids = std::collections::BTreeSet::new();
    for case in &cases {
        assert!(ids.insert(case.id.as_str()), "duplicate {}", case.id);
        assert!(
            matches!(case.expect.as_str(), "tool" | "reply" | "safe"),
            "{}",
            case.id
        );
        assert_eq!(case.expect == "tool", !case.calls.is_empty(), "{}", case.id);
        if case.expects_change() {
            assert!(case.confirmation.is_none(), "{}", case.id);
        }
        if case.listed.is_some() || case.confirmation.is_some() {
            assert!(case.state.is_some(), "{}", case.id);
        }
        if case.expect == "safe" {
            assert!(
                case.state.is_some() && !case.probe.is_empty(),
                "{}",
                case.id
            );
        }
        if !case.probe.is_empty() {
            let record = ConversationCase::new(case).finish(
                case,
                &llm::ToolOutcome {
                    calls: case.probe.clone(),
                    call_probability: Some(1.0),
                    ..Default::default()
                },
                "",
            );
            assert!(record.state.matches(case), "{}", case.id);
        }
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
                    case.state.is_some() || todo::timing::parse_deadline(when, now()).is_some(),
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
    let mut replayed = std::collections::BTreeSet::new();
    let mut tally = Tally::default();
    for line in include_str!("data/todo_replay.jsonl")
        .lines()
        .filter(|line| !line.trim().is_empty())
    {
        let record: Recorded = serde_json::from_str(line).unwrap();
        assert!(
            replayed.insert(record.id.clone()),
            "duplicate replay {}",
            record.id
        );
        let case = &cases[&record.id];
        let conversation = ConversationCase::new(case);
        let completion = conversation.completion_context();
        let outcome = llm::ToolOutcome {
            calls: record.raw_calls.clone(),
            call_probability: record.call_probability,
            ..Default::default()
        };
        let result = conversation.finish(case, &outcome, &record.reply);
        tally.add(case, &outcome, &result, &completion);
        assert_eq!(
            (result.calls, result.unsure, result.text, result.state),
            (record.calls, record.unsure, record.text, record.state),
            "{}: {}",
            record.id,
            case.user
        );
    }
    assert_eq!(replayed, cases.keys().cloned().collect());
    assert_eq!(tally.offers, 2);
    assert_eq!(tally.applied_false_changes, 0);
    assert_eq!(tally.offered_false_changes, 0);
    assert_eq!(tally.unnecessary_confirmations, 1);
    assert_eq!(tally.wrong_offers, 1);
}
