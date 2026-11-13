package user

import (
	"net/http/httptest"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestUpdateEmailRefreshesSharedCollections(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1, Email: "owner@example.com", CreationTime: 1})
	shareeID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 2, Email: "sharee@example.com", CreationTime: 1})
	collectionRepo := &repo.CollectionRepository{DB: db}
	sharedWithSharee := createUpdateEmailTestCollection(t, collectionRepo, ownerID, &shareeID)
	sharedBySharee := createUpdateEmailTestCollection(t, collectionRepo, shareeID, &ownerID)
	notShared := createUpdateEmailTestCollection(t, collectionRepo, shareeID, nil)
	futureUpdationTime := int64(4_102_444_800_000_000)
	_, err := db.Exec(`UPDATE collections SET updation_time = $1 WHERE collection_id = $2`, futureUpdationTime, sharedBySharee)
	require.NoError(t, err)
	updationTime := func(collectionID int64) int64 {
		var value int64
		require.NoError(t, db.QueryRow(`SELECT updation_time FROM collections WHERE collection_id = $1`, collectionID).Scan(&value))
		return value
	}

	c := &UserController{
		UserRepo:               &repo.UserRepository{DB: db, SecretEncryptionKey: testutil.SecretEncryptionKey(), HashingKey: testutil.HashingKey()},
		CollectionRepo:         collectionRepo,
		BillingController:      &controller.BillingController{BillingRepo: &repo.BillingRepository{DB: db}},
		MailingListsController: &controller.MailingListsController{},
		SecretEncryptionKey:    testutil.SecretEncryptionKey(),
		HashingKey:             testutil.HashingKey(),
	}
	ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
	beforeUpdate := time.Microseconds()
	require.NoError(t, c.UpdateEmail(ctx, shareeID, "new-sharee@example.com"))

	require.GreaterOrEqual(t, updationTime(sharedWithSharee), beforeUpdate)
	require.Greater(t, updationTime(sharedBySharee), futureUpdationTime)
	require.Equal(t, int64(1), updationTime(notShared))
}

func createUpdateEmailTestCollection(t *testing.T, collectionRepo *repo.CollectionRepository, ownerID int64, shareWith *int64) int64 {
	t.Helper()
	collection, err := collectionRepo.Create(ente.Collection{
		Owner:              ente.CollectionUser{ID: ownerID},
		EncryptedKey:       "encrypted-key",
		KeyDecryptionNonce: "key-nonce",
		Name:               "Test collection",
		Type:               "album",
		UpdationTime:       1,
		App:                string(ente.Photos),
	})
	require.NoError(t, err)
	if shareWith != nil {
		require.NoError(t, collectionRepo.Share(collection.ID, ownerID, *shareWith, "share-key", ente.VIEWER, 1))
	}
	return collection.ID
}
