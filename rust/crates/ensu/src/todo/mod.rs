pub(crate) mod follow_up;
mod intent;
mod matching;
mod phrase;
mod plan;
mod refine;
pub mod timing;
pub(crate) mod tool;
mod wording;

use chrono::TimeZone;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::db::models::{Message, Sender};
use crate::llm::{
    ParameterKind, ToolCall, ToolExample, ToolParameter, ToolRequest, ToolSpec, ToolValue,
};

use matching::asks_again;
pub(crate) use matching::{choice_label, find_tasks};
pub use plan::{Outcome, Plan, SavedDeadline, plan};

pub const LIST_LIMIT: usize = 20;
pub const MAX_TITLE_CHARS: usize = 200;
pub const DEFAULT_CALL_PROBABILITY: f32 = 0.5;

pub const SAVE_TOOL: &str = "save_to_do";
pub const LIST_TOOL: &str = "list_to_dos";
pub const COMPLETE_TOOL: &str = "complete_to_do";

pub(crate) const DIRECT_CALL_PROBABILITY: f32 = 0.9;

pub fn request_text<'a, E>(
    messages: &'a [Message],
    user_text: &'a str,
    mut is_tool_reply: impl FnMut(&Message) -> Result<bool, E>,
) -> Result<&'a str, E> {
    let mut text = user_text;
    let mut rest = messages;
    while let [.., earlier, reply, _] = rest {
        if !asks_again(text) || earlier.sender != Sender::SelfUser || !is_tool_reply(reply)? {
            break;
        }
        text = &earlier.text;
        rest = &rest[..rest.len() - 2];
    }
    Ok(text)
}

pub(crate) fn needs_backing(call_probability: Option<f32>) -> bool {
    call_probability.is_none_or(|p| p < DIRECT_CALL_PROBABILITY)
}

#[cfg(test)]
fn confirm_calls(
    calls: &[ToolCall],
    user_text: &str,
    shown: usize,
    call_probability: Option<f32>,
) -> bool {
    needs_backing(call_probability)
        || calls.iter().any(|call| {
            call.name == COMPLETE_TOOL
                && refine::complete(call.text("task"), call.integer("number"), user_text, shown)
                    .unsure()
        })
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

    pub(crate) fn new(id: Uuid, title: String, due_at_ms: Option<i64>, now_ms: i64) -> Self {
        Self {
            id,
            title,
            due_at_ms,
            completed_at_ms: None,
            created_at_ms: now_ms,
            updated_at_ms: now_ms,
            version: 1,
        }
    }

    pub(crate) fn changed(&self, now_ms: i64, change: impl FnOnce(&mut Todo)) -> Todo {
        let mut after = self.clone();
        change(&mut after);
        after.version = self.version + 1;
        after.updated_at_ms = now_ms;
        after
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TodoChange {
    pub before: Option<Todo>,
    pub after: Option<Todo>,
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
    const NAMED: [(&'static str, Self); 5] = [
        ("open", Self::Open),
        ("completed", Self::Completed),
        ("overdue", Self::Overdue),
        ("today", Self::Today),
        ("all", Self::All),
    ];

    pub fn name(self) -> &'static str {
        Self::NAMED
            .iter()
            .find(|(_, filter)| *filter == self)
            .map_or("open", |(name, _)| name)
    }

    pub fn from_name(name: &str) -> Option<Self> {
        Self::NAMED
            .iter()
            .find(|(named, _)| *named == name)
            .map(|(_, filter)| *filter)
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

fn task_choices(user_text: &str, open_titles: &[&str]) -> Vec<String> {
    let mut seen = std::collections::HashSet::new();
    let labels: Vec<_> = open_titles
        .iter()
        .filter_map(|title| choice_label(title))
        .filter(|label| seen.insert(label.clone()))
        .collect();
    if labels.len() <= LIST_LIMIT {
        return labels;
    }
    let mut ranked: Vec<_> = labels.into_iter().enumerate().collect();
    ranked.sort_by_cached_key(|(_, label)| {
        if matching::spells_out(label, user_text) {
            0
        } else if refine::names_task(label, user_text) {
            1
        } else {
            2
        }
    });
    ranked.truncate(LIST_LIMIT);
    ranked.sort_unstable_by_key(|(index, _)| *index);
    ranked.into_iter().map(|(_, label)| label).collect()
}

pub fn chat_tools(user_text: &str, open_titles: &[&str]) -> ToolRequest {
    let choices = task_choices(user_text, open_titles);
    let task_kind = if choices.is_empty() {
        ParameterKind::Quote
    } else {
        ParameterKind::Choice { values: choices }
    };
    ToolRequest {
        allowed: None,
        tools: vec![
            ToolSpec {
                name: SAVE_TOOL.into(),
                description: "Add a task the user themself needs or wants to do: when they ask to be reminded or to add something, or state a plan or need of their own (\"I need to…\", \"I want to…\", \"Book…\"). Not for what other people need to do, what is already done, questions, or editing existing tasks. Make one call per task: when the user names several tasks, joined by \"and\", commas or separate lines, call once for each.".into(),
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
                        "open: unfinished; completed: done; overdue: unfinished and past due; today: unfinished due today; all: unfinished and done. Omit for open.",
                        ParameterKind::Choice {
                            values: ListFilter::NAMED.iter().map(|(name, _)| (*name).to_owned()).collect(),
                        },
                        false,
                    ),
                    parameter(
                        "query",
                        "Title words to search for, copied from the user. Omit generic list words, filters, and positions; omit entirely to show all tasks in the filter.",
                        ParameterKind::Quote,
                        false,
                    ),
                ],
            },
            ToolSpec {
                name: COMPLETE_TOOL.into(),
                description:                     "Mark a task in the user's To Do list as done: when the user asks to mark, tick or check it off, or says they have just done it (\"finished the…\", \"called…\", \"picked up…\"). Name the task, or give its number from the list just shown. Call once per requested completion.".into(),
                parameters: vec![
                    parameter("task", "The open task the user means.", task_kind, false),
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
        quote_source: user_text.to_owned(),
        max_calls: crate::llm::MAX_TOOL_CALLS,
        min_call_probability: DEFAULT_CALL_PROBABILITY,
        examples: examples(),
    }
}

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
            "I gotta replace the bike chain and wash my helmet",
            vec![
                call(SAVE_TOOL, &[("title", "Replace the bike chain")]),
                call(SAVE_TOOL, &[("title", "Wash my helmet")]),
            ],
        ),
        calls("Anything left on my list?", vec![call(LIST_TOOL, &[])]),
        calls(
            "Which car tasks are overdue?",
            vec![call(LIST_TOOL, &[("filter", "overdue"), ("query", "car")])],
        ),
        calls(
            "Renewed the TV licence today",
            vec![call(COMPLETE_TOOL, &[("task", "Renew the TV licence")])],
        ),
        reply(
            "My flatmate needs to pay the water bill",
            "That's on them, so I haven't added it to your list.",
        ),
        reply("How far is the Moon?", "About **384,000 km** from Earth."),
    ]
}

pub(crate) fn clean_title(raw: &str) -> Option<String> {
    let line: String = raw.split_whitespace().collect::<Vec<_>>().join(" ");
    let quote = |c: char| c == '"' || c == '“' || c == '”' || c.is_whitespace();
    let line = line
        .trim_start_matches(quote)
        .trim_end_matches(|c: char| quote(c) || c == '.');
    if line.is_empty() {
        return None;
    }
    let mut chars = line.chars();
    let first = chars.next()?;
    Some(first.to_uppercase().chain(chars).collect())
}

pub(crate) fn select_tasks<'a>(
    todos: &'a [Todo],
    filter: ListFilter,
    query: Option<&str>,
    now_ms: i64,
    zone: &impl TimeZone,
) -> Vec<&'a Todo> {
    let today = timing::local_time(now_ms, zone).map(|now| now.date());
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
                        .and_then(|due| timing::local_time(due, zone))
                        .is_some_and(|due| Some(due.date()) == today)
            }
            ListFilter::All => true,
        })
        .collect();
    if let Some(query) = query.filter(|query| matching::has_search_words(query)) {
        selected = find_tasks(&selected, query);
    }
    selected.sort_by(|a, b| display_order(a, b));
    selected
}

fn display_order(a: &Todo, b: &Todo) -> std::cmp::Ordering {
    let key = |todo: &Todo| match todo.completed_at_ms {
        None => (
            false,
            todo.due_at_ms.unwrap_or(i64::MAX),
            todo.created_at_ms,
        ),
        Some(done) => (true, -done, todo.created_at_ms),
    };
    key(a).cmp(&key(b))
}

pub fn sort_for_display(todos: &mut [Todo]) {
    todos.sort_by(display_order);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn open_tasks_are_the_complete_tools_choices() {
        let task = |titles: &[&str]| {
            chat_tools("done", titles)
                .tools
                .into_iter()
                .find(|tool| tool.name == COMPLETE_TOOL)
                .unwrap()
                .parameters
                .into_iter()
                .find(|parameter| parameter.name == "task")
                .unwrap()
                .kind
        };
        assert_eq!(task(&[]), ParameterKind::Quote);
        assert_eq!(
            task(&["Buy milk", "Call Ana", "Buy milk"]),
            ParameterKind::Choice {
                values: vec!["Buy milk".into(), "Call Ana".into()]
            }
        );
        let many: Vec<String> = (0..30).map(|i| format!("Task {i}")).collect();
        let many: Vec<&str> = many.iter().map(String::as_str).collect();
        let ParameterKind::Choice { values } = task(&many) else {
            panic!("expected choices");
        };
        assert_eq!(values.len(), LIST_LIMIT);
        assert_eq!(values.last().unwrap(), "Task 19");
        let mut many = many;
        many.push("Renew passport");
        let task_kind = |user: &str, titles: &[&str]| {
            chat_tools(user, titles)
                .tools
                .remove(2)
                .parameters
                .remove(0)
                .kind
        };
        let ParameterKind::Choice { values } = task_kind("Renew passport is done", &many) else {
            panic!("expected choices");
        };
        assert_eq!(values.last().unwrap(), "Renew passport");
        assert_eq!(values[..LIST_LIMIT - 1], many[..LIST_LIMIT - 1]);
        let clients: Vec<String> = (1..=21).map(|i| format!("Call client {i}")).collect();
        let clients: Vec<&str> = clients.iter().map(String::as_str).collect();
        let ParameterKind::Choice { values } = task_kind("I called client 21", &clients) else {
            panic!("expected choices");
        };
        assert_eq!(values.last().unwrap(), "Call client 21");
        assert_eq!(values[..LIST_LIMIT - 1], clients[..LIST_LIMIT - 1]);
    }

    #[test]
    fn changes_the_message_does_not_back_wait_for_confirmation() {
        let item = |number: i64| ToolCall {
            name: COMPLETE_TOOL.into(),
            arguments: [("number".to_owned(), ToolValue::Integer(number))].into(),
        };
        let sure = Some(0.99);
        for (number, user, confirm) in [
            (2, "The second one is done", false),
            (3, "Tick off the third", false),
            (4, "Finished the last one", false),
            (3, "Please tick off 3", false),
            (2, "mark 2 as complete", false),
            (3, "Done with 3", false),
            (3, "Called 3 people", true),
            (3, "Booked a table for 3", true),
            (1, "I finished the first draft", true),
            (3, "Finished chapter 3", true),
            (3, "Finished chapter 3 already", true),
            (3, "Finished chapter #3", true),
            (3, "Finished version 3", true),
            (4, "Finished the last chapter", true),
            (3, "Chapter number 3 is done", true),
            (3, "#3 is done", false),
            (3, "Finished item #3", false),
            (3, "Finished item 3", false),
            (2, "The second is done", false),
            (9, "ok thanks", false),
            (1, "ok thanks", true),
            (1, "Can you try again?", true),
            (2, "Tick off the third", true),
            (3, "Booked a table for the 3rd", true),
        ] {
            assert_eq!(
                confirm_calls(&[item(number)], user, 4, sure),
                confirm,
                "{user}"
            );
        }
        assert!(!confirm_calls(&[item(1)], "ok thanks", 0, sure));
        assert!(!confirm_calls(
            &[item(2), item(3)],
            "The second and third ones are done",
            4,
            sure
        ));
        assert!(confirm_calls(
            &[item(1), item(2)],
            "Mark number 1 done",
            4,
            sure
        ));
        let pick = ToolCall {
            name: COMPLETE_TOOL.into(),
            arguments: [(
                "task".to_owned(),
                ToolValue::Text("Review chapter 3".into()),
            )]
            .into(),
        };
        assert!(confirm_calls(
            std::slice::from_ref(&pick),
            "Tick off 3",
            4,
            sure
        ));
        assert!(!confirm_calls(&[pick], "Reviewed chapter 3", 4, sure));
        let other = ToolCall {
            name: COMPLETE_TOOL.into(),
            arguments: [("task".to_owned(), ToolValue::Text("Call client 2".into()))].into(),
        };
        assert!(confirm_calls(&[other], "I called client 21", 0, sure));
        let complete = |task: &str| ToolCall {
            name: COMPLETE_TOOL.into(),
            arguments: [("task".to_owned(), ToolValue::Text(task.into()))].into(),
        };
        for (task, user, probability, confirm) in [
            (
                "Call Vidhi about Aadhar",
                "I have talked to Vidhi for her Aadhar",
                sure,
                false,
            ),
            ("Call Vidhi about Aadhar", "Can you try again?", sure, true),
            ("Buy milk", "I bought the milk", Some(0.6), true),
        ] {
            assert_eq!(
                confirm_calls(&[complete(task)], user, 0, probability),
                confirm,
                "{user}"
            );
        }
    }
}

pub(crate) fn typed_title(title: &str) -> crate::db::Result<String> {
    let title = clean_title(title).ok_or(Refusal::TitleMissing)?;
    if title.chars().count() > MAX_TITLE_CHARS {
        return Err(Refusal::TitleTooLong {
            max: MAX_TITLE_CHARS,
        }
        .into());
    }
    Ok(title)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum Refusal {
    #[error("todo changed since it was read")]
    TodoChanged,
    #[error("todo title is missing")]
    TitleMissing,
    #[error("todo title exceeds {max} characters")]
    TitleTooLong { max: usize },
    #[error("todo changes can no longer be undone")]
    UndoStale,
    #[error("todo offer is stale")]
    OfferStale,
    #[error("an earlier reply to this message has active todo changes")]
    EarlierReplyStands,
    #[error("reply has no offered todo changes")]
    NothingOffered,
    #[error("reply has no applied todo changes")]
    NothingChanged,
}
