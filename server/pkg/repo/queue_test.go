package repo

import (
	"database/sql"
	"fmt"
	"testing"

	"github.com/ente/museum/internal/testutil"
)

func TestOutdatedObjectQueueUsesNoDelayAndBatchLimit(t *testing.T) {
	repository, db := setupQueueRepositoryTest(t)

	for i := 0; i < 205; i++ {
		if _, err := db.Exec(`INSERT INTO queue(queue_name, item) VALUES($1, $2)`, OutdatedObjectsQueue, fmt.Sprintf("object-%03d", i)); err != nil {
			t.Fatalf("failed to insert queue item: %v", err)
		}
	}

	items, err := repository.GetItemsReadyForDeletion(OutdatedObjectsQueue, 200)
	if err != nil {
		t.Fatalf("GetItemsReadyForDeletion() error = %v", err)
	}
	if len(items) != 200 {
		t.Fatalf("unexpected item count: got %d want 200", len(items))
	}
}

func TestDeleteOutdatedObjectQueueUsesComplianceDelay(t *testing.T) {
	repository, db := setupQueueRepositoryTest(t)

	tx, err := db.BeginTx(t.Context(), nil)
	if err != nil {
		t.Fatalf("failed to begin transaction: %v", err)
	}
	if err := repository.AddItems(t.Context(), tx, DeleteOutdatedObjectQueue, []string{"delayed-object"}); err != nil {
		tx.Rollback()
		t.Fatalf("failed to insert delete outdated object item: %v", err)
	}
	if err := tx.Commit(); err != nil {
		t.Fatalf("failed to commit queue item: %v", err)
	}

	items, err := repository.GetItemsReadyForDeletion(DeleteOutdatedObjectQueue, 1)
	if err != nil {
		t.Fatalf("GetItemsReadyForDeletion() error = %v", err)
	}
	if len(items) != 0 {
		t.Fatalf("new delete outdated object item should not be ready, got %d item(s)", len(items))
	}

	_, err = db.Exec(`UPDATE queue
		SET created_at = now_utc_micro_seconds() - (25::bigint * 24 * 60 * 60 * 1000000)
		WHERE queue_name = $1 AND item = $2`, DeleteOutdatedObjectQueue, "delayed-object")
	if err != nil {
		t.Fatalf("failed to age delete outdated object item: %v", err)
	}

	items, err = repository.GetItemsReadyForDeletion(DeleteOutdatedObjectQueue, 1)
	if err != nil {
		t.Fatalf("GetItemsReadyForDeletion() error after aging = %v", err)
	}
	if len(items) != 1 || items[0].Item != "delayed-object" {
		t.Fatalf("aged delete outdated object item should be ready, got %+v", items)
	}
}

func setupQueueRepositoryTest(t *testing.T) (*QueueRepository, *sql.DB) {
	t.Helper()

	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	truncateQueue(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
		truncateQueue(t, db)
	})

	return &QueueRepository{DB: db}, db
}

func truncateQueue(t *testing.T, db *sql.DB) {
	t.Helper()
	if _, err := db.Exec(`TRUNCATE TABLE queue RESTART IDENTITY`); err != nil {
		t.Fatalf("failed to reset queue table: %v", err)
	}
}
