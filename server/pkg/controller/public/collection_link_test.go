package public

import (
	"context"
	"net/http/httptest"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/repo/public"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/gin-gonic/gin"
	"github.com/sirupsen/logrus"
	"github.com/stretchr/testify/require"
)

func TestHandleAccountDeletionDeletesMemoryShares(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	ctx := context.Background()
	userID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "owner@example.com", CreationTime: 1})
	otherUserID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "other@example.com", CreationTime: 1})
	memoryShareRepo := repo.NewMemoryShareRepository(db)
	userShare, err := memoryShareRepo.Create(ctx, ente.MemoryShare{UserID: userID, Type: ente.MemoryShareTypeShare, EncryptedKey: "key", KeyDecryptionNonce: "nonce", AccessToken: "owner-token"})
	require.NoError(t, err)
	otherShare, err := memoryShareRepo.Create(ctx, ente.MemoryShare{UserID: otherUserID, Type: ente.MemoryShareTypeShare, EncryptedKey: "key", KeyDecryptionNonce: "nonce", AccessToken: "other-token"})
	require.NoError(t, err)
	c := &CollectionLinkController{
		CollectionLinkRepo: &public.CollectionLinkRepo{DB: db},
		FileLinkRepo:       &public.FileLinkRepository{DB: db},
		MemoryShareRepo:    memoryShareRepo,
	}

	require.NoError(t, c.HandleAccountDeletion(ctx, userID, logrus.NewEntry(logrus.New())))

	deletedShare, err := memoryShareRepo.GetByID(ctx, userShare.ID)
	require.NoError(t, err)
	require.True(t, deletedShare.IsDeleted)
	remainingShare, err := memoryShareRepo.GetByID(ctx, otherShare.ID)
	require.NoError(t, err)
	require.False(t, remainingShare.IsDeleted)
}

func TestCreateFileNeedsGuestIdentityWhenApprovalIsOn(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "owner@example.com", CreationTime: 1})
	linkRepo := &public.CollectionLinkRepo{DB: db}
	collectionRepo := &repo.CollectionRepository{DB: db, CollectionLinkRepo: linkRepo, SecretEncryptionKey: testutil.SecretEncryptionKey()}
	collection, err := collectionRepo.Create(ente.Collection{Owner: ente.CollectionUser{ID: ownerID}, App: string(ente.Photos), Type: "album",
		Name: "album", EncryptedKey: "key", KeyDecryptionNonce: "nonce", UpdationTime: 1})
	require.NoError(t, err)
	require.NoError(t, linkRepo.Insert(context.Background(), collection.ID, "approval-token", 0, 0, true, false, nil))
	_, err = db.Exec(`UPDATE public_collection_tokens SET require_approval = TRUE WHERE collection_id = $1`, collection.ID)
	require.NoError(t, err)

	ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
	ctx.Request = httptest.NewRequest("POST", "/public-collection/file", nil)
	ctx.Set(auth.PublicAccessKey, ente.PublicAccessContext{CollectionID: collection.ID})
	_, err = (&CollectionLinkController{CollectionRepo: collectionRepo}).CreateFile(ctx, ente.File{CollectionID: collection.ID}, ente.Photos)
	require.ErrorIs(t, err, ente.ErrAuthenticationRequired)
}
