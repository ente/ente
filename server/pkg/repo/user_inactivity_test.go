package repo

import (
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
)

func TestUserInactivityUsesLatestActivityAcrossSources(t *testing.T) {
	testutil.WithServerRoot(t)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	beforeTime := int64(1_000_000)
	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "active-user@ente.com",
		CreationTime: beforeTime - 300,
	})

	_, err := db.Exec(
		`INSERT INTO tokens(user_id, token, creation_time, last_used_at, app)
		 VALUES($1, $2, $3, $4, $5)`,
		userID,
		"stale-token",
		beforeTime-200,
		beforeTime-100,
		ente.Photos,
	)
	if err != nil {
		t.Fatalf("failed to insert stale token: %v", err)
	}

	lastCollectionActivity := beforeTime + 100
	_, err = db.Exec(
		`INSERT INTO collections(owner_id, encrypted_key, key_decryption_nonce, name, type, attributes, updation_time, app)
		 VALUES($1, $2, $3, $4, $5, $6::jsonb, $7, $8)`,
		userID,
		"encrypted-key",
		"key-nonce",
		"Recent collection",
		"album",
		"{}",
		lastCollectionActivity,
		ente.Photos,
	)
	if err != nil {
		t.Fatalf("failed to insert collection: %v", err)
	}

	userRepo := &UserRepository{DB: db}
	lastActivity, found, err := userRepo.GetLatestActivity(userID)
	if err != nil {
		t.Fatalf("failed to get latest activity: %v", err)
	}
	if !found {
		t.Fatal("expected active user to be found")
	}
	if lastActivity != lastCollectionActivity {
		t.Fatalf("unexpected latest activity: got %d want %d", lastActivity, lastCollectionActivity)
	}

	candidates, err := userRepo.GetActiveUsersByLastActivityBefore(beforeTime, 0, 10)
	if err != nil {
		t.Fatalf("failed to get inactive candidates: %v", err)
	}
	if len(candidates) != 0 {
		t.Fatalf("expected recent collection activity to exclude user, got %+v", candidates)
	}
}
