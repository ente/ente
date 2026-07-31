package passkey

import (
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
)

func TestStoreTokenDataRoundTripsLegacyNULByte(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })

	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "legacy-passkey@ente.com",
		CreationTime: 1,
	})
	const sessionID = "legacy-nul-byte-session"
	if _, err := db.Exec(`
		INSERT INTO passkey_login_sessions(user_id, session_id, creation_time, expiration_time)
		VALUES ($1, $2, $3, $4)
	`, userID, sessionID, 1, 2); err != nil {
		t.Fatalf("insert passkey login session: %v", err)
	}

	repo := &Repository{DB: db}
	want := ente.TwoFactorAuthorizationResponse{
		ID: userID,
		KeyAttributes: &ente.KeyAttributes{
			KEKHash: "\x00",
		},
		EncryptedToken: "encrypted-token",
	}
	if err := repo.StoreTokenData(sessionID, want); err != nil {
		t.Fatalf("store token data: %v", err)
	}

	got, err := repo.GetTokenData(sessionID)
	if err != nil {
		t.Fatalf("get token data: %v", err)
	}
	if got.ID != want.ID || got.EncryptedToken != want.EncryptedToken {
		t.Fatalf("token data = %+v, want %+v", got, want)
	}
	if got.KeyAttributes == nil {
		t.Fatal("token data is missing key attributes")
	}
	if got.KeyAttributes.KEKHash != want.KeyAttributes.KEKHash {
		t.Fatalf("kek hash = %q, want %q", got.KeyAttributes.KEKHash, want.KeyAttributes.KEKHash)
	}
}
