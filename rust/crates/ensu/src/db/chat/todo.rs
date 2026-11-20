use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::ChatDb;
use crate::db::backend::{Backend, BackendTx, RowExt, Value};
use crate::db::models::EntityType;
use crate::db::{Error, Refusal, Result};
use crate::llm::{ToolCall, ToolRequest};
use crate::todo::{self, ListFilter, MAX_TITLE_CHARS, Todo, TodoChange};

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub(super) struct TodoTurnData {
    pub(super) responses: Vec<String>,
    pub(super) changes: Vec<TodoChange>,
    pub(super) proposed: Vec<TodoChange>,
    pub(super) shown: Vec<Uuid>,
}

fn same_task(current: &Todo, left: &Todo) -> bool {
    current.title == left.title
        && current.due_at_ms == left.due_at_ms
        && current.completed_at_ms == left.completed_at_ms
}

fn conflict() -> Error {
    Refusal::TodoChanged.into()
}

fn not_found(id: Uuid) -> Error {
    Error::NotFound {
        entity: EntityType::Todo,
        id,
    }
}

impl<B: Backend> ChatDb<B> {
    fn read_todo<T: BackendTx>(&self, tx: &T, id: Uuid) -> Result<Option<Todo>> {
        tx.query_row(
            "SELECT record FROM todos WHERE todo_id = ?",
            &[Value::Text(id.to_string())],
        )?
        .map(|row| self.open(&row.get_blob(0)?))
        .transpose()
    }

    pub(super) fn read_todos<T: BackendTx>(&self, tx: &T) -> Result<Vec<Todo>> {
        tx.query("SELECT record FROM todos ORDER BY created_at, rowid", &[])?
            .into_iter()
            .map(|row| self.open(&row.get_blob(0)?))
            .collect()
    }

    fn write_todo<T: BackendTx>(&self, tx: &T, todo: &Todo) -> Result<()> {
        tx.execute(
            "INSERT INTO todos (todo_id, record, created_at) VALUES (?, ?, ?)
             ON CONFLICT(todo_id) DO UPDATE SET record = excluded.record",
            &[
                Value::Text(todo.id.to_string()),
                Value::Blob(self.seal(todo)?),
                Value::Integer(todo.created_at_ms),
            ],
        )?;
        Ok(())
    }

    fn remove_todo<T: BackendTx>(&self, tx: &T, id: Uuid) -> Result<()> {
        let affected = tx.execute(
            "DELETE FROM todos WHERE todo_id = ?",
            &[Value::Text(id.to_string())],
        )?;
        if affected == 1 {
            Ok(())
        } else {
            Err(not_found(id))
        }
    }

    fn current<T: BackendTx>(&self, tx: &T, id: Uuid, version: u64) -> Result<Todo> {
        let todo = self.read_todo(tx, id)?.ok_or_else(|| not_found(id))?;
        if todo.version != version {
            return Err(conflict());
        }
        Ok(todo)
    }

    pub fn list_todos(&self) -> Result<Vec<Todo>> {
        let mut todos = self.read_todos(&self.backend)?;
        todo::sort_for_display(&mut todos);
        Ok(todos)
    }

    pub(super) fn todo_tools(&self, todos: &[Todo], user_text: &str) -> ToolRequest {
        let open = todo::select_tasks(todos, ListFilter::Open, None, self.now_ms(), &chrono::Local);
        let titles: Vec<&str> = open.iter().map(|todo| todo.title.as_str()).collect();
        todo::chat_tools(user_text, &titles)
    }

    pub fn get_todo(&self, id: Uuid) -> Result<Option<Todo>> {
        self.read_todo(&self.backend, id)
    }

    fn typed_title(title: &str) -> Result<String> {
        let title = todo::clean_title(title).ok_or(Refusal::TitleMissing)?;
        if title.chars().count() > MAX_TITLE_CHARS {
            return Err(Refusal::TitleTooLong {
                max: MAX_TITLE_CHARS,
            }
            .into());
        }
        Ok(title)
    }

    pub fn create_todo(&self, title: &str, due_at_ms: Option<i64>) -> Result<Todo> {
        let title = Self::typed_title(title)?;
        let todo = Todo::new(self.uuid_gen.new_uuid(), title, due_at_ms, self.now_ms());
        self.write_todo(&self.backend, &todo)?;
        self.tools_changed();
        Ok(todo)
    }

    pub fn update_todo(
        &self,
        id: Uuid,
        version: u64,
        title: &str,
        due_at_ms: Option<i64>,
    ) -> Result<Todo> {
        let title = Self::typed_title(title)?;
        let now = self.now_ms();
        self.backend
            .transaction(|tx| {
                let before = self.current(tx, id, version)?;
                let after = before.changed(now, |todo| {
                    todo.title = title;
                    todo.due_at_ms = due_at_ms;
                });
                self.write_todo(tx, &after)?;
                Ok(after)
            })
            .inspect(|_| self.tools_changed())
    }

    pub fn set_todo_completed(&self, id: Uuid, version: u64, completed: bool) -> Result<Todo> {
        let now = self.now_ms();
        let (todo, changed) = self.backend.transaction(|tx| {
            let before = self.current(tx, id, version)?;
            if before.is_open() != completed {
                return Ok((before, false));
            }
            let after = before.changed(now, |todo| {
                todo.completed_at_ms = completed.then_some(now);
            });
            self.write_todo(tx, &after)?;
            Ok((after, true))
        })?;
        if changed {
            self.tools_changed();
        }
        Ok(todo)
    }

    pub fn delete_todo(&self, id: Uuid, version: u64) -> Result<()> {
        self.backend
            .transaction(|tx| {
                self.current(tx, id, version)?;
                self.remove_todo(tx, id)
            })
            .inspect(|_| self.tools_changed())
    }

    pub(super) fn apply_todo_calls<T: BackendTx>(
        &self,
        tx: &T,
        calls: &[ToolCall],
        (captured, user_text): (&[Todo], &str),
        shown: Vec<Uuid>,
        now_ms: i64,
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
                (now_ms, &chrono::Local),
                call_probability,
                &mut || {
                    if next == new_ids.len() {
                        new_ids.push(self.uuid_gen.new_uuid());
                    }
                    let id = new_ids[next];
                    next += 1;
                    id
                },
            )
            .map_err(|name| Error::UnsupportedOperation(format!("Unknown To Do call {name}")))
        };
        let plan = plan_for(self.read_todos(tx)?)?;
        if calls.iter().any(|call| call.name == todo::COMPLETE_TOOL) {
            let prepared = plan_for(captured.to_vec())?;
            if plan.changes != prepared.changes {
                return Err(Error::ConversationChanged);
            }
        }
        let text = plan.text(plan.unsure, &chrono::Local);
        let mut data = TodoTurnData {
            responses: plan.responses(plan.unsure, &chrono::Local),
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
                self.write_todo(tx, after)?;
            }
            data.changes = plan.changes;
        }
        Ok((plan.calls, text, data))
    }

    pub(super) fn confirm_todo_offer<T: BackendTx>(
        &self,
        tx: &T,
        data: &mut TodoTurnData,
        now: i64,
    ) -> Result<bool> {
        if !self.todo_offer_stands(tx, data)? {
            return Ok(false);
        }
        for after in data
            .proposed
            .iter()
            .filter_map(|change| change.after.as_ref())
        {
            let current = self.read_todo(tx, after.id)?;
            let mut todo = after.clone();
            todo.updated_at_ms = now;
            match &current {
                None => todo.created_at_ms = now,
                Some(current) => todo.version = current.version + 1,
            }
            if todo.completed_at_ms.is_some() {
                todo.completed_at_ms = Some(now);
            }
            self.write_todo(tx, &todo)?;
            data.changes.push(TodoChange {
                before: current,
                after: Some(todo),
            });
        }
        Ok(true)
    }

    pub(super) fn undo_todo_changes<T: BackendTx>(
        &self,
        tx: &T,
        data: &TodoTurnData,
        now: i64,
    ) -> Result<usize> {
        let mut reverted = 0;
        for change in data.changes.iter().rev() {
            let Some(current) = self.standing(tx, change)? else {
                continue;
            };
            match &change.before {
                None => self.remove_todo(tx, current.id)?,
                Some(before) => {
                    let mut restored = before.clone();
                    restored.version = current.version + 1;
                    restored.updated_at_ms = now;
                    self.write_todo(tx, &restored)?;
                }
            }
            reverted += 1;
        }
        Ok(reverted)
    }

    fn standing<T: BackendTx>(&self, tx: &T, change: &TodoChange) -> Result<Option<Todo>> {
        let Some(after) = &change.after else {
            return Ok(None);
        };
        Ok(self
            .read_todo(tx, after.id)?
            .filter(|current| same_task(current, after)))
    }

    pub(super) fn todo_offer_stands<T: BackendTx>(
        &self,
        tx: &T,
        data: &TodoTurnData,
    ) -> Result<bool> {
        let mut todos = None;
        for proposed in &data.proposed {
            let Some(after) = &proposed.after else {
                continue;
            };
            let unchanged = match (self.read_todo(tx, after.id)?, &proposed.before) {
                (None, None) => {
                    let todos = match &todos {
                        Some(todos) => todos,
                        None => todos.insert(self.read_todos(tx)?),
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

    pub(super) fn todo_changes_stand<T: BackendTx>(
        &self,
        tx: &T,
        data: &TodoTurnData,
    ) -> Result<bool> {
        for change in &data.changes {
            if self.standing(tx, change)?.is_some() {
                return Ok(true);
            }
        }
        Ok(false)
    }
}

#[cfg(test)]
#[cfg(feature = "sqlite")]
#[path = "todo_tests.rs"]
mod tests;
