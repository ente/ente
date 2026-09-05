package repo

import (
	"database/sql"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/repo/public"
)

func TestTrashAndRestoreMaintainReadyLockerCount(t *testing.T) {
	repository, db, userID := setupCollectionMembershipTest(t)
	setReadyFileCounts(t, db, userID, 0, 1)
	firstCollectionID := insertObjectTestCollection(t, db, userID)
	secondCollectionID := insertObjectTestCollection(t, db, userID)
	if _, err := db.Exec(`UPDATE collections SET app = 'locker'
		WHERE collection_id IN ($1, $2)`, firstCollectionID, secondCollectionID); err != nil {
		t.Fatal(err)
	}
	fileID := insertObjectTestFile(t, db, userID)
	linkObjectTestFileToCollection(t, db, firstCollectionID, fileID, userID)
	linkObjectTestFileToCollection(t, db, secondCollectionID, fileID, userID)
	repository.TrashRepo.FileLinkRepo = public.NewFileLinkRepo(db)

	if err := repository.TrashRepo.TrashFiles(t.Context(), userID, ente.TrashRequest{
		TrashItems: []ente.TrashItemRequest{{FileID: fileID, CollectionID: firstCollectionID}},
	}); err != nil {
		t.Fatalf("TrashFiles() error = %v", err)
	}
	assertReadyFileCounts(t, db, userID, 0, 0, 1)

	if err := repository.RestoreFiles(t.Context(), userID, firstCollectionID,
		[]ente.CollectionFileItem{collectionMembershipTestItem(fileID)}); err != nil {
		t.Fatalf("RestoreFiles() error = %v", err)
	}
	assertReadyFileCounts(t, db, userID, 0, 1, 2)
}

func TestTrashInvalidatesCrossAppFileCounts(t *testing.T) {
	repository, db, userID := setupCollectionMembershipTest(t)
	setReadyFileCounts(t, db, userID, 1, 1)
	photosCollectionID := insertObjectTestCollection(t, db, userID)
	lockerCollectionID := insertObjectTestCollection(t, db, userID)
	if _, err := db.Exec(`UPDATE collections SET app = 'locker' WHERE collection_id = $1`, lockerCollectionID); err != nil {
		t.Fatal(err)
	}
	fileID := insertObjectTestFile(t, db, userID)
	linkObjectTestFileToCollection(t, db, photosCollectionID, fileID, userID)
	linkObjectTestFileToCollection(t, db, lockerCollectionID, fileID, userID)
	repository.TrashRepo.FileLinkRepo = public.NewFileLinkRepo(db)

	if err := repository.TrashRepo.TrashFiles(t.Context(), userID, ente.TrashRequest{
		TrashItems: []ente.TrashItemRequest{{FileID: fileID, CollectionID: photosCollectionID}},
	}); err != nil {
		t.Fatalf("TrashFiles() error = %v", err)
	}

	photos, locker, version := readFileCountState(t, db, userID)
	if photos.Valid || locker.Valid || version != 1 {
		t.Fatalf("file count state = (%v, %v, %d), want (NULL, NULL, 1)", photos, locker, version)
	}
}

func setReadyFileCounts(t *testing.T, db *sql.DB, userID, photos, locker int64) {
	t.Helper()
	if _, err := db.Exec(`UPDATE usage
		SET photos_file_count = $2, locker_file_count = $3
		WHERE user_id = $1`, userID, photos, locker); err != nil {
		t.Fatal(err)
	}
}

func assertReadyFileCounts(t *testing.T, db *sql.DB, userID, wantPhotos, wantLocker, wantVersion int64) {
	t.Helper()
	photos, locker, version := readFileCountState(t, db, userID)
	if !photos.Valid || photos.Int64 != wantPhotos || !locker.Valid || locker.Int64 != wantLocker || version != wantVersion {
		t.Fatalf("file count state = (%v, %v, %d), want (%d, %d, %d)", photos, locker, version, wantPhotos, wantLocker, wantVersion)
	}
}

func readFileCountState(t *testing.T, db *sql.DB, userID int64) (sql.NullInt64, sql.NullInt64, int64) {
	t.Helper()
	var photos, locker sql.NullInt64
	var version int64
	if err := db.QueryRow(`SELECT photos_file_count, locker_file_count, file_count_source_version
		FROM usage WHERE user_id = $1`, userID).Scan(&photos, &locker, &version); err != nil {
		t.Fatal(err)
	}
	return photos, locker, version
}
