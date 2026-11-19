use chrono::TimeZone;

use super::plan::{Outcome, SavedDeadline};
use super::{LIST_LIMIT, Todo, timing};

pub(crate) fn reply(outcomes: &[Outcome], offer: bool, zone: &impl TimeZone) -> String {
    let mut text = String::new();
    let mut after_list = false;
    for outcome in outcomes {
        let list = matches!(outcome, Outcome::Listed { tasks, .. } | Outcome::Ambiguous { tasks } if !tasks.is_empty());
        if !text.is_empty() {
            text.push_str(if list || after_list { "\n\n" } else { "\n" });
        }
        text.push_str(&sentence(outcome, offer, zone));
        after_list = list;
    }
    text
}

fn sentence(outcome: &Outcome, offer: bool, zone: &impl TimeZone) -> String {
    match outcome {
        Outcome::Saved { todo, deadline } => {
            let due = todo.due_at_ms.map_or_else(String::new, |due| {
                format!(", due {}", describe_due(due, zone))
            });
            let note = match deadline {
                SavedDeadline::NotGiven | SavedDeadline::Given => String::new(),
                SavedDeadline::DefaultTime(at) => {
                    format!(" No time was given, so I used {}.", at.format("%-H:%M"))
                }
                SavedDeadline::Unreadable(quote) => {
                    format!(" I couldn't work out the deadline “{quote}”, so it has no due date.")
                }
            };
            if offer {
                format!("Add “{}”{due} to your To Dos?{note}", todo.title)
            } else {
                format!("Saved “{}”{due}.{note}", todo.title)
            }
        }
        Outcome::Untitled => "I couldn't save a task without a title.".into(),
        Outcome::Listed { tasks, total } => {
            let mut lines = numbered(tasks, zone);
            if *total > LIST_LIMIT {
                lines.push(String::new());
                lines.push(format!("Showing {LIST_LIMIT} of {total} tasks."));
            }
            lines.join("\n")
        }
        Outcome::NothingListed => "No tasks match.".into(),
        Outcome::NotInList { number } => {
            format!("There's no task {number} in the last list. Ask me to list your tasks again.")
        }
        Outcome::NamesAnother => "I couldn't find that in your open tasks.".into(),
        Outcome::NotFound { task } => format!("I couldn't find an open task matching “{task}”."),
        Outcome::Unspecified => "Which task should I mark as done?".into(),
        Outcome::AlreadyDone { title } => format!("“{title}” is already done."),
        Outcome::Completed { title } if offer => format!("Mark “{title}” as done?"),
        Outcome::Completed { title } => format!("Marked “{title}” as done."),
        Outcome::Ambiguous { tasks } => format!(
            "Which one should I mark as done?\n{}",
            numbered(tasks, zone).join("\n")
        ),
    }
}

fn numbered(tasks: &[Todo], zone: &impl TimeZone) -> Vec<String> {
    tasks
        .iter()
        .enumerate()
        .map(|(i, todo)| list_line(i + 1, todo, zone))
        .collect()
}

fn describe_due(due_at_ms: i64, zone: &impl TimeZone) -> String {
    timing::local_time(due_at_ms, zone)
        .map(|at| at.format("%a %-d %b %Y, %H:%M").to_string())
        .unwrap_or_else(|| "an unknown time".into())
}

fn list_line(number: usize, todo: &Todo, zone: &impl TimeZone) -> String {
    let due = todo.due_at_ms.map_or_else(
        || "no due date".to_owned(),
        |due| format!("due {}", describe_due(due, zone)),
    );
    let done = if todo.is_open() { "" } else { ", done" };
    format!("{number}. {} — {due}{done}", todo.title)
}
