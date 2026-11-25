package repo

import (
	"errors"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/stretchr/testify/require"
)

func TestHasPublishedFiles(t *testing.T) {
	collections, db, owner := setupCollectionMembershipTest(t)
	album := insertObjectTestCollection(t, db, owner)
	files := insertCollectionMembershipTestFiles(t, db, owner, 2)
	linkObjectTestFileToCollection(t, db, album, files[0], owner)
	_, err := db.Exec(`UPDATE collection_files SET moderation_status = 'PENDING' WHERE file_id = $1`, files[0])
	require.NoError(t, err)
	hasPublished, err := collections.HasPublishedFiles(t.Context(), album)
	require.NoError(t, err)
	require.False(t, hasPublished)

	linkObjectTestFileToCollection(t, db, album, files[1], owner)
	hasPublished, err = collections.HasPublishedFiles(t.Context(), album)
	require.NoError(t, err)
	require.True(t, hasPublished)
}

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

func TestVerifyAllFileIDsExistsInCollectionRejectsPendingRemove(t *testing.T) {
	_, db := setupAccessibleObjectTest(t)
	repository := &CollectionRepository{DB: db}
	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID: 2, Email: "copy-membership@ente.com", CreationTime: 1,
	})
	collectionID := insertObjectTestCollection(t, db, ownerID)
	otherCollectionID := insertObjectTestCollection(t, db, ownerID)
	fileID := insertObjectTestFile(t, db, ownerID)
	linkObjectTestFileToCollection(t, db, collectionID, fileID, ownerID)
	linkObjectTestFileToCollection(t, db, otherCollectionID, fileID, ownerID)

	if err := repository.VerifyAllFileIDsExistsInCollection(t.Context(), collectionID, []int64{fileID}); err != nil {
		t.Fatalf("active source membership rejected: %v", err)
	}
	if _, err := db.Exec(`UPDATE collection_files SET action = $1 WHERE collection_id = $2 AND file_id = $3`, ente.ActionRemove, collectionID, fileID); err != nil {
		t.Fatal(err)
	}
	if err := repository.VerifyAllFileIDsExistsInCollection(t.Context(), collectionID, []int64{fileID}); !errors.Is(err, ente.ErrPermissionDenied) {
		t.Fatalf("pending removal error = %v, want permission denied", err)
	}
	if err := repository.VerifyAllFileIDsExistsInCollection(t.Context(), otherCollectionID, []int64{fileID}); err != nil {
		t.Fatalf("active membership in another collection rejected: %v", err)
	}
}
