package collections

import (
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/controller/access"
	"github.com/ente/museum/pkg/repo"
	publicrepo "github.com/ente/museum/pkg/repo/public"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestModeratePendingFiles(t *testing.T) {
	db, collectionRepo, ownerID, viewerID := setupCollectionShareTest(t)
	testutil.InsertUsage(t, db, ownerID, 0)
	adminID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 3, Email: "admin@example.com", CreationTime: 1})
	collectionID := createShareTestCollection(t, collectionRepo, ownerID)
	addShareTestShare(t, collectionRepo, collectionID, ownerID, viewerID, ente.VIEWER)
	addShareTestShare(t, collectionRepo, collectionID, ownerID, adminID, ente.ADMIN)
	normal := addShareTestOwnerFile(t, db, collectionID, ownerID)
	approved := addShareTestOwnerFile(t, db, collectionID, ownerID)
	rejected := addShareTestOwnerFile(t, db, collectionID, ownerID)
	removed := addShareTestOwnerFile(t, db, collectionID, ownerID)
	otherGuests := addShareTestOwnerFile(t, db, collectionID, ownerID)
	_, err := db.Exec(`UPDATE collection_files SET moderation_status = 'PENDING', anon_user_id = CASE WHEN file_id = $3 THEN 'other' ELSE 'guest' END
		WHERE collection_id = $1 AND file_id <> $2`, collectionID, normal, otherGuests)
	require.NoError(t, err)
	controller := &CollectionController{
		AccessCtrl:     access.NewAccessController(collectionRepo, nil),
		CollectionRepo: collectionRepo,
		TrashRepo: &repo.TrashRepository{
			DB:           db,
			FileLinkRepo: publicrepo.NewFileLinkRepo(db),
			FileRepo:     &repo.FileRepository{DB: db, ObjectRepo: &repo.ObjectRepository{DB: db}},
		},
	}
	state := func(fileID int64) (status *string, isDeleted bool, createdAt int64) {
		t.Helper()
		require.NoError(t, db.QueryRow(`SELECT moderation_status, is_deleted, created_at FROM collection_files WHERE collection_id = $1 AND file_id = $2`,
			collectionID, fileID).Scan(&status, &isDeleted, &createdAt))
		return status, isDeleted, createdAt
	}
	request := func(fileIDs ...int64) ente.PendingFilesRequest {
		return ente.PendingFilesRequest{CollectionID: collectionID, FileIDs: fileIDs}
	}

	require.ErrorIs(t, controller.ApprovePendingFiles(newBatchShareTestContext(viewerID), request(approved)), ente.ErrPermissionDenied)
	require.ErrorIs(t, controller.RejectPendingFiles(newBatchShareTestContext(viewerID), request(rejected)), ente.ErrPermissionDenied)

	_, _, createdBefore := state(approved)
	require.NoError(t, controller.ApprovePendingFiles(newBatchShareTestContext(adminID), request(approved, normal)))
	var albumTime, albumTimeAfter int64
	require.NoError(t, db.QueryRow(`SELECT updation_time FROM collections WHERE collection_id = $1`, collectionID).Scan(&albumTime))
	require.NoError(t, controller.ApprovePendingFiles(newBatchShareTestContext(ownerID), request(approved)))
	require.NoError(t, db.QueryRow(`SELECT updation_time FROM collections WHERE collection_id = $1`, collectionID).Scan(&albumTimeAfter))
	require.Equal(t, albumTime, albumTimeAfter)
	status, isDeleted, createdAt := state(approved)
	require.Equal(t, ente.ModerationApproved, *status)
	require.False(t, isDeleted)
	require.Greater(t, createdAt, createdBefore)
	status, _, _ = state(normal)
	require.Nil(t, status)

	require.NoError(t, controller.RejectPendingFiles(newBatchShareTestContext(ownerID), request(rejected, normal)))
	status, isDeleted, _ = state(rejected)
	require.Equal(t, ente.ModerationRejected, *status)
	require.True(t, isDeleted)
	_, isDeleted, _ = state(normal)
	require.False(t, isDeleted)

	guestContext := func(guestID string) *gin.Context {
		ctx := newFileDiffTestContext("/public-collection/pending-files")
		ctx.Set(auth.PublicAccessKey, ente.PublicAccessContext{CollectionID: collectionID})
		if guestID != "" {
			auth.SetPublicAnonUserID(ctx, guestID)
		}
		return ctx
	}
	require.ErrorIs(t, controller.RemovePendingFile(guestContext(""), removed), ente.ErrPermissionDenied)
	require.ErrorIs(t, controller.RemovePendingFile(guestContext("guest"), otherGuests), ente.ErrNotFound)
	status, isDeleted, _ = state(otherGuests)
	require.Equal(t, ente.ModerationPending, *status)
	require.False(t, isDeleted)
	require.NoError(t, controller.RemovePendingFile(guestContext("guest"), removed))
	status, isDeleted, _ = state(removed)
	require.Equal(t, ente.ModerationRemoved, *status)
	require.True(t, isDeleted)
	require.ErrorIs(t, controller.RemovePendingFile(guestContext("guest"), removed), ente.ErrNotFound)
	require.ErrorIs(t, controller.RemovePendingFile(guestContext("guest"), rejected), ente.ErrNotFound)
	var trashDeleted bool
	require.NoError(t, db.QueryRow(`SELECT is_deleted FROM trash WHERE file_id = $1`, rejected).Scan(&trashDeleted))
	require.False(t, trashDeleted)
	require.NoError(t, db.QueryRow(`SELECT is_deleted FROM trash WHERE file_id = $1`, removed).Scan(&trashDeleted))
	require.True(t, trashDeleted)
}
