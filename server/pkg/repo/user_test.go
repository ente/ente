package repo

import (
	"context"
	"database/sql"
	"testing"
	"time"

	"github.com/ente/museum/internal/testutil"
	storageBonusRepo "github.com/ente/museum/pkg/repo/storagebonus"
	"github.com/stretchr/testify/require"
)

func TestGetUsersWhoUpgradedNDaysAgoIncludesFamilyAdminID(t *testing.T) {
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })

	soloUserID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1, Email: "solo@example.com", CreationTime: 1})
	familyAdminID := int64(2)
	testutil.InsertUser(t, db, testutil.UserFixture{UserID: familyAdminID, Email: "family@example.com", CreationTime: 1, FamilyAdminID: &familyAdminID})
	for _, userID := range []int64{soloUserID, familyAdminID} {
		testutil.InsertSubscription(t, db, testutil.SubscriptionFixture{UserID: userID, Storage: 1})
	}
	_, err := db.Exec(`UPDATE subscriptions SET upgraded_at = now_utc_micro_seconds() - 721::BIGINT * 60 * 60 * 1000 * 1000`)
	require.NoError(t, err)

	userRepo := &UserRepository{DB: db, SecretEncryptionKey: testutil.SecretEncryptionKey()}
	users, err := userRepo.GetUsersWhoUpgradedNDaysAgo(30)
	require.NoError(t, err)

	familyAdminIDs := make(map[int64]*int64)
	for _, user := range users {
		familyAdminIDs[user.ID] = user.FamilyAdminID
	}
	require.Len(t, familyAdminIDs, 2)
	require.Nil(t, familyAdminIDs[soloUserID])
	require.NotNil(t, familyAdminIDs[familyAdminID])
	require.Equal(t, familyAdminID, *familyAdminIDs[familyAdminID])
}

func TestGetUsersWithIndividualPlanWhoHaveExceededStorageQuota(t *testing.T) {
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })

	pool, err := sql.Open("postgres", "sslmode=disable")
	require.NoError(t, err)
	pool.SetMaxOpenConns(1)
	t.Cleanup(func() { _ = pool.Close() })

	activeUserID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "over@example.com",
		CreationTime: 1,
	})
	deletedUserID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       2,
		Email:        "deleted-over@example.com",
		CreationTime: 1,
	})
	for _, userID := range []int64{activeUserID, deletedUserID} {
		testutil.InsertUsage(t, db, userID, 200)
		testutil.InsertSubscription(t, db, testutil.SubscriptionFixture{UserID: userID, Storage: 100})
	}
	_, err = db.Exec(`UPDATE users SET email_hash = 'deleted+2@ente.io' WHERE user_id = $1`, deletedUserID)
	require.NoError(t, err)

	userRepo := &UserRepository{
		DB:                  pool,
		SecretEncryptionKey: testutil.SecretEncryptionKey(),
		StorageBonusRepo:    storageBonusRepo.NewRepository(pool),
	}
	users, err := userRepo.GetUsersWithIndividualPlanWhoHaveExceededStorageQuota()
	require.NoError(t, err)
	require.Equal(t, 0, pool.Stats().InUse)
	require.Len(t, users, 1)
	require.Equal(t, activeUserID, users[0].ID)
	require.Equal(t, "over@example.com", users[0].Email)

	closedDB, err := sql.Open("postgres", "sslmode=disable")
	require.NoError(t, err)
	require.NoError(t, closedDB.Close())
	failingRepo := &UserRepository{
		DB:                  pool,
		SecretEncryptionKey: testutil.SecretEncryptionKey(),
		StorageBonusRepo:    storageBonusRepo.NewRepository(closedDB),
	}
	_, err = failingRepo.GetUsersWithIndividualPlanWhoHaveExceededStorageQuota()
	require.Error(t, err)
	require.Equal(t, 0, pool.Stats().InUse)

	ctx, cancel := context.WithTimeout(t.Context(), 2*time.Second)
	defer cancel()
	require.NoError(t, pool.PingContext(ctx))
}
