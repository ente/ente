package repo

import (
	"testing"

	"github.com/ente/museum/internal/testutil"
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
