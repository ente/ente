use crate::todo::Refusal;
use uuid::Uuid;

use super::ChatDb;
use crate::db::backend::{Backend, BackendTx, RowExt, Value};
use crate::db::models::EntityType;
use crate::db::{Error, Result};
use crate::todo::{self, Todo};

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
    pub(crate) fn todo<T: BackendTx>(&self, tx: &T, id: Uuid) -> Result<Option<Todo>> {
        tx.query_row(
            "SELECT record FROM todos WHERE todo_id = ?",
            &[Value::Text(id.to_string())],
        )?
        .map(|row| self.open(&row.get_blob(0)?))
        .transpose()
    }

    pub(crate) fn todos<T: BackendTx>(&self, tx: &T) -> Result<Vec<Todo>> {
        tx.query("SELECT record FROM todos ORDER BY created_at, rowid", &[])?
            .into_iter()
            .map(|row| self.open(&row.get_blob(0)?))
            .collect()
    }

    pub(crate) fn put_todo<T: BackendTx>(&self, tx: &T, todo: &Todo) -> Result<()> {
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

    pub(crate) fn delete_todo_row<T: BackendTx>(&self, tx: &T, id: Uuid) -> Result<()> {
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
        let todo = self.todo(tx, id)?.ok_or_else(|| not_found(id))?;
        if todo.version != version {
            return Err(conflict());
        }
        Ok(todo)
    }

    pub fn list_todos(&self) -> Result<Vec<Todo>> {
        let mut todos = self.todos(&self.backend)?;
        todo::sort_for_display(&mut todos);
        Ok(todos)
    }

    pub fn get_todo(&self, id: Uuid) -> Result<Option<Todo>> {
        self.todo(&self.backend, id)
    }

    pub fn create_todo(&self, title: &str, due_at_ms: Option<i64>) -> Result<Todo> {
        let title = todo::typed_title(title)?;
        let todo = Todo::new(self.new_uuid(), title, due_at_ms, self.now_ms());
        self.put_todo(&self.backend, &todo)?;
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
        let title = todo::typed_title(title)?;
        let now = self.now_ms();
        let (todo, changed) = self.backend.transaction(|tx| {
            let before = self.current(tx, id, version)?;
            if before.title == title && before.due_at_ms == due_at_ms {
                return Ok((before, false));
            }
            let after = before.changed(now, |todo| {
                todo.title = title;
                todo.due_at_ms = due_at_ms;
            });
            self.put_todo(tx, &after)?;
            Ok((after, true))
        })?;
        if changed {
            self.tools_changed();
        }
        Ok(todo)
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
            self.put_todo(tx, &after)?;
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
                self.delete_todo_row(tx, id)
            })
            .inspect(|_| self.tools_changed())
    }
}

#[cfg(test)]
#[cfg(feature = "sqlite")]
#[path = "todo_tests.rs"]
mod tests;
