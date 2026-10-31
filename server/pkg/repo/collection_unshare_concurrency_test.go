package repo

import (
	"context"
	"database/sql"
	"testing"
	"time"

	"github.com/ente/museum/ente"
)

func TestUnshareIncludesContributionsCommittedWhileWaiting(t *testing.T) {
	repository, db := setupInvitationTest(t)
	collectionID := insertObjectTestCollection(t, db, 1)
	insertObjectTestCollectionShare(t, db, collectionID, 1, 2)
	fileID := insertObjectTestFile(t, db, 2)
	ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
	defer cancel()
	parentGate, err := db.BeginTx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer parentGate.Rollback()
	if _, err := parentGate.ExecContext(ctx, `SELECT collection_id FROM collections
		WHERE collection_id = $1 FOR NO KEY UPDATE`, collectionID); err != nil {
		t.Fatal(err)
	}
	shareGate, err := db.BeginTx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer shareGate.Rollback()
	if _, err := shareGate.ExecContext(ctx, `SELECT collection_id FROM collection_shares
		WHERE collection_id = $1 AND to_user_id = 2 FOR UPDATE`, collectionID); err != nil {
		t.Fatal(err)
	}
	openDB := func(name string) *sql.DB {
		t.Helper()
		connection, err := sql.Open("postgres", "sslmode=disable application_name="+name)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = connection.Close() })
		return connection
	}
	waitForLock := func(name string) {
		t.Helper()
		for {
			var waiting bool
			if err := db.QueryRowContext(ctx, `SELECT EXISTS (SELECT 1 FROM pg_stat_activity
				WHERE datname = current_database() AND application_name = $1 AND wait_event_type = 'Lock')`, name).Scan(&waiting); err != nil {
				t.Fatal(err)
			}
			if waiting {
				return
			}
			time.Sleep(10 * time.Millisecond)
		}
	}
	addDB := openDB("unshare_concurrent_add")
	addRepo := &CollectionRepository{DB: addDB, TrashRepo: &TrashRepository{DB: addDB}}
	repository.DB = openDB("unshare_concurrent_revoke")
	addDone, unshareDone := make(chan struct{}), make(chan struct{})
	var addErr, unshareErr error
	var status ente.CollectionShareStatus
	var unshareStarted bool
	defer func() {
		cancel()
		_ = parentGate.Rollback()
		_ = shareGate.Rollback()
		<-addDone
		if unshareStarted {
			<-unshareDone
		}
	}()
	go func() {
		defer close(addDone)
		addErr = addRepo.AddFiles(ctx, collectionID, 1, []ente.CollectionFileItem{collectionMembershipTestItem(fileID)}, 2)
	}()
	// Keep the insertion uncommitted until unsharing has taken its file snapshot.
	waitForLock("unshare_concurrent_add")
	unshareStarted = true
	go func() {
		defer close(unshareDone)
		status, unshareErr = repository.UnShareContext(ctx, collectionID, 2)
	}()
	waitForLock("unshare_concurrent_revoke")
	if err := parentGate.Commit(); err != nil {
		t.Fatal(err)
	}
	<-addDone
	if addErr != nil {
		t.Fatal(addErr)
	}
	assertInvitationState(t, db, collectionID, 2, ente.CollectionAccepted, false, 0)
	if err := shareGate.Commit(); err != nil {
		t.Fatal(err)
	}
	<-unshareDone
	if unshareErr != nil || status != ente.CollectionUnshared {
		t.Fatalf("UnShareContext() = %s, %v", status, unshareErr)
	}
	assertInvitationState(t, db, collectionID, 2, ente.CollectionAccepted, true, 0)
	if state := readCollectionMembershipState(t, db, collectionID, fileID); !state.isDeleted {
		t.Fatal("unsharing left the concurrently committed contribution active")
	}
}
