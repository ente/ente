package repo

import (
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
)

func TestGetCollectionFileState(t *testing.T) {
	_, db := setupAccessibleObjectTest(t)
	repository := &CollectionRepository{DB: db}
	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "collection-file-owner@ente.com",
		CreationTime: 1,
	})
	collectionID := insertObjectTestCollection(t, db, ownerID)
	otherCollectionID := insertObjectTestCollection(t, db, ownerID)
	fileID := insertObjectTestFile(t, db, ownerID)
	linkObjectTestFileToCollection(t, db, collectionID, fileID, ownerID)

	assertState := func(want CollectionFileState, candidateCollectionID, candidateFileID int64) {
		t.Helper()
		state, err := repository.GetCollectionFileState(t.Context(), candidateCollectionID, candidateFileID)
		if err != nil || state != want {
			t.Fatalf("state=%q, want=%q, err=%v", state, want, err)
		}
	}
	assertState(CollectionFileActive, collectionID, fileID)
	for _, candidate := range []struct {
		state        CollectionFileState
		fileID       int64
		collectionID int64
	}{
		{state: CollectionFileAbsent, fileID: fileID + 1, collectionID: collectionID},
		{state: CollectionFileAbsent, fileID: fileID, collectionID: otherCollectionID},
	} {
		assertState(candidate.state, candidate.collectionID, candidate.fileID)
	}

	if _, err := db.Exec(`UPDATE collection_files SET action = $1 WHERE collection_id = $2 AND file_id = $3`, ente.ActionRemove, collectionID, fileID); err != nil {
		t.Fatal(err)
	}
	assertState(CollectionFilePendingRemove, collectionID, fileID)

	if _, err := db.Exec(`UPDATE collection_files SET action = NULL WHERE collection_id = $1 AND file_id = $2`, collectionID, fileID); err != nil {
		t.Fatal(err)
	}
	assertState(CollectionFileActive, collectionID, fileID)

	if _, err := db.Exec(`UPDATE collection_files SET is_deleted = TRUE WHERE collection_id = $1 AND file_id = $2`, collectionID, fileID); err != nil {
		t.Fatal(err)
	}
	assertState(CollectionFileDeleted, collectionID, fileID)
}
