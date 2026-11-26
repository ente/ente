package repo

import (
	"database/sql"
	"testing"

	"github.com/lib/pq"
	"github.com/stretchr/testify/require"
)

func TestCleanupBatchSupportsNumericKeys(t *testing.T) {
	db := setupQueueCleanupTest(t)
	const queueName = "cleanup'queue"
	_, err := db.Exec(`INSERT INTO queue (queue_id, queue_name, item, is_deleted) VALUES
		(2, $1, 'pending', false), (10, $1, 'completed-10', true),
		(20, 'other', 'completed-other', true), (100, $1, 'completed-100', true)`, queueName)
	require.NoError(t, err)
	spec := CleanupSpec{
		Name:            "queue_cleanup_test",
		Table:           "queue",
		KeyColumn:       "queue_id",
		DeleteCondition: "is_deleted = true AND queue_name = $2",
		DeleteArgs:      []any{queueName},
	}
	repository := &CleanupRepository{DB: db}
	invalidSpec := spec
	invalidSpec.DeleteCondition = "missing_column = true"
	_, err = repository.PruneBatch(invalidSpec, 2, 0)
	require.Error(t, err)
	var count int
	require.NoError(t, db.QueryRow(`SELECT count(*) FROM cleanup_progress WHERE name = $1`, spec.Name).Scan(&count))
	require.Zero(t, count)
	require.NoError(t, db.QueryRow(`SELECT count(*) FROM queue`).Scan(&count))
	require.Equal(t, 4, count)

	batch, err := repository.PruneBatch(spec, 2, 0)
	require.NoError(t, err)
	require.Equal(t, CleanupBatch{Scanned: 2, Deleted: 1}, batch)
	var lastKey, upperBound string
	require.NoError(t, db.QueryRow(`SELECT last_key, upper_bound FROM cleanup_progress WHERE name = $1`, spec.Name).
		Scan(&lastKey, &upperBound))
	require.Equal(t, "10", lastKey)
	require.Equal(t, "100", upperBound)
	_, err = db.Exec(`INSERT INTO queue (queue_id, queue_name, item, is_deleted) VALUES (1000, $1, 'new', true)`, queueName)
	require.NoError(t, err)

	repository = &CleanupRepository{DB: db}
	batch, err = repository.PruneBatch(spec, 2, 0)
	require.NoError(t, err)
	require.Equal(t, CleanupBatch{Scanned: 2, Deleted: 1}, batch)
	batch, err = repository.PruneBatch(spec, 2, 0)
	require.NoError(t, err)
	require.Equal(t, CleanupBatch{Completed: true}, batch)
	var scanned, deleted int
	require.NoError(t, db.QueryRow(`SELECT rows_scanned, rows_deleted FROM cleanup_progress WHERE name = $1`, spec.Name).
		Scan(&scanned, &deleted))
	require.Equal(t, 4, scanned)
	require.Equal(t, 2, deleted)
	var keys []int64
	require.NoError(t, db.QueryRow(`SELECT array_agg(queue_id ORDER BY queue_id) FROM queue`).Scan(pq.Array(&keys)))
	require.Equal(t, []int64{2, 20, 1000}, keys)

	tx, err := db.BeginTx(t.Context(), nil)
	require.NoError(t, err)
	defer tx.Rollback()
	_, err = tx.Exec(`LOCK TABLE queue IN ACCESS EXCLUSIVE MODE`)
	require.NoError(t, err)
	batch, err = (&CleanupRepository{DB: db}).PruneBatch(spec, 2, 0)
	require.NoError(t, err)
	require.Equal(t, CleanupBatch{Completed: true}, batch)
}

func TestCleanupBatchGroupsDeleteCondition(t *testing.T) {
	db := setupQueueCleanupTest(t)
	_, err := db.Exec(`INSERT INTO queue (queue_id, queue_name, item, is_deleted) VALUES
		(2, 'cleanup', 'first', false), (10, 'cleanup', 'second', false), (100, 'cleanup', 'third', false)`)
	require.NoError(t, err)
	batch, err := (&CleanupRepository{DB: db}).PruneBatch(CleanupSpec{
		Name:            "queue_cleanup_test",
		Table:           "queue",
		KeyColumn:       "queue_id",
		DeleteCondition: "is_deleted = true OR queue_name = $2",
		DeleteArgs:      []any{"cleanup"},
	}, 1, 0)
	require.NoError(t, err)
	require.Equal(t, CleanupBatch{Scanned: 1, Deleted: 1}, batch)
	var keys []int64
	require.NoError(t, db.QueryRow(`SELECT array_agg(queue_id ORDER BY queue_id) FROM queue`).Scan(pq.Array(&keys)))
	require.Equal(t, []int64{10, 100}, keys)
}

func TestCleanupBatchRequiresExplicitSpec(t *testing.T) {
	for _, spec := range []CleanupSpec{
		{Table: "queue", KeyColumn: "queue_id", DeleteCondition: "is_deleted = true"},
		{Name: "cleanup", KeyColumn: "queue_id", DeleteCondition: "is_deleted = true"},
		{Name: "cleanup", Table: "queue", DeleteCondition: "is_deleted = true"},
		{Name: "cleanup", Table: "queue", KeyColumn: "queue_id"},
	} {
		_, err := (&CleanupRepository{}).PruneBatch(spec, 1, 0)
		require.Error(t, err)
	}
}

func setupQueueCleanupTest(t *testing.T) *sql.DB {
	t.Helper()
	db := setupFileUsageTest(t)
	reset := func() {
		_, err := db.Exec(`TRUNCATE queue; DELETE FROM cleanup_progress WHERE name = 'queue_cleanup_test'`)
		require.NoError(t, err)
	}
	reset()
	t.Cleanup(reset)
	return db
}
