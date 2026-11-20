use chrono::{NaiveDateTime, TimeZone};
use uuid::Uuid;

use super::intent::{Intent, Target};
use super::{
    COMPLETE_TOOL, LIST_LIMIT, LIST_TOOL, MAX_TITLE_CHARS, Todo, TodoChange, matching, refine,
    timing, wording,
};
use crate::llm::ToolCall;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SavedDeadline {
    NotGiven,
    Given,
    DefaultTime(NaiveDateTime),
    Unreadable(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Outcome {
    Saved { todo: Todo, deadline: SavedDeadline },
    Untitled,
    Listed { tasks: Vec<Todo>, total: usize },
    NothingListed,
    NotInList { number: i64 },
    NamesAnother,
    NotFound { task: String },
    Unspecified,
    AlreadyDone { title: String },
    Completed { title: String },
    Ambiguous { tasks: Vec<Todo> },
}

impl Outcome {
    pub fn shown(&self) -> Vec<Uuid> {
        match self {
            Self::Listed { tasks, .. } | Self::Ambiguous { tasks } => {
                tasks.iter().map(|todo| todo.id).collect()
            }
            _ => Vec::new(),
        }
    }
}

pub struct Plan {
    pub calls: Vec<ToolCall>,
    pub changes: Vec<TodoChange>,
    pub shown: Option<Vec<Uuid>>,
    pub unsure: bool,
    pub outcomes: Vec<Outcome>,
}

impl Plan {
    pub fn text(&self, offer: bool, zone: &impl TimeZone) -> String {
        wording::reply(&self.outcomes, offer, zone)
    }

    pub fn responses(&self, offer: bool, zone: &impl TimeZone) -> Vec<String> {
        self.outcomes
            .iter()
            .map(|outcome| wording::reply(std::slice::from_ref(outcome), offer, zone))
            .collect()
    }
}

struct Step {
    outcome: Outcome,
    change: Option<TodoChange>,
}

impl From<Outcome> for Step {
    fn from(outcome: Outcome) -> Self {
        Self {
            outcome,
            change: None,
        }
    }
}

pub fn plan(
    calls: &[ToolCall],
    user_text: &str,
    shown: &[Uuid],
    mut todos: Vec<Todo>,
    (now_ms, zone): (i64, &impl TimeZone),
    call_probability: Option<f32>,
    new_id: &mut dyn FnMut() -> Uuid,
) -> Result<Plan, String> {
    let mut unique: Vec<&ToolCall> = Vec::with_capacity(calls.len());
    let mut since_list = 0;
    for call in calls {
        if call.name == LIST_TOOL {
            since_list = unique.len() + 1;
        } else if call.name == COMPLETE_TOOL && unique[since_list..].contains(&call) {
            continue;
        }
        unique.push(call);
    }
    let places = refine::places(&unique);
    let now = timing::local_time(now_ms, zone);
    let references = refine::references(
        &unique,
        user_text,
        todos
            .iter()
            .filter(|todo| todo.is_open())
            .map(|todo| todo.title.as_str()),
    );
    let mut plan = Plan {
        calls: Vec::with_capacity(unique.len()),
        changes: Vec::new(),
        shown: None,
        unsure: false,
        outcomes: Vec::with_capacity(unique.len()),
    };
    let mut listed: Option<Vec<Uuid>> = None;
    for (call, place) in unique.into_iter().zip(places) {
        let current = listed.as_deref().unwrap_or(shown);
        let intent = refine::interpret(call, &references, current.len(), now, place)?;
        plan.unsure |= super::needs_backing(call_probability) || intent.unsure();
        let step = step(
            &intent, user_text, &mut todos, current, now_ms, zone, new_id,
        );
        let shown = step.outcome.shown();
        if let Some(change) = step.change {
            let id = change.before.as_ref().map(|before| before.id);
            let earlier = plan
                .changes
                .iter_mut()
                .find(|earlier| id.is_some() && earlier.after.as_ref().map(|after| after.id) == id);
            match earlier {
                Some(earlier) => earlier.after = change.after,
                None => plan.changes.push(change),
            }
        }
        let lists = matches!(intent, Intent::List { .. });
        if lists || !shown.is_empty() {
            plan.shown = Some(shown.clone());
        }
        if lists {
            listed = Some(shown);
        }
        plan.calls.push(intent.to_call());
        plan.outcomes.push(step.outcome);
    }
    Ok(plan)
}

fn step(
    intent: &Intent,
    user_text: &str,
    todos: &mut Vec<Todo>,
    shown: &[Uuid],
    now_ms: i64,
    zone: &impl TimeZone,
    new_id: &mut dyn FnMut() -> Uuid,
) -> Step {
    match intent {
        Intent::Save { title, when } => {
            let Some(title) = title
                .as_deref()
                .and_then(super::clean_title)
                .map(|title| title.chars().take(MAX_TITLE_CHARS).collect::<String>())
            else {
                return Outcome::Untitled.into();
            };
            let (due, deadline) = match when {
                None => (None, SavedDeadline::NotGiven),
                Some(when) => {
                    let resolved = when
                        .deadline
                        .and_then(|deadline| Some((deadline.millis(now_ms, zone)?, deadline)));
                    match resolved {
                        Some((due, deadline)) if deadline.default_time => {
                            (Some(due), SavedDeadline::DefaultTime(deadline.at))
                        }
                        Some((due, _)) => (Some(due), SavedDeadline::Given),
                        None => (None, SavedDeadline::Unreadable(when.quote.clone())),
                    }
                }
            };
            let todo = Todo::new(new_id(), title, due, now_ms);
            todos.push(todo.clone());
            Step {
                change: Some(TodoChange {
                    before: None,
                    after: Some(todo.clone()),
                }),
                outcome: Outcome::Saved { todo, deadline },
            }
        }
        Intent::List { filter, query } => {
            let filter = filter.unwrap_or(super::ListFilter::Open);
            let selected = super::select_tasks(todos, filter, query.as_deref(), now_ms, zone);
            if selected.is_empty() {
                return Outcome::NothingListed.into();
            }
            Outcome::Listed {
                total: selected.len(),
                tasks: selected.into_iter().take(LIST_LIMIT).cloned().collect(),
            }
            .into()
        }
        Intent::Complete { target, .. } => {
            let target = if let Target::Position(number) = *target {
                let id = usize::try_from(number)
                    .ok()
                    .and_then(|n| n.checked_sub(1))
                    .and_then(|i| shown.get(i));
                match id.and_then(|id| todos.iter().find(|todo| todo.id == *id)) {
                    Some(todo) => vec![todo.clone()],
                    None => return Outcome::NotInList { number }.into(),
                }
            } else if let Target::Named(task) = target {
                if matching::names_another(task, user_text) {
                    return Outcome::NamesAnother.into();
                }
                let open: Vec<_> = todos.iter().filter(|todo| todo.is_open()).collect();
                let found: Vec<_> = super::find_tasks(&open, task)
                    .into_iter()
                    .cloned()
                    .collect();
                if found.is_empty() {
                    return Outcome::NotFound { task: task.clone() }.into();
                }
                found
            } else {
                return Outcome::Unspecified.into();
            };
            match target.as_slice() {
                [todo] if !todo.is_open() => Outcome::AlreadyDone {
                    title: todo.title.clone(),
                }
                .into(),
                [todo] => {
                    let after = todo.changed(now_ms, |todo| todo.completed_at_ms = Some(now_ms));
                    if let Some(stored) = todos.iter_mut().find(|stored| stored.id == todo.id) {
                        *stored = after.clone();
                    }
                    Step {
                        outcome: Outcome::Completed {
                            title: todo.title.clone(),
                        },
                        change: Some(TodoChange {
                            before: Some(todo.clone()),
                            after: Some(after),
                        }),
                    }
                }
                many => Outcome::Ambiguous {
                    tasks: many.iter().take(LIST_LIMIT).cloned().collect(),
                }
                .into(),
            }
        }
    }
}
