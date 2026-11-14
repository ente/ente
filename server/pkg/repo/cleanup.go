package repo

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/ente/stacktrace"
	"github.com/lib/pq"
)

type CleanupRepository struct {
	DB *sql.DB
}

type CleanupSpec struct {
	Name            string
	Table           string
	KeyColumn       string
	DeleteCondition string
	DeleteArgs      []any
}

type CleanupBatch struct {
	Scanned    int
	Deleted    int64
	Completed  bool
	RetryAfter time.Duration
}

func (repo *CleanupRepository) PruneBatch(spec CleanupSpec, batchSize int, interval time.Duration) (CleanupBatch, error) {
	var batch CleanupBatch
	if batchSize <= 0 || interval < 0 {
		return batch, stacktrace.NewError("invalid cleanup batch size or interval")
	}
	if spec.Name == "" || spec.Table == "" || spec.KeyColumn == "" || spec.DeleteCondition == "" {
		return batch, stacktrace.NewError("cleanup name, table, key column, and delete condition are required")
	}
	table := pq.QuoteIdentifier(spec.Table)
	keyColumn := pq.QuoteIdentifier(spec.KeyColumn)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	tx, err := repo.DB.BeginTx(ctx, nil)
	if err != nil {
		return batch, stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()
	_, err = tx.ExecContext(ctx, `SET LOCAL lock_timeout = '250ms'; SET LOCAL statement_timeout = '5s'`)
	if err != nil {
		return batch, stacktrace.Propagate(err, "")
	}

	_, err = tx.ExecContext(ctx, `INSERT INTO cleanup_progress (name) VALUES ($1) ON CONFLICT (name) DO NOTHING`, spec.Name)
	if err != nil {
		return batch, stacktrace.Propagate(err, "failed to initialize cleanup progress")
	}

	var lastKey, upperBound sql.NullString
	var completedAt sql.NullTime
	var retrySeconds float64
	err = tx.QueryRowContext(ctx, `SELECT last_key, upper_bound, completed_at,
		GREATEST(0, EXTRACT(EPOCH FROM next_batch_at - clock_timestamp()))
		FROM cleanup_progress WHERE name = $1 FOR UPDATE`, spec.Name).
		Scan(&lastKey, &upperBound, &completedAt, &retrySeconds)
	if err != nil {
		return batch, stacktrace.Propagate(err, "failed to lock cleanup progress")
	}
	if completedAt.Valid {
		batch.Completed = true
		return batch, nil
	}
	if retrySeconds > 0 {
		batch.RetryAfter = time.Duration(retrySeconds * float64(time.Second))
		return batch, nil
	}
	if !upperBound.Valid {
		err = tx.QueryRowContext(ctx, fmt.Sprintf(`SELECT %s FROM %s ORDER BY %s DESC LIMIT 1`, keyColumn, table, keyColumn)).Scan(&upperBound)
		if err != nil && !errors.Is(err, sql.ErrNoRows) {
			return batch, stacktrace.Propagate(err, "failed to bound cleanup")
		}
	}

	keys := make([]string, 0, batchSize)
	if upperBound.Valid {
		query := fmt.Sprintf(`SELECT %s FROM %s WHERE %s <= $1`, keyColumn, table, keyColumn)
		args := []any{upperBound.String}
		if lastKey.Valid {
			query += fmt.Sprintf(` AND %s > $2 ORDER BY %s LIMIT $3`, keyColumn, keyColumn)
			args = append(args, lastKey.String, batchSize)
		} else {
			query += fmt.Sprintf(` ORDER BY %s LIMIT $2`, keyColumn)
			args = append(args, batchSize)
		}
		rows, err := tx.QueryContext(ctx, query, args...)
		if err != nil {
			return batch, stacktrace.Propagate(err, "failed to scan cleanup batch")
		}
		defer rows.Close()
		for rows.Next() {
			var key string
			if err := rows.Scan(&key); err != nil {
				return batch, stacktrace.Propagate(err, "")
			}
			keys = append(keys, key)
		}
		if err := rows.Err(); err != nil {
			return batch, stacktrace.Propagate(err, "")
		}
		if err := rows.Close(); err != nil {
			return batch, stacktrace.Propagate(err, "")
		}
	}

	batch.Scanned = len(keys)
	batch.Completed = len(keys) < batchSize
	if len(keys) > 0 {
		query := fmt.Sprintf(`DELETE FROM %s WHERE %s = ANY($1) AND (%s)`, table, keyColumn, spec.DeleteCondition)
		args := append([]any{pq.Array(keys)}, spec.DeleteArgs...)
		result, err := tx.ExecContext(ctx, query, args...)
		if err != nil {
			return batch, stacktrace.Propagate(err, "failed to delete cleanup batch")
		}
		batch.Deleted, err = result.RowsAffected()
		if err != nil {
			return batch, stacktrace.Propagate(err, "")
		}
		lastKey = sql.NullString{String: keys[len(keys)-1], Valid: true}
	}
	_, err = tx.ExecContext(ctx, `UPDATE cleanup_progress SET
		last_key = $1, upper_bound = $2,
		rows_scanned = rows_scanned + $3, rows_deleted = rows_deleted + $4,
		completed_at = CASE WHEN $5 THEN clock_timestamp() END,
		next_batch_at = clock_timestamp() + $6 * INTERVAL '1 second'
		WHERE name = $7`, lastKey, upperBound, batch.Scanned, batch.Deleted, batch.Completed, interval.Seconds(), spec.Name)
	if err != nil {
		return batch, stacktrace.Propagate(err, "failed to checkpoint cleanup")
	}
	if err := tx.Commit(); err != nil {
		return batch, stacktrace.Propagate(err, "failed to commit cleanup")
	}
	batch.RetryAfter = interval
	return batch, nil
}
