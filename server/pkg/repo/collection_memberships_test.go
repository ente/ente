package repo

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo/public"
)

func TestAddFilesUpsertsBatchAndPreservesConflictFields(t *testing.T) {
	repository, db, ownerID := setupCollectionMembershipTest(t)
	collectionID := insertObjectTestCollection(t, db, ownerID)
	deletedFileID := insertObjectTestFile(t, db, ownerID)
	activeFileID := insertObjectTestFile(t, db, ownerID)
	newFileID := insertObjectTestFile(t, db, ownerID)
	linkObjectTestFileToCollection(t, db, collectionID, deletedFileID, ownerID)
	linkObjectTestFileToCollection(t, db, collectionID, activeFileID, ownerID)

	if _, err := db.Exec(`UPDATE collection_files
		SET is_deleted = TRUE, action_user = $1, action = $2, created_at = 10
		WHERE collection_id = $3 AND file_id = $4`, ownerID, ente.ActionRemove, collectionID, deletedFileID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`UPDATE collection_files
		SET action_user = $1, action = $2, created_at = 20
		WHERE collection_id = $3 AND file_id = $4`, ownerID, ente.ActionRemove, collectionID, activeFileID); err != nil {
		t.Fatal(err)
	}

	files := []ente.CollectionFileItem{
		collectionMembershipTestItem(newFileID),
		collectionMembershipTestItem(activeFileID),
		collectionMembershipTestItem(deletedFileID),
	}
	if err := repository.AddFiles(t.Context(), collectionID, ownerID, files, ownerID); err != nil {
		t.Fatalf("AddFiles() error = %v", err)
	}

	deletedState := readCollectionMembershipState(t, db, collectionID, deletedFileID)
	activeState := readCollectionMembershipState(t, db, collectionID, activeFileID)
	newState := readCollectionMembershipState(t, db, collectionID, newFileID)
	for fileID, state := range map[int64]collectionMembershipState{
		deletedFileID: deletedState,
		activeFileID:  activeState,
		newFileID:     newState,
	} {
		if state.isDeleted {
			t.Errorf("file %d remained deleted", fileID)
		}
		if state.action.Valid || state.actionUser.Valid {
			t.Errorf("file %d retained action state: action=%v user=%v", fileID, state.action, state.actionUser)
		}
		if state.collectionOwnerID != ownerID || state.fileOwnerID != ownerID {
			t.Errorf("file %d owners = (%d, %d), want (%d, %d)", fileID, state.collectionOwnerID, state.fileOwnerID, ownerID, ownerID)
		}
	}

	if deletedState.encryptedKey != "collection-file-key" || deletedState.keyDecryptionNonce != "collection-file-nonce" {
		t.Errorf("reactivated membership replaced encrypted fields: %+v", deletedState)
	}
	if deletedState.createdAt <= 10 {
		t.Errorf("reactivated membership created_at = %d, want greater than 10", deletedState.createdAt)
	}
	if activeState.createdAt != 20 {
		t.Errorf("active membership created_at = %d, want 20", activeState.createdAt)
	}
	if activeState.encryptedKey != "collection-file-key" || activeState.keyDecryptionNonce != "collection-file-nonce" {
		t.Errorf("active membership replaced encrypted fields: %+v", activeState)
	}
	wantNewItem := collectionMembershipTestItem(newFileID)
	if newState.encryptedKey != wantNewItem.EncryptedKey || newState.keyDecryptionNonce != wantNewItem.KeyDecryptionNonce {
		t.Errorf("new membership encrypted fields = (%q, %q), want (%q, %q)",
			newState.encryptedKey, newState.keyDecryptionNonce, wantNewItem.EncryptedKey, wantNewItem.KeyDecryptionNonce)
	}

	var collectionUpdationTime int64
	if err := db.QueryRow(`SELECT updation_time FROM collections WHERE collection_id = $1`, collectionID).Scan(&collectionUpdationTime); err != nil {
		t.Fatal(err)
	}
	for fileID, state := range map[int64]collectionMembershipState{
		deletedFileID: deletedState,
		activeFileID:  activeState,
		newFileID:     newState,
	} {
		if state.updationTime != collectionUpdationTime {
			t.Errorf("file %d updation_time = %d, collection updation_time = %d", fileID, state.updationTime, collectionUpdationTime)
		}
	}
}

func TestAddFilesSupportsMaximumBatchSize(t *testing.T) {
	repository, db, ownerID := setupCollectionMembershipTest(t)
	collectionID := insertObjectTestCollection(t, db, ownerID)
	fileIDs := insertCollectionMembershipTestFiles(t, db, ownerID, 1000)
	files := make([]ente.CollectionFileItem, len(fileIDs))
	for index, fileID := range fileIDs {
		files[index] = collectionMembershipTestItem(fileID)
	}

	if err := repository.AddFiles(t.Context(), collectionID, ownerID, files, ownerID); err != nil {
		t.Fatalf("AddFiles() error = %v", err)
	}

	var count, activeCount int
	if err := db.QueryRow(`SELECT COUNT(*), COUNT(*) FILTER (WHERE is_deleted = FALSE)
		FROM collection_files WHERE collection_id = $1`, collectionID).Scan(&count, &activeCount); err != nil {
		t.Fatal(err)
	}
	if count != len(files) || activeCount != len(files) {
		t.Fatalf("collection membership counts = (%d total, %d active), want (%d, %d)", count, activeCount, len(files), len(files))
	}
}

func TestAddFilesPreservesFirstItemForDuplicateFileID(t *testing.T) {
	repository, db, ownerID := setupCollectionMembershipTest(t)
	collectionID := insertObjectTestCollection(t, db, ownerID)
	fileID := insertObjectTestFile(t, db, ownerID)
	first := collectionMembershipTestItem(fileID)
	second := ente.CollectionFileItem{
		ID:                 fileID,
		EncryptedKey:       "second-encrypted-key",
		KeyDecryptionNonce: "second-key-nonce",
	}

	if err := repository.AddFiles(t.Context(), collectionID, ownerID, []ente.CollectionFileItem{first, second}, ownerID); err != nil {
		t.Fatalf("AddFiles() error = %v", err)
	}

	state := readCollectionMembershipState(t, db, collectionID, fileID)
	if state.encryptedKey != first.EncryptedKey || state.keyDecryptionNonce != first.KeyDecryptionNonce {
		t.Fatalf("duplicate membership encrypted fields = (%q, %q), want first item (%q, %q)",
			state.encryptedKey, state.keyDecryptionNonce, first.EncryptedKey, first.KeyDecryptionNonce)
	}
}

func TestAddFilesRollsBackBatchOnFailure(t *testing.T) {
	repository, db, ownerID := setupCollectionMembershipTest(t)
	collectionID := insertObjectTestCollection(t, db, ownerID)
	validFileID := insertObjectTestFile(t, db, ownerID)
	files := []ente.CollectionFileItem{
		collectionMembershipTestItem(validFileID),
		collectionMembershipTestItem(int64(^uint64(0) >> 1)),
	}

	if err := repository.AddFiles(t.Context(), collectionID, ownerID, files, ownerID); err == nil {
		t.Fatal("AddFiles() succeeded with a nonexistent file")
	}

	var membershipCount int
	if err := db.QueryRow(`SELECT COUNT(*) FROM collection_files WHERE collection_id = $1`, collectionID).Scan(&membershipCount); err != nil {
		t.Fatal(err)
	}
	if membershipCount != 0 {
		t.Fatalf("membership count after rollback = %d, want 0", membershipCount)
	}
	assertCollectionMembershipTestUpdationTime(t, db, collectionID, 1)
}

func TestAddFilesHonorsCanceledContext(t *testing.T) {
	repository, db, ownerID := setupCollectionMembershipTest(t)
	collectionID := insertObjectTestCollection(t, db, ownerID)
	fileID := insertObjectTestFile(t, db, ownerID)
	ctx, cancel := context.WithCancel(t.Context())
	cancel()

	if err := repository.AddFiles(ctx, collectionID, ownerID, []ente.CollectionFileItem{collectionMembershipTestItem(fileID)}, ownerID); err == nil {
		t.Fatal("AddFiles() succeeded with a canceled context")
	}

	var membershipCount int
	if err := db.QueryRow(`SELECT COUNT(*) FROM collection_files WHERE collection_id = $1`, collectionID).Scan(&membershipCount); err != nil {
		t.Fatal(err)
	}
	if membershipCount != 0 {
		t.Fatalf("membership count after canceled request = %d, want 0", membershipCount)
	}
	assertCollectionMembershipTestUpdationTime(t, db, collectionID, 1)
}

func TestAddFilesRejectsTrashedFileInsideTransaction(t *testing.T) {
	repository, db, ownerID := setupCollectionMembershipTest(t)
	collectionID := insertObjectTestCollection(t, db, ownerID)
	fileID := insertObjectTestFile(t, db, ownerID)
	linkObjectTestFileToCollection(t, db, collectionID, fileID, ownerID)
	if _, err := db.Exec(`UPDATE collection_files SET is_deleted = TRUE
		WHERE collection_id = $1 AND file_id = $2`, collectionID, fileID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO trash(file_id, user_id, collection_id, delete_by)
		VALUES($1, $2, $3, $4)`, fileID, ownerID, collectionID, int64(100)); err != nil {
		t.Fatal(err)
	}

	err := repository.AddFiles(t.Context(), collectionID, ownerID, []ente.CollectionFileItem{collectionMembershipTestItem(fileID)}, ownerID)
	if !errors.Is(err, &ente.ErrFileInTrash) {
		t.Fatalf("AddFiles() error = %v, want ErrFileInTrash", err)
	}

	if state := readCollectionMembershipState(t, db, collectionID, fileID); !state.isDeleted {
		t.Fatal("AddFiles() reactivated trashed membership")
	}
}

func TestAddFilesAndTrashFilesSerializeOnFile(t *testing.T) {
	repository, db, ownerID := setupCollectionMembershipTest(t)
	sourceCollectionID := insertObjectTestCollection(t, db, ownerID)
	destinationCollectionID := insertObjectTestCollection(t, db, ownerID)
	fileID := insertObjectTestFile(t, db, ownerID)
	linkObjectTestFileToCollection(t, db, sourceCollectionID, fileID, ownerID)
	repository.TrashRepo.FileLinkRepo = public.NewFileLinkRepo(db)

	addResult := make(chan error, 1)
	trashResult := make(chan error, 1)
	lockReleaseTime := runFileLockRace(t, db, fileID, func() {
		go func() {
			addResult <- repository.AddFiles(t.Context(), destinationCollectionID, ownerID,
				[]ente.CollectionFileItem{collectionMembershipTestItem(fileID)}, ownerID)
		}()
		go func() {
			trashResult <- repository.TrashRepo.TrashFiles(t.Context(), ownerID, ente.TrashRequest{
				TrashItems: []ente.TrashItemRequest{{
					FileID:       fileID,
					CollectionID: sourceCollectionID,
				}},
			})
		}()
	})

	addErr := <-addResult
	if addErr != nil && !errors.Is(addErr, &ente.ErrFileInTrash) {
		t.Fatalf("AddFiles() error = %v", addErr)
	}
	if err := <-trashResult; err != nil {
		t.Fatalf("TrashFiles() error = %v", err)
	}

	var activeMemberships, activeTrashRows int
	if err := db.QueryRow(`SELECT
			(SELECT COUNT(*) FROM collection_files WHERE file_id = $1 AND is_deleted = FALSE),
			(SELECT COUNT(*) FROM trash WHERE file_id = $1 AND is_deleted = FALSE AND is_restored = FALSE)`,
		fileID).Scan(&activeMemberships, &activeTrashRows); err != nil {
		t.Fatal(err)
	}
	if activeMemberships != 0 || activeTrashRows != 1 {
		t.Fatalf("final state = (%d active memberships, %d active Trash rows), want (0, 1)", activeMemberships, activeTrashRows)
	}
	if updationTime := readCollectionMembershipState(t, db, sourceCollectionID, fileID).updationTime; updationTime < lockReleaseTime {
		t.Fatalf("membership updation_time = %d, want >= %d", updationTime, lockReleaseTime)
	}
}

func TestRestoreFilesUpsertsBatchAndMarksTrashRestored(t *testing.T) {
	repository, db, ownerID := setupCollectionMembershipTest(t)
	collectionID := insertObjectTestCollection(t, db, ownerID)
	fileIDs := []int64{
		insertObjectTestFile(t, db, ownerID),
		insertObjectTestFile(t, db, ownerID),
	}
	for _, fileID := range fileIDs {
		linkObjectTestFileToCollection(t, db, collectionID, fileID, ownerID)
		if _, err := db.Exec(`UPDATE collection_files SET is_deleted = TRUE
			WHERE collection_id = $1 AND file_id = $2`, collectionID, fileID); err != nil {
			t.Fatal(err)
		}
		if _, err := db.Exec(`INSERT INTO trash(file_id, user_id, collection_id, delete_by)
			VALUES($1, $2, $3, $4)`, fileID, ownerID, collectionID, int64(100)); err != nil {
			t.Fatal(err)
		}
	}
	files := []ente.CollectionFileItem{
		collectionMembershipTestItem(fileIDs[1]),
		collectionMembershipTestItem(fileIDs[0]),
	}

	if err := repository.RestoreFiles(t.Context(), ownerID, collectionID, files); err != nil {
		t.Fatalf("RestoreFiles() error = %v", err)
	}

	var activeCount, restoredCount int
	if err := db.QueryRow(`SELECT
			COUNT(*) FILTER (WHERE cf.is_deleted = FALSE),
			COUNT(*) FILTER (WHERE t.is_restored = TRUE)
		FROM collection_files AS cf
		JOIN trash AS t ON t.collection_id = cf.collection_id AND t.file_id = cf.file_id
		WHERE cf.collection_id = $1`, collectionID).Scan(&activeCount, &restoredCount); err != nil {
		t.Fatal(err)
	}
	if activeCount != len(files) || restoredCount != len(files) {
		t.Fatalf("restore counts = (%d active, %d restored), want (%d, %d)", activeCount, restoredCount, len(files), len(files))
	}
}

func TestRestoreFilesAndDeleteSerializeOnFile(t *testing.T) {
	repository, db, ownerID := setupCollectionMembershipTest(t)
	collectionID := insertObjectTestCollection(t, db, ownerID)
	fileID := insertObjectTestFile(t, db, ownerID)
	linkObjectTestFileToCollection(t, db, collectionID, fileID, ownerID)
	if _, err := db.Exec(`UPDATE collection_files SET is_deleted = TRUE
		WHERE collection_id = $1 AND file_id = $2`, collectionID, fileID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO trash(file_id, user_id, collection_id, delete_by)
		VALUES($1, $2, $3, $4)`, fileID, ownerID, collectionID, int64(100)); err != nil {
		t.Fatal(err)
	}
	insertObjectTestKey(t, db, fileID, ente.FILE, "restore-delete-race", 100, []string{"b2-eu-cen"})
	testutil.InsertUsage(t, db, ownerID, 100)
	repository.TrashRepo.FileRepo = &FileRepository{
		DB: db,
		ObjectRepo: &ObjectRepository{
			DB:        db,
			QueueRepo: &QueueRepository{DB: db},
		},
	}

	restoreResult := make(chan error, 1)
	deleteResult := make(chan error, 1)
	lockReleaseTime := runFileLockRace(t, db, fileID, func() {
		go func() {
			restoreResult <- repository.RestoreFiles(t.Context(), ownerID, collectionID,
				[]ente.CollectionFileItem{collectionMembershipTestItem(fileID)})
		}()
		go func() {
			deleteResult <- repository.TrashRepo.Delete(t.Context(), ownerID, []int64{fileID})
		}()
	})

	restoreErr := <-restoreResult
	if restoreErr != nil && !errors.Is(restoreErr, ente.ErrBadRequest) {
		t.Fatalf("RestoreFiles() error = %v", restoreErr)
	}
	if err := <-deleteResult; err != nil {
		t.Fatalf("Delete() error = %v", err)
	}

	var membershipDeleted, trashDeleted, trashRestored, objectDeleted bool
	if err := db.QueryRow(`SELECT cf.is_deleted, t.is_deleted, t.is_restored, ok.is_deleted
		FROM collection_files AS cf
		JOIN trash AS t ON t.file_id = cf.file_id
		JOIN object_keys AS ok ON ok.file_id = cf.file_id AND ok.o_type = 'file'
		WHERE cf.collection_id = $1 AND cf.file_id = $2`, collectionID, fileID).Scan(
		&membershipDeleted, &trashDeleted, &trashRestored, &objectDeleted); err != nil {
		t.Fatal(err)
	}
	if membershipDeleted {
		if !trashDeleted || trashRestored || !objectDeleted {
			t.Fatalf("deleted outcome = (trash deleted %t, restored %t, object deleted %t)", trashDeleted, trashRestored, objectDeleted)
		}
	} else {
		if trashDeleted || !trashRestored || objectDeleted {
			t.Fatalf("restored outcome = (trash deleted %t, restored %t, object deleted %t)", trashDeleted, trashRestored, objectDeleted)
		}
		if updationTime := readCollectionMembershipState(t, db, collectionID, fileID).updationTime; updationTime < lockReleaseTime {
			t.Fatalf("membership updation_time = %d, want >= %d", updationTime, lockReleaseTime)
		}
	}
}

func TestMoveFilesUpsertsDestinationAndDeletesSource(t *testing.T) {
	repository, db, ownerID := setupCollectionMembershipTest(t)
	fromCollectionID := insertObjectTestCollection(t, db, ownerID)
	toCollectionID := insertObjectTestCollection(t, db, ownerID)
	fileIDs := []int64{
		insertObjectTestFile(t, db, ownerID),
		insertObjectTestFile(t, db, ownerID),
	}
	for _, fileID := range fileIDs {
		linkObjectTestFileToCollection(t, db, fromCollectionID, fileID, ownerID)
	}
	linkObjectTestFileToCollection(t, db, toCollectionID, fileIDs[1], ownerID)
	if _, err := db.Exec(`UPDATE collection_files SET is_deleted = TRUE, created_at = 10
		WHERE collection_id = $1 AND file_id = $2`, toCollectionID, fileIDs[1]); err != nil {
		t.Fatal(err)
	}
	files := []ente.CollectionFileItem{
		collectionMembershipTestItem(fileIDs[1]),
		collectionMembershipTestItem(fileIDs[0]),
	}

	if err := repository.MoveFiles(t.Context(), toCollectionID, fromCollectionID, files, ownerID, ownerID); err != nil {
		t.Fatalf("MoveFiles() error = %v", err)
	}

	for _, fileID := range fileIDs {
		fromState := readCollectionMembershipState(t, db, fromCollectionID, fileID)
		toState := readCollectionMembershipState(t, db, toCollectionID, fileID)
		if !fromState.isDeleted {
			t.Errorf("source membership for file %d is still active", fileID)
		}
		if toState.isDeleted {
			t.Errorf("destination membership for file %d is still deleted", fileID)
		}
	}

	newDestinationState := readCollectionMembershipState(t, db, toCollectionID, fileIDs[0])
	wantNewItem := collectionMembershipTestItem(fileIDs[0])
	if newDestinationState.encryptedKey != wantNewItem.EncryptedKey || newDestinationState.keyDecryptionNonce != wantNewItem.KeyDecryptionNonce {
		t.Errorf("new destination membership encrypted fields = (%q, %q), want (%q, %q)",
			newDestinationState.encryptedKey, newDestinationState.keyDecryptionNonce, wantNewItem.EncryptedKey, wantNewItem.KeyDecryptionNonce)
	}
	existingDestinationState := readCollectionMembershipState(t, db, toCollectionID, fileIDs[1])
	if existingDestinationState.encryptedKey != "collection-file-key" || existingDestinationState.keyDecryptionNonce != "collection-file-nonce" {
		t.Errorf("existing destination membership replaced encrypted fields: %+v", existingDestinationState)
	}
	if existingDestinationState.createdAt <= 10 {
		t.Errorf("reactivated destination membership created_at = %d, want greater than 10", existingDestinationState.createdAt)
	}

	var fromUpdationTime, toUpdationTime int64
	if err := db.QueryRow(`SELECT source.updation_time, destination.updation_time
		FROM collections AS source
		JOIN collections AS destination ON destination.collection_id = $2
		WHERE source.collection_id = $1`, fromCollectionID, toCollectionID).Scan(&fromUpdationTime, &toUpdationTime); err != nil {
		t.Fatal(err)
	}
	if fromUpdationTime <= 1 || fromUpdationTime != toUpdationTime {
		t.Errorf("collection updation times = (%d, %d), want equal values greater than 1", fromUpdationTime, toUpdationTime)
	}
}

func TestMoveFilesAndTrashFilesSerializeOnFile(t *testing.T) {
	repository, db, ownerID := setupCollectionMembershipTest(t)
	sourceCollectionID := insertObjectTestCollection(t, db, ownerID)
	destinationCollectionID := insertObjectTestCollection(t, db, ownerID)
	fileID := insertObjectTestFile(t, db, ownerID)
	linkObjectTestFileToCollection(t, db, sourceCollectionID, fileID, ownerID)
	repository.TrashRepo.FileLinkRepo = public.NewFileLinkRepo(db)

	moveResult := make(chan error, 1)
	trashResult := make(chan error, 1)
	lockReleaseTime := runFileLockRace(t, db, fileID, func() {
		go func() {
			moveResult <- repository.MoveFiles(t.Context(), destinationCollectionID, sourceCollectionID,
				[]ente.CollectionFileItem{collectionMembershipTestItem(fileID)}, ownerID, ownerID)
		}()
		go func() {
			trashResult <- repository.TrashRepo.TrashFiles(t.Context(), ownerID, ente.TrashRequest{
				TrashItems: []ente.TrashItemRequest{{
					FileID:       fileID,
					CollectionID: sourceCollectionID,
				}},
			})
		}()
	})

	moveErr := <-moveResult
	if moveErr != nil && !errors.Is(moveErr, &ente.ErrFileInTrash) {
		t.Fatalf("MoveFiles() error = %v", moveErr)
	}
	if err := <-trashResult; err != nil {
		t.Fatalf("TrashFiles() error = %v", err)
	}

	var activeMemberships, activeTrashRows int
	if err := db.QueryRow(`SELECT
		(SELECT COUNT(*) FROM collection_files WHERE file_id = $1 AND is_deleted = FALSE),
		(SELECT COUNT(*) FROM trash WHERE file_id = $1 AND is_deleted = FALSE AND is_restored = FALSE)`,
		fileID).Scan(&activeMemberships, &activeTrashRows); err != nil {
		t.Fatal(err)
	}
	if activeMemberships != 0 || activeTrashRows != 1 {
		t.Fatalf("final state = (%d active memberships, %d active Trash rows), want (0, 1)", activeMemberships, activeTrashRows)
	}
	if updationTime := readCollectionMembershipState(t, db, sourceCollectionID, fileID).updationTime; updationTime < lockReleaseTime {
		t.Fatalf("membership updation_time = %d, want >= %d", updationTime, lockReleaseTime)
	}
}

type collectionMembershipState struct {
	encryptedKey       string
	keyDecryptionNonce string
	isDeleted          bool
	updationTime       int64
	collectionOwnerID  int64
	fileOwnerID        int64
	createdAt          int64
	actionUser         sql.NullInt64
	action             sql.NullString
}

func setupCollectionMembershipTest(t *testing.T) (*CollectionRepository, *sql.DB, int64) {
	t.Helper()

	_, db := setupAccessibleObjectTest(t)
	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "collection-membership-owner@ente.com",
		CreationTime: 1,
	})
	return &CollectionRepository{
		DB:        db,
		TrashRepo: &TrashRepository{DB: db},
	}, db, ownerID
}

func collectionMembershipTestItem(fileID int64) ente.CollectionFileItem {
	return ente.CollectionFileItem{
		ID:                 fileID,
		EncryptedKey:       fmt.Sprintf("encrypted-key-%d", fileID),
		KeyDecryptionNonce: fmt.Sprintf("key-nonce-%d", fileID),
	}
}

func insertCollectionMembershipTestFiles(t *testing.T, db *sql.DB, ownerID int64, count int) []int64 {
	t.Helper()

	rows, err := db.Query(`INSERT INTO files(
			owner_id,
			file_decryption_header,
			thumbnail_decryption_header,
			metadata_decryption_header,
			encrypted_metadata,
			updation_time,
			info
		)
		SELECT
			$1,
			'file-header-' || generated.sequence,
			'thumbnail-header-' || generated.sequence,
			'metadata-header-' || generated.sequence,
			'encrypted-metadata-' || generated.sequence,
			1,
			'{}'::jsonb
		FROM generate_series(1, $2) AS generated(sequence)
		RETURNING file_id`, ownerID, count)
	if err != nil {
		t.Fatalf("failed to insert %d files: %v", count, err)
	}
	defer rows.Close()

	fileIDs := make([]int64, 0, count)
	for rows.Next() {
		var fileID int64
		if err := rows.Scan(&fileID); err != nil {
			t.Fatal(err)
		}
		fileIDs = append(fileIDs, fileID)
	}
	if err := rows.Err(); err != nil {
		t.Fatal(err)
	}
	if len(fileIDs) != count {
		t.Fatalf("inserted file count = %d, want %d", len(fileIDs), count)
	}
	return fileIDs
}

func waitForFileLockWaiters(t *testing.T, db *sql.DB) {
	t.Helper()

	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		var count int
		if err := db.QueryRow(`SELECT COUNT(*) FROM pg_stat_activity
			WHERE datname = current_database()
				AND pid <> pg_backend_pid()
				AND wait_event_type = 'Lock'
				AND query LIKE '%FROM files%'
				AND query LIKE '%FOR UPDATE%'`).Scan(&count); err != nil {
			t.Fatal(err)
		}
		if count >= 2 {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("timed out waiting for file-lock waiters")
}

func runFileLockRace(t *testing.T, db *sql.DB, fileID int64, start func()) int64 {
	t.Helper()

	blocker, err := db.BeginTx(t.Context(), nil)
	if err != nil {
		t.Fatal(err)
	}
	defer blocker.Rollback()
	if _, err := blocker.ExecContext(t.Context(), `SELECT file_id FROM files
		WHERE file_id = $1 FOR UPDATE`, fileID); err != nil {
		t.Fatal(err)
	}

	start()
	waitForFileLockWaiters(t, db)
	lockReleaseTime := time.Now().UnixMicro()
	if err := blocker.Commit(); err != nil {
		t.Fatal(err)
	}
	return lockReleaseTime
}

func readCollectionMembershipState(t *testing.T, db *sql.DB, collectionID int64, fileID int64) collectionMembershipState {
	t.Helper()

	var state collectionMembershipState
	err := db.QueryRow(`SELECT
			encrypted_key,
			key_decryption_nonce,
			is_deleted,
			updation_time,
			c_owner_id,
			f_owner_id,
			created_at,
			action_user,
			action
		FROM collection_files
		WHERE collection_id = $1 AND file_id = $2`, collectionID, fileID).Scan(
		&state.encryptedKey,
		&state.keyDecryptionNonce,
		&state.isDeleted,
		&state.updationTime,
		&state.collectionOwnerID,
		&state.fileOwnerID,
		&state.createdAt,
		&state.actionUser,
		&state.action,
	)
	if err != nil {
		t.Fatalf("failed to read collection membership for collection %d file %d: %v", collectionID, fileID, err)
	}
	return state
}

func assertCollectionMembershipTestUpdationTime(t *testing.T, db *sql.DB, collectionID int64, want int64) {
	t.Helper()

	var got int64
	if err := db.QueryRow(`SELECT updation_time FROM collections WHERE collection_id = $1`, collectionID).Scan(&got); err != nil {
		t.Fatal(err)
	}
	if got != want {
		t.Fatalf("collection updation_time = %d, want %d", got, want)
	}
}
