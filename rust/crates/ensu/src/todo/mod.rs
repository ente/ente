//! A personal To Do list the chat model can manage through native tool calls.
//!
//! Storage lives in [`crate::db::ChatDb`]. This module defines the domain
//! types, the tools offered to the model, and the pure rules for interpreting
//! calls: deadline parsing, task matching and receipt text.

mod matching;
mod refine;
pub mod timing;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::llm::{
    ParameterKind, ToolCall, ToolChoice, ToolExample, ToolParameter, ToolRequest, ToolSpec,
    ToolValue,
};

pub(crate) use matching::find_tasks;
pub use refine::refine_calls;

/// Most tasks a list reply numbers.
pub const LIST_LIMIT: usize = 20;
/// Longest stored title, in characters.
pub const MAX_TITLE_CHARS: usize = 200;
/// Default first-token probability needed before the model may call a tool.
pub const DEFAULT_CALL_PROBABILITY: f32 = 0.5;

pub const SAVE_TOOL: &str = "save_to_do";
pub const LIST_TOOL: &str = "list_to_dos";
pub const COMPLETE_TOOL: &str = "complete_to_do";

/// Confidence in a tool call, the first-token probability of the call, at
/// which a change to the list applies directly. Below it, down to
/// [`DEFAULT_CALL_PROBABILITY`], saves and completions are offered for the
/// user to confirm. One rule for every model: a model that is unsure, or
/// that tells tasks from chat less well, lands in the confirm band on its own
/// (measured with `tests/todo_eval.rs`).
pub const DIRECT_CALL_PROBABILITY: f32 = 0.9;

/// Whether a turn's changes apply directly or wait for confirmation, given
/// the model's confidence in its calls. Without a confidence, they wait.
pub fn confirm_changes(call_probability: Option<f32>) -> bool {
    call_probability.is_none_or(|p| p < DIRECT_CALL_PROBABILITY)
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Todo {
    pub id: Uuid,
    pub title: String,
    pub due_at_ms: Option<i64>,
    pub completed_at_ms: Option<i64>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
    pub version: u64,
}

impl Todo {
    pub fn is_open(&self) -> bool {
        self.completed_at_ms.is_none()
    }
}

/// One task's state before and after a change. `None` means the task did
/// not exist.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TodoChange {
    pub before: Option<Todo>,
    pub after: Option<Todo>,
}

/// A scheduled reminder for an open task with a future deadline. Platforms
/// keep the OS schedule equal to the latest set of alarms, comparing `key`s.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TodoAlarm {
    pub todo_id: Uuid,
    pub title: String,
    pub due_at_ms: i64,
    /// Changes whenever the alarm's time or text changes.
    pub key: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ListFilter {
    Open,
    Completed,
    Overdue,
    Today,
    All,
}

impl ListFilter {
    pub const NAMES: [&'static str; 5] = ["open", "completed", "overdue", "today", "all"];

    pub fn from_name(name: &str) -> Option<Self> {
        Some(match name {
            "open" => Self::Open,
            "completed" => Self::Completed,
            "overdue" => Self::Overdue,
            "today" => Self::Today,
            "all" => Self::All,
            _ => return None,
        })
    }
}

fn parameter(name: &str, description: &str, kind: ParameterKind, required: bool) -> ToolParameter {
    ToolParameter {
        name: name.into(),
        description: description.into(),
        kind,
        required,
    }
}

/// Longest open-task title shown to the model, in characters.
const PROMPT_TITLE_CHARS: usize = 60;

/// How the open tasks read in the complete tool's description, so the model
/// knows what it can mark as done.
fn open_tasks_text(open_titles: &[&str]) -> String {
    if open_titles.is_empty() {
        return "The list has no open tasks.".into();
    }
    let titles: Vec<String> = open_titles
        .iter()
        .take(LIST_LIMIT)
        .map(|title| {
            let short: String = title.chars().take(PROMPT_TITLE_CHARS).collect();
            format!("“{short}”")
        })
        .collect();
    format!("Open tasks: {}.", titles.join(", "))
}

/// The To Do tools for one chat turn. Quoted arguments must come from
/// `user_text`, the current user message. `open_titles` are the open tasks,
/// in list order; the first [`LIST_LIMIT`] are shown to the model.
pub fn chat_tools(user_text: &str, open_titles: &[&str]) -> ToolRequest {
    ToolRequest {
        tools: vec![
            ToolSpec {
                name: SAVE_TOOL.into(),
                description: "Add a task the user themself needs or wants to do: when they ask to be reminded or to add something, or state a plan or need of their own (\"I need to…\", \"I want to…\", \"Book…\"). Not for what other people need to do, what is already done, or questions. Make one call per task: when the user names several tasks, joined by \"and\", commas or separate lines, call once for each.".into(),
                parameters: vec![
                    parameter(
                        "title",
                        "Short title for this one task, in the user's words, without the deadline.",
                        ParameterKind::Text,
                        true,
                    ),
                    parameter(
                        "when",
                        "This task's deadline copied exactly from the user's message, keeping every word of the day and time (\"at 3\", \"5 PM today\", \"noon on Friday\"). Omit when the user gave none.",
                        ParameterKind::Quote,
                        false,
                    ),
                ],
            },
            ToolSpec {
                name: LIST_TOOL.into(),
                description: "Show tasks from the user's To Do list, when they ask what is on it or what they have to do.".into(),
                parameters: vec![
                    parameter(
                        "filter",
                        "Which tasks to show. Omit to show open tasks.",
                        ParameterKind::Choice {
                            values: ListFilter::NAMES.iter().map(|name| (*name).to_owned()).collect(),
                        },
                        false,
                    ),
                    parameter(
                        "query",
                        "Words from task titles to search for, copied from the user. Omit to show every task in the filter.",
                        ParameterKind::Quote,
                        false,
                    ),
                ],
            },
            ToolSpec {
                name: COMPLETE_TOOL.into(),
                description: format!(
                    "Mark a task in the user's To Do list as done: when the user asks to mark, tick or check it off, or says they have just done it (\"finished the…\", \"called…\", \"picked up…\"). Name the task, or give its number from the list just shown. {}",
                    open_tasks_text(open_titles),
                ),
                parameters: vec![
                    parameter(
                        "task",
                        "Words naming the task, copied from the user's message.",
                        ParameterKind::Quote,
                        false,
                    ),
                    parameter(
                        "number",
                        "The task's position in the list just shown, when the user refers to it by position (\"the third one\" is 3).",
                        ParameterKind::Integer {
                            max: LIST_LIMIT as u32,
                        },
                        false,
                    ),
                ],
            },
        ],
        choice: ToolChoice::Auto,
        quote_source: user_text.to_owned(),
        max_calls: crate::llm::MAX_TOOL_CALLS,
        min_call_probability: DEFAULT_CALL_PROBABILITY,
        examples: examples(),
    }
}

/// Exchanges for models that need examples to tell when a tool fits. Kept
/// unlike any case in `tests/data`, so the eval still measures new wording.
fn examples() -> Vec<ToolExample> {
    let call = |name: &str, args: &[(&str, &str)]| ToolCall {
        name: name.into(),
        arguments: args
            .iter()
            .map(|(key, value)| ((*key).to_owned(), ToolValue::Text((*value).to_owned())))
            .collect(),
    };
    let calls = |user: &str, calls: Vec<ToolCall>| ToolExample {
        user: user.into(),
        calls,
        reply: String::new(),
    };
    let reply = |user: &str, reply: &str| ToolExample {
        user: user.into(),
        calls: Vec::new(),
        reply: reply.into(),
    };
    vec![
        calls(
            "Remind me to phone Uncle Raj at 6 PM",
            vec![call(
                SAVE_TOOL,
                &[("title", "Phone Uncle Raj"), ("when", "at 6 PM")],
            )],
        ),
        calls(
            "I gotta replace the bike chain",
            vec![call(SAVE_TOOL, &[("title", "Replace the bike chain")])],
        ),
        calls("Anything left on my list?", vec![call(LIST_TOOL, &[])]),
        calls(
            "Renewed the TV licence today",
            vec![call(COMPLETE_TOOL, &[("task", "TV licence")])],
        ),
        reply(
            "My flatmate needs to pay the water bill",
            "That's on them, so I haven't added it to your list.",
        ),
        reply("How far is the Moon?", "About **384,000 km** from Earth."),
    ]
}

/// A title as stored: one trimmed line, first letter capitalised.
pub(crate) fn clean_title(raw: &str) -> Option<String> {
    let line: String = raw.split_whitespace().collect::<Vec<_>>().join(" ");
    let line = line
        .trim_matches(|c: char| c == '"' || c == '“' || c == '”' || c == '.' || c.is_whitespace());
    if line.is_empty() {
        return None;
    }
    let mut chars = line.chars();
    let first = chars.next()?;
    let title: String = first
        .to_uppercase()
        .chain(chars)
        .take(MAX_TITLE_CHARS)
        .collect();
    Some(title)
}

/// A deadline for chat receipts and lists, in local time.
pub(crate) fn describe_due(due_at_ms: i64) -> String {
    timing::local_time(due_at_ms)
        .map(|at| at.format("%a %-d %b %Y, %H:%M").to_string())
        .unwrap_or_else(|| "an unknown time".into())
}

pub(crate) fn list_line(number: usize, todo: &Todo) -> String {
    let due = todo.due_at_ms.map_or_else(
        || "no due date".to_owned(),
        |due| format!("due {}", describe_due(due)),
    );
    let done = if todo.is_open() { "" } else { ", done" };
    format!("{number}. {} — {due}{done}", todo.title)
}

/// Tasks matching a list request, in display order: open before done,
/// earlier deadlines first, then oldest first.
pub(crate) fn select_tasks<'a>(
    todos: &'a [Todo],
    filter: ListFilter,
    query: Option<&str>,
    now_ms: i64,
) -> Vec<&'a Todo> {
    let today = timing::local_time(now_ms).map(|now| now.date());
    let mut selected: Vec<_> = todos
        .iter()
        .filter(|todo| match filter {
            ListFilter::Open => todo.is_open(),
            ListFilter::Completed => !todo.is_open(),
            ListFilter::Overdue => todo.is_open() && todo.due_at_ms.is_some_and(|due| due < now_ms),
            ListFilter::Today => {
                todo.is_open()
                    && todo
                        .due_at_ms
                        .and_then(timing::local_time)
                        .is_some_and(|due| Some(due.date()) == today)
            }
            ListFilter::All => true,
        })
        .collect();
    if let Some(query) = query {
        let matched = find_tasks(
            &selected.iter().copied().cloned().collect::<Vec<_>>(),
            query,
        )
        .into_iter()
        .map(|todo| todo.id)
        .collect::<Vec<_>>();
        selected.retain(|todo| matched.contains(&todo.id));
    }
    // Stable, so equal keys keep the stored creation order.
    selected.sort_by_key(|todo| (!todo.is_open(), todo.due_at_ms.unwrap_or(i64::MAX)));
    selected
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn titles_are_single_trimmed_capitalised_lines() {
        assert_eq!(clean_title("  call   mom\n").as_deref(), Some("Call mom"));
        assert_eq!(clean_title("“buy milk.”").as_deref(), Some("Buy milk"));
        assert_eq!(clean_title(" . "), None);
        assert_eq!(
            clean_title(&"x".repeat(500)).unwrap().chars().count(),
            MAX_TITLE_CHARS
        );
    }

    #[test]
    fn chat_tools_are_valid_for_any_user_text() {
        for text in ["Buy milk tomorrow", "", "明日牛乳を買う"] {
            let request = chat_tools(text, &[]);
            assert!(request.tools.iter().any(|tool| tool.name == SAVE_TOOL));
            assert_eq!(request.quote_source, text);
        }
    }

    #[test]
    fn open_tasks_are_named_for_the_complete_tool() {
        let complete = |titles: &[&str]| {
            chat_tools("done", titles)
                .tools
                .into_iter()
                .find(|tool| tool.name == COMPLETE_TOOL)
                .unwrap()
                .description
        };
        assert!(complete(&[]).ends_with("The list has no open tasks."));
        assert!(
            complete(&["Buy milk", "Call Ana"]).ends_with("Open tasks: “Buy milk”, “Call Ana”.")
        );
        let many: Vec<String> = (0..30).map(|i| format!("Task {i}")).collect();
        let many: Vec<&str> = many.iter().map(String::as_str).collect();
        let description = complete(&many);
        assert!(description.contains("“Task 19”") && !description.contains("“Task 20”"));
        let long = "x".repeat(500);
        assert!(complete(&[&long]).contains(&format!("“{}”", "x".repeat(PROMPT_TITLE_CHARS))));
    }
}
