//! A personal To Do list the chat model can manage through native tool calls.
//!
//! Storage lives in [`crate::db::ChatDb`]. This module defines the domain
//! types, the tools offered to the model, and the pure rules for interpreting
//! calls: deadline parsing, task matching and receipt text.

mod matching;
pub mod timing;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::llm::{ParameterKind, ToolChoice, ToolParameter, ToolRequest, ToolSpec};

pub(crate) use matching::find_tasks;

/// Most tasks a list reply numbers.
pub const LIST_LIMIT: usize = 20;
/// Longest stored title, in characters.
pub const MAX_TITLE_CHARS: usize = 200;
/// Default first-token probability needed before the model may call a tool.
pub const DEFAULT_CALL_PROBABILITY: f32 = 0.5;

pub const SAVE_TOOL: &str = "save_to_do";
pub const LIST_TOOL: &str = "list_to_dos";
pub const COMPLETE_TOOL: &str = "complete_to_do";

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

/// The To Do tools for one chat turn. Quoted arguments must come from
/// `user_text`, the current user message.
pub fn chat_tools(user_text: &str) -> ToolRequest {
    ToolRequest {
        tools: vec![
            ToolSpec {
                name: SAVE_TOOL.into(),
                description: "Add a task to the user's To Do list when the user states something they need or want to do, or asks to be reminded. Call once per task.".into(),
                parameters: vec![
                    parameter(
                        "title",
                        "Short task title in the user's words, without the deadline.",
                        ParameterKind::Text,
                        true,
                    ),
                    parameter(
                        "when",
                        "The deadline copied exactly from the user's message, including both day and time. Omit when the user gave none.",
                        ParameterKind::Quote,
                        false,
                    ),
                ],
            },
            ToolSpec {
                name: LIST_TOOL.into(),
                description: "Show tasks from the user's To Do list.".into(),
                parameters: vec![
                    parameter(
                        "filter",
                        "Which tasks to show.",
                        ParameterKind::Choice {
                            values: ListFilter::NAMES.iter().map(|name| (*name).to_owned()).collect(),
                        },
                        true,
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
                description: "Mark a task in the user's To Do list as done. Name the task, or give its number from the list just shown.".into(),
                parameters: vec![
                    parameter(
                        "task",
                        "Words naming the task, copied from the user's message.",
                        ParameterKind::Quote,
                        false,
                    ),
                    parameter(
                        "number",
                        "The task's number in the list just shown.",
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
    }
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
            let request = chat_tools(text);
            assert!(request.tools.iter().any(|tool| tool.name == SAVE_TOOL));
            assert_eq!(request.quote_source, text);
        }
    }
}
