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

func TestDeleteItemHardDeletesRowAndAllowsReinsert(t *testing.T) {
	repository, db := setupQueueRepositoryTest(t)

	if err := repository.InsertItem(t.Context(), TrashEmptyQueue, "1::100"); err != nil {
		t.Fatalf("failed to insert pending item: %v", err)
	}
	if err := repository.InsertItem(t.Context(), TrashEmptyQueue, "1::200"); err != nil {
		t.Fatalf("failed to insert sibling item: %v", err)
	}
	if err := repository.InsertItem(t.Context(), TrashEmptyLockerQueue, "1::100"); err != nil {
		t.Fatalf("failed to insert other-queue item: %v", err)
	}
	if _, err := db.Exec(`INSERT INTO queue(queue_name, item, is_deleted) VALUES($1, $2, true)`, TrashEmptyQueue, "1::50"); err != nil {
		t.Fatalf("failed to insert historical soft-deleted row: %v", err)
	}

	var firstID int64
	if err := db.QueryRow(`SELECT queue_id FROM queue WHERE queue_name = $1 AND item = $2`, TrashEmptyQueue, "1::100").Scan(&firstID); err != nil {
		t.Fatalf("failed to fetch queue_id for pending item: %v", err)
	}

	if err := repository.DeleteItem(TrashEmptyQueue, firstID); err != nil {
		t.Fatalf("DeleteItem() error = %v", err)
	}

	var count int
	if err := db.QueryRow(`SELECT COUNT(*) FROM queue WHERE queue_name = $1 AND item = $2`, TrashEmptyQueue, "1::100").Scan(&count); err != nil {
		t.Fatalf("failed to count deleted queue row: %v", err)
	}
	if count != 0 {
		t.Fatalf("expected deleted row count = 0, got %d", count)
	}

	for _, tc := range []struct {
		queueName   string
		item        string
		wantDeleted bool
	}{
		{TrashEmptyQueue, "1::200", false},
		{TrashEmptyLockerQueue, "1::100", false},
		{TrashEmptyQueue, "1::50", true},
	} {
		var isDeleted bool
		if err := db.QueryRow(`SELECT is_deleted FROM queue WHERE queue_name = $1 AND item = $2`, tc.queueName, tc.item).Scan(&isDeleted); err != nil {
			t.Fatalf("expected row (%s, %s) to remain, query error = %v", tc.queueName, tc.item, err)
		}
		if isDeleted != tc.wantDeleted {
			t.Fatalf("row (%s, %s) is_deleted = %t, want %t", tc.queueName, tc.item, isDeleted, tc.wantDeleted)
		}
	}

	ready, err := repository.GetItemsReadyForDeletion(TrashEmptyQueue, 10)
	if err != nil {
		t.Fatalf("GetItemsReadyForDeletion() error = %v", err)
	}
	if len(ready) != 1 || ready[0].Item != "1::200" {
		t.Fatalf("expected only 1::200 ready after deletion, got %+v", ready)
	}

	if err := repository.InsertItem(t.Context(), TrashEmptyQueue, "1::100"); err != nil {
		t.Fatalf("InsertItem() after hard delete failed: %v", err)
	}
	ready, err = repository.GetItemsReadyForDeletion(TrashEmptyQueue, 10)
	if err != nil {
		t.Fatalf("GetItemsReadyForDeletion() after reinsert error = %v", err)
	}
	if len(ready) != 2 {
		t.Fatalf("expected 2 ready items after reinsert, got %+v", ready)
	}
	foundReinserted := false
	for _, qItem := range ready {
		if qItem.Item == "1::100" {
			foundReinserted = true
			break
		}
	}
	if !foundReinserted {
		t.Fatalf("expected reinserted item 1::100 in ready items, got %+v", ready)
	}

	if err := repository.DeleteItem(TrashEmptyQueue, 999999); err != nil {
		t.Fatalf("DeleteItem() for non-existent item returned error: %v", err)
	}
}

func TestDeleteItemIgnoresStaleQueueIDAfterReinsert(t *testing.T) {
	repository, db := setupQueueRepositoryTest(t)

	if err := repository.InsertItem(t.Context(), TrashEmptyQueue, "1::100"); err != nil {
		t.Fatalf("failed to insert initial item: %v", err)
	}
	items, err := repository.GetItemsReadyForDeletion(TrashEmptyQueue, 10)
	if err != nil {
		t.Fatalf("GetItemsReadyForDeletion() error = %v", err)
	}
	if len(items) != 1 || items[0].Item != "1::100" {
		t.Fatalf("unexpected initial items: %+v", items)
	}
	firstID := items[0].Id

	if err := repository.DeleteItem(TrashEmptyQueue, firstID); err != nil {
		t.Fatalf("DeleteItem(firstID) error = %v", err)
	}
	if err := repository.InsertItem(t.Context(), TrashEmptyQueue, "1::100"); err != nil {
		t.Fatalf("failed to reinsert item: %v", err)
	}
	items, err = repository.GetItemsReadyForDeletion(TrashEmptyQueue, 10)
	if err != nil {
		t.Fatalf("GetItemsReadyForDeletion() after reinsert error = %v", err)
	}
	if len(items) != 1 || items[0].Item != "1::100" || items[0].Id == firstID {
		t.Fatalf("expected new queue_id != %d for reinserted item, got %+v", firstID, items)
	}
	secondID := items[0].Id

	// Repeating the stale worker acknowledgement for row 1 must not delete row 2.
	if err := repository.DeleteItem(TrashEmptyQueue, firstID); err != nil {
		t.Fatalf("stale DeleteItem(firstID) error = %v", err)
	}
	// Mismatched queue_name must also leave the replacement row untouched.
	if err := repository.DeleteItem(TrashEmptyLockerQueue, secondID); err != nil {
		t.Fatalf("mismatched queue DeleteItem(secondID) error = %v", err)
	}

	items, err = repository.GetItemsReadyForDeletion(TrashEmptyQueue, 10)
	if err != nil {
		t.Fatalf("GetItemsReadyForDeletion() after stale delete error = %v", err)
	}
	if len(items) != 1 || items[0] != (QueueItem{Id: secondID, Item: "1::100"}) {
		t.Fatalf("expected replacement row %d to remain pending, got %+v", secondID, items)
	}

	var count int
	if err := db.QueryRow(`SELECT COUNT(*) FROM queue WHERE queue_id = $1 AND is_deleted = false`, secondID).Scan(&count); err != nil {
		t.Fatalf("failed to verify replacement row: %v", err)
	}
	if count != 1 {
		t.Fatalf("expected replacement row %d count = 1, got %d", secondID, count)
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
