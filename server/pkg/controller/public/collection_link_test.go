package public

import (
	"context"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/repo/public"
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
