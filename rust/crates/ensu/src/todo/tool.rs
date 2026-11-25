use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::db::{Backend, BackendTx, ChatDb, Error, Result};
use crate::llm::{ToolCall, ToolRequest};
use crate::todo::{self, ListFilter, Todo, TodoChange};

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub(crate) struct TodoTurnData {
    pub(crate) responses: Vec<String>,
    pub(crate) changes: Vec<TodoChange>,
    pub(crate) proposed: Vec<TodoChange>,
    pub(crate) shown: Vec<Uuid>,
}

fn same_task(current: &Todo, left: &Todo) -> bool {
    current.title == left.title
        && current.due_at_ms == left.due_at_ms
        && current.completed_at_ms == left.completed_at_ms
}

pub(crate) fn request<B: Backend>(
    db: &ChatDb<B>,
    todos: &[Todo],
    user_text: &str,
    zone: &impl chrono::TimeZone,
) -> ToolRequest {
    let open = todo::select_tasks(todos, ListFilter::Open, None, db.now_ms(), zone);
    let titles: Vec<&str> = open.iter().map(|todo| todo.title.as_str()).collect();
    todo::chat_tools(user_text, &titles)
}

pub(crate) fn apply<B: Backend, T: BackendTx>(
    db: &ChatDb<B>,
    tx: &T,
    calls: &[ToolCall],
    (captured, user_text): (&[Todo], &str),
    shown: Vec<Uuid>,
    (now_ms, zone): (i64, &impl chrono::TimeZone),
    call_probability: Option<f32>,
) -> Result<(Vec<ToolCall>, String, TodoTurnData)> {
    let mut new_ids = Vec::new();
    let mut plan_for = |todos| {
        let mut next = 0;
        todo::plan(
            calls,
            user_text,
            &shown,
            todos,
            (now_ms, zone),
            call_probability,
            &mut || {
                if next == new_ids.len() {
                    new_ids.push(db.new_uuid());
                }
                let id = new_ids[next];
                next += 1;
                id
            },
        )
        .map_err(|name| Error::UnsupportedOperation(format!("Unknown To Do call {name}")))
    };
    let plan = plan_for(db.todos(tx)?)?;
    if calls.iter().any(|call| call.name == todo::COMPLETE_TOOL) {
        let prepared = plan_for(captured.to_vec())?;
        if plan.changes != prepared.changes {
            return Err(Error::ConversationChanged);
        }
    }
    let text = plan.text(plan.unsure, zone);
    let mut data = TodoTurnData {
        responses: plan.responses(plan.unsure, zone),
        shown: plan.shown.unwrap_or(shown),
        ..Default::default()
    };
    if plan.unsure {
        data.proposed = plan.changes;
    } else {
        for after in plan
            .changes
            .iter()
            .filter_map(|change| change.after.as_ref())
        {
            db.put_todo(tx, after)?;
        }
        data.changes = plan.changes;
    }
    Ok((plan.calls, text, data))
}

pub(crate) fn confirm<B: Backend, T: BackendTx>(
    db: &ChatDb<B>,
    tx: &T,
    data: &mut TodoTurnData,
    now: i64,
) -> Result<bool> {
    if !offer_stands(db, tx, data)? {
        return Ok(false);
    }
    for after in data
        .proposed
        .iter()
        .filter_map(|change| change.after.as_ref())
    {
        let current = db.todo(tx, after.id)?;
        let mut todo = after.clone();
        todo.updated_at_ms = now;
        match &current {
            None => todo.created_at_ms = now,
            Some(current) => todo.version = current.version + 1,
        }
        if todo.completed_at_ms.is_some() {
            todo.completed_at_ms = Some(now);
        }
        db.put_todo(tx, &todo)?;
        data.changes.push(TodoChange {
            before: current,
            after: Some(todo),
        });
    }
    Ok(true)
}

pub(crate) fn undo<B: Backend, T: BackendTx>(
    db: &ChatDb<B>,
    tx: &T,
    data: &TodoTurnData,
    now: i64,
) -> Result<usize> {
    let mut reverted = 0;
    for change in data.changes.iter().rev() {
        let Some(current) = standing(db, tx, change)? else {
            continue;
        };
        match &change.before {
            None => db.delete_todo_row(tx, current.id)?,
            Some(before) => {
                let mut restored = before.clone();
                restored.version = current.version + 1;
                restored.updated_at_ms = now;
                db.put_todo(tx, &restored)?;
            }
        }
        reverted += 1;
    }
    Ok(reverted)
}

fn standing<B: Backend, T: BackendTx>(
    db: &ChatDb<B>,
    tx: &T,
    change: &TodoChange,
) -> Result<Option<Todo>> {
    let Some(after) = &change.after else {
        return Ok(None);
    };
    Ok(db
        .todo(tx, after.id)?
        .filter(|current| same_task(current, after)))
}

pub(crate) fn offer_stands<B: Backend, T: BackendTx>(
    db: &ChatDb<B>,
    tx: &T,
    data: &TodoTurnData,
) -> Result<bool> {
    let mut todos = None;
    for proposed in &data.proposed {
        let Some(after) = &proposed.after else {
            continue;
        };
        let unchanged = match (db.todo(tx, after.id)?, &proposed.before) {
            (None, None) => {
                let todos = match &todos {
                    Some(todos) => todos,
                    None => todos.insert(db.todos(tx)?),
                };
                !todos.iter().any(|todo| {
                    todo.created_at_ms >= after.created_at_ms
                        && todo.title.eq_ignore_ascii_case(&after.title)
                })
            }
            (Some(current), Some(before)) => same_task(&current, before),
            _ => false,
        };
        if !unchanged {
            return Ok(false);
        }
    }
    Ok(true)
}

pub(crate) fn changes_stand<B: Backend, T: BackendTx>(
    db: &ChatDb<B>,
    tx: &T,
    data: &TodoTurnData,
) -> Result<bool> {
    for change in &data.changes {
        if standing(db, tx, change)?.is_some() {
            return Ok(true);
        }
    }
    Ok(false)
}
