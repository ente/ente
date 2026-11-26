package repo

import (
	"context"
	"database/sql"
	"testing"
	"time"

	"github.com/ente/museum/internal/testutil"
	"github.com/stretchr/testify/require"
)

func TestUpdateTransactionIDOnDeletionDoesNotLeakConnections(t *testing.T) {
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })

	pool, err := sql.Open("postgres", "sslmode=disable")
	require.NoError(t, err)
	pool.SetMaxOpenConns(1)
	t.Cleanup(func() { _ = pool.Close() })

	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "billing-delete@example.com",
		CreationTime: 1,
	})
	testutil.InsertSubscription(t, db, testutil.SubscriptionFixture{
		UserID:                userID,
		Storage:               100,
		OriginalTransactionID: "txn-1",
	})

	billingRepo := &BillingRepository{DB: pool}
	require.NoError(t, billingRepo.UpdateTransactionIDOnDeletion(userID))
	require.Equal(t, 0, pool.Stats().InUse)

	ctx, cancel := context.WithTimeout(t.Context(), 2*time.Second)
	defer cancel()
	var transactionID string
	require.NoError(t, pool.QueryRowContext(
		ctx,
		`SELECT original_transaction_id FROM subscriptions WHERE user_id = $1`,
		userID,
	).Scan(&transactionID))
	require.Equal(t, "1:txn-1", transactionID)
}
