package repo

import (
	"bytes"
	"crypto/sha256"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/utils/time"
)

func TestTokenHashCompatibilityTrigger(t *testing.T) {
	testutil.WithServerRoot(t)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })

	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		Email:        "token-hash@example.com",
		CreationTime: 1,
	})
	rawToken := "existing-bearer-token"
	var storedToken string
	var storedHash []byte
	err := db.QueryRow(
		`INSERT INTO tokens(user_id, token, token_hash, creation_time, last_used_at, app)
		 VALUES($1, $2, $3, $4, $5, $6)
		 RETURNING token, token_hash`,
		userID, rawToken, bytes.Repeat([]byte{0xff}, sha256.Size), 1, 1, ente.Photos,
	).Scan(&storedToken, &storedHash)
	if err != nil {
		t.Fatalf("failed to insert token: %v", err)
	}

	expectedHash := sha256.Sum256([]byte(rawToken))
	if storedToken != rawToken {
		t.Fatalf("raw token changed: got %q want %q", storedToken, rawToken)
	}
	if !bytes.Equal(storedHash, expectedHash[:]) {
		t.Fatalf("unexpected token hash: got %x want %x", storedHash, expectedHash)
	}

	rawToken = "updated-bearer-token"
	if err := db.QueryRow(
		`UPDATE tokens SET token = $1 WHERE user_id = $2 RETURNING token_hash`, rawToken, userID,
	).Scan(&storedHash); err != nil {
		t.Fatalf("failed to update token: %v", err)
	}
	expectedHash = sha256.Sum256([]byte(rawToken))
	if !bytes.Equal(storedHash, expectedHash[:]) {
		t.Fatalf("unexpected updated token hash: got %x want %x", storedHash, expectedHash)
	}
}

func TestUserAuthRepositoryRemoveOTTReturnsWhetherRowWasConsumed(t *testing.T) {
	testutil.WithServerRoot(t)

	db := testutil.RequireTestDB(t)
	if _, err := db.Exec(`TRUNCATE TABLE otts RESTART IDENTITY CASCADE`); err != nil {
		t.Fatalf("failed to reset otts: %v", err)
	}
	t.Cleanup(func() {
		if _, err := db.Exec(`TRUNCATE TABLE otts RESTART IDENTITY CASCADE`); err != nil {
			t.Errorf("failed to reset otts: %v", err)
		}
	})

	repo := &UserAuthRepository{DB: db}
	emailHash := "duplicate-verify-email-hash"
	ott := "123456"
	app := ente.Photos

	err := repo.AddOTT(emailHash, app, ott, time.Microseconds()+60*1000000)
	if err != nil {
		t.Fatalf("failed to add ott: %v", err)
	}

	removed, err := repo.RemoveOTT(emailHash, ott, app)
	if err != nil {
		t.Fatalf("first remove returned error: %v", err)
	}
	if !removed {
		t.Fatal("first remove should consume the ott")
	}

	removed, err = repo.RemoveOTT(emailHash, ott, app)
	if err != nil {
		t.Fatalf("second remove returned error: %v", err)
	}
	if removed {
		t.Fatal("second remove should report that the ott was already consumed")
	}
}
