package repo

import (
	"errors"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/stretchr/testify/require"
)

func TestPendingUploadVisibility(t *testing.T) {
	collections, db, owner := setupCollectionMembershipTest(t)
	ctx := t.Context()
	album := insertObjectTestCollection(t, db, owner)
	member := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 2, Email: "album-member@example.com", CreationTime: 1})
	insertObjectTestCollectionShare(t, db, album, owner, member)
	admin := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 3, Email: "album-admin@example.com", CreationTime: 1})
	insertObjectTestCollectionShare(t, db, album, owner, admin)
	_, err := db.Exec(`UPDATE collection_shares SET role_type = $1 WHERE collection_id = $2 AND to_user_id = $3`, ente.ADMIN, album, admin)
	require.NoError(t, err)
	files := insertCollectionMembershipTestFiles(t, db, owner, 2)
	pending, published := files[0], files[1]
	linkObjectTestFileToCollection(t, db, album, pending, owner)
	_, err = db.Exec(`UPDATE collection_files SET moderation_status = 'PENDING', anon_user_id = 'guest' WHERE file_id = $1`, pending)
	require.NoError(t, err)
	linkObjectTestFileToCollection(t, db, album, published, owner)

	state, err := collections.GetCollectionFileState(ctx, album, pending)
	require.NoError(t, err)
	require.Equal(t, CollectionFileAwaitingApproval, state)
	require.ErrorIs(t, collections.VerifyAllFileIDsExistsInCollection(ctx, album, files), ente.ErrPermissionDenied)
	require.Error(t, collections.DoAllFilesExistInGivenCollections(files, []int64{album}))
	active, err := collections.FilterActiveFileIDsInCollection(ctx, album, files)
	require.NoError(t, err)
	require.Equal(t, []int64{published}, active)
	count, err := collections.GetCollectionsFilesCount(album)
	require.NoError(t, err)
	require.EqualValues(t, 1, count)

	objects := &ObjectRepository{DB: db}
	for _, objType := range []ente.ObjectType{ente.FILE, ente.THUMBNAIL} {
		insertObjectTestKey(t, db, pending, objType, "pending-"+string(objType), 100, []string{"b2-eu-cen"})
		_, err = objects.GetAccessibleObject(ctx, pending, member, objType)
		require.ErrorIs(t, err, ente.ErrPermissionDenied)
		_, err = objects.GetCollectionObject(ctx, album, pending, objType, nil)
		require.ErrorIs(t, err, ente.ErrPermissionDenied)
		otherGuest := "other"
		_, err = objects.GetCollectionObject(ctx, album, pending, objType, &otherGuest)
		require.ErrorIs(t, err, ente.ErrPermissionDenied)
		guest := "guest"
		_, err = objects.GetCollectionObject(ctx, album, pending, objType, &guest)
		require.NoError(t, err)
		_, err = objects.GetAccessibleObject(ctx, pending, owner, objType)
		require.NoError(t, err)
		_, err = objects.GetAccessibleObject(ctx, pending, admin, objType)
		require.NoError(t, err)
	}
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
