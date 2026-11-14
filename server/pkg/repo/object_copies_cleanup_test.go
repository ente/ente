package repo

import (
	"database/sql"
	"fmt"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/lib/pq"
	"github.com/stretchr/testify/require"
)

func TestObjectCopiesCleanupEligibility(t *testing.T) {
	db := setupObjectCopiesCleanupTest(t)
	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "cleanup@example.com", CreationTime: 1})
	var retained []string
	for i, tc := range []struct {
		name       string
		values     string
		wantDelete bool
	}{
		{"complete", "1, 1, 1, true, true, true", true},
		{"thumbnail", "1, 1, NULL, true, true, false", true},
		{"cancelled", "1, NULL, NULL, false, false, false", true},
		{"b2 not requested", "NULL, 1, 1, false, true, true", true},
		{"wasabi not requested", "1, NULL, 1, true, false, true", true},
		{"pending b2", "NULL, 1, 1, true, true, true", false},
		{"pending wasabi", "1, NULL, 1, true, true, true", false},
		{"pending scaleway", "1, 1, NULL, true, true, true", false},
		{"unknown requirement", "1, NULL, 1, true, NULL, true", false},
	} {
		key := fmt.Sprintf("%02d-%s", i, tc.name)
		insertObjectTestKey(t, db, insertObjectTestFile(t, db, ownerID), ente.FILE, key, 100, []string{"b2-eu-cen"})
		_, err := db.Exec(`INSERT INTO object_copies (object_key, b2, wasabi, scw, want_b2, want_wasabi, want_scw)
			VALUES ($1, `+tc.values+`)`, key)
		require.NoError(t, err)
		if !tc.wantDelete {
			retained = append(retained, key)
		}
	}
	repository := &ObjectCopiesRepository{DB: db}
	batch, err := repository.PruneCompletedReplicationBatch(100, 0)
	require.NoError(t, err)
	require.Equal(t, CleanupBatch{Scanned: 9, Deleted: 5, Completed: true}, batch)
	var keys []string
	require.NoError(t, db.QueryRow(`SELECT array_agg(object_key ORDER BY object_key) FROM object_copies`).Scan(pq.Array(&keys)))
	require.Equal(t, retained, keys)
	var count int
	require.NoError(t, db.QueryRow(`SELECT count(*) FROM object_keys`).Scan(&count))
	require.Equal(t, 9, count, "canonical object records must survive pruning")
}

func TestObjectCopiesCleanupResumesAndStopsAtUpperBound(t *testing.T) {
	db := setupObjectCopiesCleanupTest(t)
	insertCleanupObjects(t, db, "", "a", "b", "c")
	_, err := db.Exec(`UPDATE object_copies SET wasabi = NULL WHERE object_key IN ('', 'a')`)
	require.NoError(t, err)
	repository := &ObjectCopiesRepository{DB: db}
	batch, err := repository.PruneCompletedReplicationBatch(2, 0)
	require.NoError(t, err)
	require.Equal(t, CleanupBatch{Scanned: 2}, batch, "a page of pending jobs must advance without ending the sweep")

	insertCleanupObjects(t, db, "z-new")
	_, err = db.Exec(`UPDATE object_copies SET wasabi = 1 WHERE object_key = ''`)
	require.NoError(t, err)
	repository = &ObjectCopiesRepository{DB: db}
	batch, err = repository.PruneCompletedReplicationBatch(2, 0)
	require.NoError(t, err)
	require.Equal(t, CleanupBatch{Scanned: 2, Deleted: 2}, batch)
	batch, err = repository.PruneCompletedReplicationBatch(2, 0)
	require.NoError(t, err)
	require.True(t, batch.Completed)
	var lastKey, upperBound string
	var scanned, deleted int
	require.NoError(t, db.QueryRow(`SELECT last_key, upper_bound, rows_scanned, rows_deleted
		FROM cleanup_progress WHERE name = 'object_copies_completed_v1'`).Scan(&lastKey, &upperBound, &scanned, &deleted))
	require.Equal(t, "c", lastKey)
	require.Equal(t, "c", upperBound)
	require.Equal(t, 4, scanned)
	require.Equal(t, 2, deleted)

	tx, err := db.BeginTx(t.Context(), nil)
	require.NoError(t, err)
	defer tx.Rollback()
	_, err = tx.Exec(`LOCK TABLE object_copies IN ACCESS EXCLUSIVE MODE`)
	require.NoError(t, err)
	repository = &ObjectCopiesRepository{DB: db}
	batch, err = repository.PruneCompletedReplicationBatch(2, 0)
	require.NoError(t, err)
	require.Equal(t, CleanupBatch{Completed: true}, batch)
}

func TestObjectCopiesCleanupEmptyTable(t *testing.T) {
	db := setupObjectCopiesCleanupTest(t)
	batch, err := (&ObjectCopiesRepository{DB: db}).PruneCompletedReplicationBatch(2, 0)
	require.NoError(t, err)
	require.Equal(t, CleanupBatch{Completed: true}, batch)
	var completed bool
	require.NoError(t, db.QueryRow(`SELECT completed_at IS NOT NULL FROM cleanup_progress WHERE name = 'object_copies_completed_v1'`).Scan(&completed))
	require.True(t, completed)
}

func TestObjectCopiesCleanupLeavesOtherJobsUnchanged(t *testing.T) {
	db := setupObjectCopiesCleanupTest(t)
	_, err := db.Exec(`INSERT INTO cleanup_progress (name, last_key, upper_bound, rows_scanned, rows_deleted)
		VALUES ('queue_cleanup_test', '42', '1000', 42, 20)`)
	require.NoError(t, err)
	t.Cleanup(func() {
		_, err := db.Exec(`DELETE FROM cleanup_progress WHERE name = 'queue_cleanup_test'`)
		require.NoError(t, err)
	})
	var before, after string
	require.NoError(t, db.QueryRow(`SELECT to_jsonb(p)::text FROM cleanup_progress p WHERE name = 'queue_cleanup_test'`).Scan(&before))
	batch, err := (&ObjectCopiesRepository{DB: db}).PruneCompletedReplicationBatch(2, 0)
	require.NoError(t, err)
	require.True(t, batch.Completed)
	require.NoError(t, db.QueryRow(`SELECT to_jsonb(p)::text FROM cleanup_progress p WHERE name = 'queue_cleanup_test'`).Scan(&after))
	require.Equal(t, before, after)
}

func TestObjectCopiesCleanupCheckpointFailureRollsBackDeletions(t *testing.T) {
	db := setupObjectCopiesCleanupTest(t)
	insertCleanupObjects(t, db, "a", "b")
	_, err := db.Exec(`CREATE FUNCTION fail_copies_checkpoint() RETURNS trigger LANGUAGE plpgsql AS $$
		BEGIN RAISE EXCEPTION 'checkpoint failed'; END;
		$$;
		CREATE TRIGGER fail_copies_checkpoint BEFORE UPDATE ON cleanup_progress
		FOR EACH ROW EXECUTE FUNCTION fail_copies_checkpoint()`)
	require.NoError(t, err)
	t.Cleanup(func() {
		_, err := db.Exec(`DROP TRIGGER IF EXISTS fail_copies_checkpoint ON cleanup_progress; DROP FUNCTION fail_copies_checkpoint()`)
		require.NoError(t, err)
	})
	repository := &ObjectCopiesRepository{DB: db}
	_, err = repository.PruneCompletedReplicationBatch(1, 0)
	require.ErrorContains(t, err, "checkpoint failed")
	var count int
	var unchanged bool
	require.NoError(t, db.QueryRow(`SELECT count(*) FROM object_copies`).Scan(&count))
	require.Equal(t, 2, count)
	require.NoError(t, db.QueryRow(`SELECT last_key IS NULL AND upper_bound IS NULL
		AND rows_scanned = 0 AND rows_deleted = 0 AND completed_at IS NULL
		FROM cleanup_progress WHERE name = 'object_copies_completed_v1'`).Scan(&unchanged))
	require.True(t, unchanged)
	_, err = db.Exec(`DROP TRIGGER fail_copies_checkpoint ON cleanup_progress`)
	require.NoError(t, err)
	batch, err := repository.PruneCompletedReplicationBatch(1, 0)
	require.NoError(t, err)
	require.Equal(t, CleanupBatch{Scanned: 1, Deleted: 1}, batch)
}

func TestObjectCopiesCleanupRetriesLockedRows(t *testing.T) {
	db := setupObjectCopiesCleanupTest(t)
	insertCleanupObjects(t, db, "a")
	tx, err := db.BeginTx(t.Context(), nil)
	require.NoError(t, err)
	defer tx.Rollback()
	_, err = tx.Exec(`UPDATE object_copies SET wasabi = NULL WHERE object_key = 'a'`)
	require.NoError(t, err)
	repository := &ObjectCopiesRepository{DB: db}
	_, err = repository.PruneCompletedReplicationBatch(1, 0)
	var pgError *pq.Error
	require.ErrorAs(t, err, &pgError)
	require.Equal(t, pq.ErrorCode("55P03"), pgError.Code)
	var unchanged bool
	require.NoError(t, db.QueryRow(`SELECT last_key IS NULL AND rows_scanned = 0
		FROM cleanup_progress WHERE name = 'object_copies_completed_v1'`).Scan(&unchanged))
	require.True(t, unchanged, "locked jobs must not be skipped by advancing the cursor")
	require.NoError(t, tx.Commit())
	batch, err := repository.PruneCompletedReplicationBatch(1, 0)
	require.NoError(t, err)
	require.Equal(t, CleanupBatch{Scanned: 1}, batch)
	var pending bool
	require.NoError(t, db.QueryRow(`SELECT wasabi IS NULL FROM object_copies WHERE object_key = 'a'`).Scan(&pending))
	require.True(t, pending)
}

func TestObjectCopiesCleanupRechecksConcurrentReset(t *testing.T) {
	db := setupObjectCopiesCleanupTest(t)
	insertCleanupObjects(t, db, "a")
	tx, err := db.BeginTx(t.Context(), nil)
	require.NoError(t, err)
	defer tx.Rollback()
	var resetPID int
	require.NoError(t, tx.QueryRow(`SELECT pg_backend_pid()`).Scan(&resetPID))
	_, err = tx.Exec(`UPDATE object_copies SET wasabi = NULL WHERE object_key = 'a'`)
	require.NoError(t, err)
	type outcome struct {
		batch CleanupBatch
		err   error
	}
	result := make(chan outcome, 1)
	go func() {
		batch, err := (&ObjectCopiesRepository{DB: db}).PruneCompletedReplicationBatch(2, 0)
		result <- outcome{batch, err}
	}()
	require.Eventually(t, func() bool {
		var waiting bool
		err := db.QueryRow(`SELECT EXISTS (SELECT 1 FROM pg_stat_activity
			WHERE $1 = ANY(pg_blocking_pids(pid)) AND query LIKE 'DELETE FROM "object_copies"%')`, resetPID).Scan(&waiting)
		return err == nil && waiting
	}, time.Second, time.Millisecond)
	require.NoError(t, tx.Commit())
	got := <-result
	require.NoError(t, got.err)
	require.Equal(t, CleanupBatch{Scanned: 1, Completed: true}, got.batch)
	var pending bool
	require.NoError(t, db.QueryRow(`SELECT wasabi IS NULL FROM object_copies WHERE object_key = 'a'`).Scan(&pending))
	require.True(t, pending)
}

func TestObjectCopiesCleanupCoordinatesInstances(t *testing.T) {
	db := setupObjectCopiesCleanupTest(t)
	insertCleanupObjects(t, db, "a", "b")
	tx, err := db.BeginTx(t.Context(), nil)
	require.NoError(t, err)
	defer tx.Rollback()
	_, err = tx.Exec(`SELECT name FROM cleanup_progress WHERE name = 'object_copies_completed_v1' FOR UPDATE`)
	require.NoError(t, err)
	_, err = (&ObjectCopiesRepository{DB: db}).PruneCompletedReplicationBatch(1, time.Hour)
	var pgError *pq.Error
	require.ErrorAs(t, err, &pgError)
	require.Equal(t, pq.ErrorCode("55P03"), pgError.Code)
	require.NoError(t, tx.Rollback())

	batch, err := (&ObjectCopiesRepository{DB: db}).PruneCompletedReplicationBatch(1, time.Hour)
	require.NoError(t, err)
	require.Equal(t, 1, batch.Scanned)
	batch, err = (&ObjectCopiesRepository{DB: db}).PruneCompletedReplicationBatch(1, time.Hour)
	require.NoError(t, err)
	require.Zero(t, batch.Scanned)
	require.Greater(t, batch.RetryAfter, 59*time.Minute, "the delay applies to other instances too")
	_, err = db.Exec(`UPDATE cleanup_progress SET next_batch_at = now() WHERE name = 'object_copies_completed_v1'`)
	require.NoError(t, err)
	batch, err = (&ObjectCopiesRepository{DB: db}).PruneCompletedReplicationBatch(1, 0)
	require.NoError(t, err)
	require.Equal(t, 1, batch.Scanned)
	require.EqualValues(t, 1, batch.Deleted)
}

func TestObjectCopiesCleanupRejectsInvalidInput(t *testing.T) {
	repository := &ObjectCopiesRepository{}
	_, err := repository.PruneCompletedReplicationBatch(0, 0)
	require.Error(t, err)
	_, err = repository.PruneCompletedReplicationBatch(1, -time.Second)
	require.Error(t, err)
}

func setupObjectCopiesCleanupTest(t *testing.T) *sql.DB {
	t.Helper()
	db := setupFileUsageTest(t)
	reset := func() {
		_, err := db.Exec(`UPDATE cleanup_progress SET last_key = NULL, upper_bound = NULL,
			rows_scanned = 0, rows_deleted = 0, next_batch_at = now(), completed_at = NULL WHERE name = 'object_copies_completed_v1'`)
		require.NoError(t, err)
	}
	reset()
	t.Cleanup(reset)
	return db
}

func insertCleanupObjects(t *testing.T, db *sql.DB, keys ...string) {
	t.Helper()
	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "cleanup-" + keys[0] + "@example.com", CreationTime: 1})
	for _, key := range keys {
		insertObjectTestKey(t, db, insertObjectTestFile(t, db, ownerID), ente.FILE, key, 100, []string{"b2-eu-cen"})
		_, err := db.Exec(`INSERT INTO object_copies (object_key, b2, wasabi, scw, want_b2, want_wasabi, want_scw)
			VALUES ($1, 1, 1, 1, true, true, true)`, key)
		require.NoError(t, err)
	}
}
