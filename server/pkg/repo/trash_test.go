package repo

import (
	"database/sql"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo/public"
)

func TestTrashFilesUsesRequestItemsAsItsScope(t *testing.T) {
	repository, db := setupTrashTest(t)
	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "trash-owner@ente.com",
		CreationTime: 1,
	})
	collectionID := insertObjectTestCollection(t, db, ownerID)
	requestedFileID := insertObjectTestFile(t, db, ownerID)
	untouchedFileID := insertObjectTestFile(t, db, ownerID)
	linkObjectTestFileToCollection(t, db, collectionID, requestedFileID, ownerID)
	linkObjectTestFileToCollection(t, db, collectionID, untouchedFileID, ownerID)
	insertTrashTestFileLink(t, db, "pft_requested", "requested-token", requestedFileID, ownerID)
	insertTrashTestFileLink(t, db, "pft_untouched", "untouched-token", untouchedFileID, ownerID)

	err := repository.TrashFiles(t.Context(), ownerID, ente.TrashRequest{
		OwnerID: ownerID,
		TrashItems: []ente.TrashItemRequest{{
			FileID:       requestedFileID,
			CollectionID: collectionID,
		}},
	})
	if err != nil {
		t.Fatalf("TrashFiles() error = %v", err)
	}

	var requestedDeleted, untouchedDeleted bool
	err = db.QueryRow(
		`SELECT requested.is_deleted, untouched.is_deleted
		 FROM collection_files AS requested
		 JOIN collection_files AS untouched ON untouched.collection_id = requested.collection_id
		 WHERE requested.collection_id = $1
		   AND requested.file_id = $2
		   AND untouched.file_id = $3`,
		collectionID,
		requestedFileID,
		untouchedFileID,
	).Scan(&requestedDeleted, &untouchedDeleted)
	if err != nil {
		t.Fatalf("failed to read collection file states: %v", err)
	}
	if !requestedDeleted || untouchedDeleted {
		t.Fatalf("unexpected collection file states: requested deleted=%t, untouched deleted=%t", requestedDeleted, untouchedDeleted)
	}

	var trashCount, trashedFileID int64
	if err := db.QueryRow(`SELECT COUNT(*), COALESCE(MAX(file_id), 0) FROM trash`).Scan(&trashCount, &trashedFileID); err != nil {
		t.Fatalf("failed to read trash state: %v", err)
	}
	if trashCount != 1 || trashedFileID != requestedFileID {
		t.Fatalf("unexpected trash state: count=%d file=%d, want count=1 file=%d", trashCount, trashedFileID, requestedFileID)
	}

	var requestedLinkDisabled, untouchedLinkDisabled bool
	err = db.QueryRow(
		`SELECT requested.is_disabled, untouched.is_disabled
		 FROM public_file_tokens AS requested
		 JOIN public_file_tokens AS untouched ON untouched.id = $2
		 WHERE requested.id = $1`,
		"pft_requested",
		"pft_untouched",
	).Scan(&requestedLinkDisabled, &untouchedLinkDisabled)
	if err != nil {
		t.Fatalf("failed to read public file link states: %v", err)
	}
	if !requestedLinkDisabled || untouchedLinkDisabled {
		t.Fatalf("unexpected public file link states: requested disabled=%t, untouched disabled=%t", requestedLinkDisabled, untouchedLinkDisabled)
	}
}

func TestTrashFilesRollsBackWhenFileLinkCleanupFails(t *testing.T) {
	repository, db := setupTrashTest(t)
	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "trash-owner@ente.com",
		CreationTime: 1,
	})
	collectionID := insertObjectTestCollection(t, db, ownerID)
	fileID := insertObjectTestFile(t, db, ownerID)
	linkObjectTestFileToCollection(t, db, collectionID, fileID, ownerID)
	insertTrashTestFileLink(t, db, "pft_failure", "failure-token", fileID, ownerID)

	if _, err := db.Exec(`ALTER TABLE public_file_tokens
		ADD CONSTRAINT test_public_file_tokens_disable_failure CHECK (is_disabled = FALSE)`); err != nil {
		t.Fatalf("failed to install public file link failure constraint: %v", err)
	}
	t.Cleanup(func() {
		if _, err := db.Exec(`ALTER TABLE public_file_tokens
			DROP CONSTRAINT IF EXISTS test_public_file_tokens_disable_failure`); err != nil {
			t.Errorf("failed to remove public file link failure constraint: %v", err)
		}
	})

	err := repository.TrashFiles(t.Context(), ownerID, ente.TrashRequest{
		OwnerID: ownerID,
		TrashItems: []ente.TrashItemRequest{{
			FileID:       fileID,
			CollectionID: collectionID,
		}},
	})
	if err == nil {
		t.Fatal("TrashFiles() succeeded despite public file link cleanup failure")
	}

	var membershipDeleted bool
	if err := db.QueryRow(
		`SELECT is_deleted FROM collection_files WHERE collection_id = $1 AND file_id = $2`,
		collectionID,
		fileID,
	).Scan(&membershipDeleted); err != nil {
		t.Fatalf("failed to read collection file state: %v", err)
	}
	if membershipDeleted {
		t.Fatal("collection membership remained deleted after transaction rollback")
	}

	var trashCount int64
	if err := db.QueryRow(`SELECT COUNT(*) FROM trash WHERE file_id = $1`, fileID).Scan(&trashCount); err != nil {
		t.Fatalf("failed to read trash state: %v", err)
	}
	if trashCount != 0 {
		t.Fatalf("trash row remained after transaction rollback: count=%d", trashCount)
	}

	var linkDisabled bool
	if err := db.QueryRow(`SELECT is_disabled FROM public_file_tokens WHERE id = $1`, "pft_failure").Scan(&linkDisabled); err != nil {
		t.Fatalf("failed to read public file link state: %v", err)
	}
	if linkDisabled {
		t.Fatal("public file link changed despite transaction rollback")
	}
}

func setupTrashTest(t *testing.T) (*TrashRepository, *sql.DB) {
	t.Helper()

	_, db := setupAccessibleObjectTest(t)
	if _, err := db.Exec(`TRUNCATE TABLE public_file_tokens_access_history, public_file_tokens RESTART IDENTITY CASCADE`); err != nil {
		t.Fatalf("failed to reset public file link tables: %v", err)
	}
	t.Cleanup(func() {
		if _, err := db.Exec(`TRUNCATE TABLE public_file_tokens_access_history, public_file_tokens RESTART IDENTITY CASCADE`); err != nil {
			t.Errorf("failed to reset public file link tables: %v", err)
		}
	})

	return &TrashRepository{
		DB:           db,
		FileLinkRepo: public.NewFileLinkRepo(db),
	}, db
}

func insertTrashTestFileLink(t *testing.T, db *sql.DB, id string, token string, fileID int64, ownerID int64) {
	t.Helper()

	_, err := db.Exec(
		`INSERT INTO public_file_tokens(id, file_id, owner_id, app, access_token)
		 VALUES($1, $2, $3, $4, $5)`,
		id,
		fileID,
		ownerID,
		string(ente.Photos),
		token,
	)
	if err != nil {
		t.Fatalf("failed to insert public file link %q: %v", id, err)
	}
}
