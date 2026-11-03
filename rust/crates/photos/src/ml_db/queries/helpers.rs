use std::collections::HashMap;
use std::hash::Hash;

use crate::db::{self, FromSql, Params, Row, ToSql, Transaction, params_from_iter};

use crate::ml_db::{MlDb, Result};

pub(super) const MAX_SQL_BIND_PARAMS_PER_QUERY: usize = 10000;

impl MlDb {
    pub(in crate::ml_db) fn read_all<C: FromIterator<T>, T, P: Params>(
        &self,
        sql: &str,
        parameters: P,
        map: impl FnMut(&Row<'_>) -> db::Result<T>,
    ) -> Result<C> {
        self.db
            .read(|connection| {
                let mut statement = connection.prepare_cached(sql)?;
                let rows = statement.query_map(parameters, map)?;
                rows.collect::<db::Result<C>>()
            })
            .map_err(Into::into)
    }

    pub(in crate::ml_db) fn read_column<C: FromIterator<T>, T: FromSql, P: Params>(
        &self,
        sql: &str,
        parameters: P,
    ) -> Result<C> {
        self.read_all(sql, parameters, |row| Ok(row.get(0)?))
    }

    pub(in crate::ml_db) fn read_grouped<
        K: FromSql + Eq + Hash,
        V: FromSql,
        C: FromIterator<V>,
        P: Params,
    >(
        &self,
        sql: &str,
        parameters: P,
    ) -> Result<HashMap<K, C>> {
        let rows: Vec<(K, V)> = self.read_all(sql, parameters, pair)?;
        Ok(group_into(rows))
    }

    pub(in crate::ml_db) fn read_value<T: FromSql>(
        &self,
        sql: &str,
        parameters: impl Params,
    ) -> Result<T> {
        self.db
            .read(|connection| {
                connection
                    .prepare_cached(sql)?
                    .query_row(parameters, |row| Ok(row.get(0)?))
            })
            .map_err(Into::into)
    }

    pub(in crate::ml_db) fn read_optional<T>(
        &self,
        sql: &str,
        parameters: impl Params,
        map: impl FnOnce(&Row<'_>) -> db::Result<T>,
    ) -> Result<Option<T>> {
        self.db
            .read(|connection| {
                connection
                    .prepare_cached(sql)?
                    .query_optional(parameters, map)
            })
            .map_err(Into::into)
    }

    pub(in crate::ml_db) fn read_chunked_in<C: FromIterator<T>, T, I: ToSql>(
        &self,
        sql: &str,
        ids: &[I],
        mut map: impl FnMut(&Row<'_>) -> db::Result<T>,
    ) -> Result<C> {
        let mut rows = Vec::new();
        for chunk in ids.chunks(MAX_SQL_BIND_PARAMS_PER_QUERY) {
            let sql = expand_in_clause(sql, chunk.len());
            let chunk_rows: Vec<T> = self.read_all(&sql, params_from_iter(chunk), &mut map)?;
            rows.extend(chunk_rows);
        }
        Ok(rows.into_iter().collect())
    }

    pub(in crate::ml_db) fn execute(&self, sql: &str, parameters: impl Params) -> Result<usize> {
        self.db
            .write(|connection| connection.prepare_cached(sql)?.execute(parameters))
            .map_err(Into::into)
    }

    pub(in crate::ml_db) fn execute_chunked_in<I: ToSql>(
        &self,
        sql: &str,
        ids: &[I],
    ) -> Result<()> {
        if ids.is_empty() {
            return Ok(());
        }
        self.db
            .write_transaction(|transaction| {
                for chunk in ids.chunks(MAX_SQL_BIND_PARAMS_PER_QUERY) {
                    let sql = expand_in_clause(sql, chunk.len());
                    transaction.execute(&sql, params_from_iter(chunk))?;
                }
                Ok(())
            })
            .map_err(Into::into)
    }

    pub(in crate::ml_db) fn execute_statements<'a>(
        &self,
        statements: impl IntoIterator<Item = &'a str>,
    ) -> Result<()> {
        self.db
            .write_transaction(|transaction| {
                for statement in statements {
                    transaction.execute_batch(statement)?;
                }
                Ok(())
            })
            .map_err(Into::into)
    }

    pub(in crate::ml_db) fn write_transaction<T>(
        &self,
        write: impl FnOnce(&Transaction<'_>) -> db::Result<T>,
    ) -> Result<T> {
        self.db.write_transaction(write).map_err(Into::into)
    }

    pub(in crate::ml_db) fn write_batch_atomic<P: Params>(
        &self,
        sql: &str,
        parameter_sets: impl IntoIterator<Item = P>,
    ) -> Result<()> {
        self.db
            .write_transaction(|transaction| {
                let mut statement = transaction.prepare_cached(sql)?;
                for parameters in parameter_sets {
                    statement.execute(parameters)?;
                }
                Ok(())
            })
            .map_err(Into::into)
    }
}

pub(super) fn bind_placeholders(count: usize) -> String {
    vec!["?"; count].join(", ")
}

fn expand_in_clause(sql: &str, count: usize) -> String {
    sql.replacen("{}", &bind_placeholders(count), 1)
}

pub(super) fn pair<A: FromSql, B: FromSql>(row: &Row<'_>) -> db::Result<(A, B)> {
    Ok((row.get(0)?, row.get(1)?))
}

pub(super) fn optional_parameter(value: &Option<impl ToSql>) -> Vec<&dyn ToSql> {
    value.iter().map(|value| value as &dyn ToSql).collect()
}

pub(super) fn group_into<K: Eq + Hash, V, C: FromIterator<V>>(
    rows: impl IntoIterator<Item = (K, V)>,
) -> HashMap<K, C> {
    let mut groups: HashMap<K, Vec<V>> = HashMap::new();
    for (key, value) in rows {
        groups.entry(key).or_default().push(value);
    }
    groups
        .into_iter()
        .map(|(key, values)| (key, values.into_iter().collect()))
        .collect()
}

#[cfg(test)]
mod tests {
    use std::collections::{HashMap, HashSet};

    use crate::db::{Database, OpenOptions};

    use super::{MAX_SQL_BIND_PARAMS_PER_QUERY, bind_placeholders};
    use crate::ml_db::MlDb;

    fn open() -> (tempfile::TempDir, MlDb) {
        let directory = tempfile::tempdir().unwrap();
        let db = Database::open(
            directory.path().join("items.db"),
            OpenOptions::default(),
            |connection| connection.execute_batch("CREATE TABLE items (id INTEGER PRIMARY KEY)"),
        )
        .unwrap();
        (directory, MlDb { db })
    }

    #[test]
    fn reader_queries_reject_writes() {
        let (_directory, db) = open();
        db.execute("INSERT INTO items (id) VALUES (?)", [7])
            .unwrap();
        let deleted: Result<Vec<i64>, _> = db.read_column("DELETE FROM items RETURNING id", ());
        assert!(deleted.is_err());
        assert_eq!(
            db.read_column::<Vec<i64>, _, _>("SELECT id FROM items", ())
                .unwrap(),
            [7]
        );
    }

    #[test]
    fn failed_batch_rolls_back_and_writer_recovers() {
        let (_directory, db) = open();
        assert!(
            db.write_batch_atomic("INSERT INTO items (id) VALUES (?)", [[1], [2], [1]])
                .is_err()
        );
        assert_eq!(
            db.read_value::<i64>("SELECT COUNT(*) FROM items", ())
                .unwrap(),
            0
        );
        assert_eq!(
            db.execute("INSERT INTO items (id) VALUES (?)", [3])
                .unwrap(),
            1
        );
        assert_eq!(
            db.execute("DELETE FROM items WHERE id = ?", [4]).unwrap(),
            0
        );
        assert_eq!(
            db.read_column::<Vec<i64>, _, _>("SELECT id FROM items", ())
                .unwrap(),
            [3]
        );
    }

    #[test]
    fn statement_sequence_rolls_back_if_a_later_statement_fails() {
        let (_directory, db) = open();
        assert!(
            db.execute_statements([
                "INSERT INTO items VALUES (1)",
                "INSERT INTO missing_table VALUES (2)",
            ])
            .is_err()
        );
        assert_eq!(
            db.read_value::<i64>("SELECT COUNT(*) FROM items", ())
                .unwrap(),
            0
        );
    }

    #[test]
    fn chunked_delete_handles_empty_lists_and_rolls_back_on_failure() {
        let (_directory, db) = open();
        let ids: Vec<i64> = (0..10_001).collect();
        db.write_batch_atomic(
            "INSERT INTO items (id) VALUES (?)",
            ids.iter().map(|id| [id]),
        )
        .unwrap();
        db.execute_chunked_in::<i64>("DELETE FROM items WHERE id IN ({})", &[])
            .unwrap();
        assert_eq!(
            db.read_value::<i64>("SELECT COUNT(*) FROM items", ())
                .unwrap(),
            10_001
        );
        db.execute_statements(["CREATE TRIGGER reject_last_delete BEFORE DELETE ON items
             WHEN OLD.id = 10000 BEGIN SELECT RAISE(ABORT, 'cannot delete'); END"])
            .unwrap();
        assert!(
            db.execute_chunked_in("DELETE FROM items WHERE id IN ({})", &ids)
                .is_err()
        );
        assert_eq!(
            db.read_value::<i64>("SELECT COUNT(*) FROM items", ())
                .unwrap(),
            10_001
        );
        db.execute_statements(["DROP TRIGGER reject_last_delete"])
            .unwrap();
        db.execute_chunked_in("DELETE FROM items WHERE id IN ({})", &ids)
            .unwrap();
        assert_eq!(
            db.read_value::<i64>("SELECT COUNT(*) FROM items", ())
                .unwrap(),
            0
        );
    }

    #[test]
    fn chunked_reads_query_each_chunk_in_order() {
        let (_directory, db) = open();
        let boundary = MAX_SQL_BIND_PARAMS_PER_QUERY as i64;
        db.write_batch_atomic(
            "INSERT INTO items (id) VALUES (?)",
            [1, 2, boundary - 1, boundary, boundary + 1].map(|id| [id]),
        )
        .unwrap();
        let ids: Vec<i64> = (0..=boundary + 1).collect();
        let by_chunk: Vec<i64> = db
            .read_chunked_in(
                "SELECT id FROM items WHERE id IN ({}) ORDER BY id DESC",
                &ids,
                |row| Ok(row.get(0)?),
            )
            .unwrap();
        assert_eq!(by_chunk, [boundary - 1, 2, 1, boundary + 1, boundary]);
        let none: Vec<i64> = db
            .read_chunked_in(
                "SELECT id FROM missing_table WHERE id IN ({})",
                &Vec::<i64>::new(),
                |row| Ok(row.get(0)?),
            )
            .unwrap();
        assert!(none.is_empty());
    }

    #[test]
    fn grouped_reads_collect_values_per_key() {
        let (_directory, db) = open();
        db.write_batch_atomic("INSERT INTO items (id) VALUES (?)", (1..=5).map(|id| [id]))
            .unwrap();
        let by_parity: HashMap<i64, Vec<i64>> = db
            .read_grouped("SELECT id % 2, id FROM items ORDER BY id", ())
            .unwrap();
        assert_eq!(
            by_parity,
            HashMap::from([(1, vec![1, 3, 5]), (0, vec![2, 4])])
        );
        let by_label: HashMap<String, HashSet<i64>> = db
            .read_grouped(
                "SELECT CASE WHEN id < 3 THEN 'low' ELSE 'high' END, id FROM items",
                (),
            )
            .unwrap();
        assert_eq!(
            by_label,
            HashMap::from([
                ("low".to_string(), HashSet::from([1, 2])),
                ("high".to_string(), HashSet::from([3, 4, 5]))
            ])
        );
        let empty: HashMap<i64, Vec<i64>> = db
            .read_grouped("SELECT id, id FROM items WHERE id > 5", ())
            .unwrap();
        assert!(empty.is_empty());
    }

    #[test]
    fn bind_placeholders_joins_question_marks() {
        assert_eq!(bind_placeholders(0), "");
        assert_eq!(bind_placeholders(1), "?");
        assert_eq!(bind_placeholders(3), "?, ?, ?");
    }
}
