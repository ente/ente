package repo

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"errors"
	"fmt"
	"testing"
	gotime "time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/google/uuid"
	"github.com/lib/pq"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestTokenHashTrigger(t *testing.T) {
	testutil.WithServerRoot(t)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })

	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		Email:        "token-hash@example.com",
		CreationTime: 1,
	})
	rawToken := "existing-bearer-token-π"
	var storedToken sql.NullString
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
	if storedToken.Valid {
		t.Fatalf("raw token was stored: %q", storedToken.String)
	}
	if !bytes.Equal(storedHash, expectedHash[:]) {
		t.Fatalf("unexpected token hash: got %x want %x", storedHash, expectedHash)
	}

	rawToken = "updated-bearer-token"
	if err := db.QueryRow(
		`UPDATE tokens SET token = $1 WHERE user_id = $2 RETURNING token, token_hash`, rawToken, userID,
	).Scan(&storedToken, &storedHash); err != nil {
		t.Fatalf("failed to update token: %v", err)
	}
	if storedToken.Valid {
		t.Fatalf("updated raw token was stored: %q", storedToken.String)
	}
	expectedHash = sha256.Sum256([]byte(rawToken))
	if !bytes.Equal(storedHash, expectedHash[:]) {
		t.Fatalf("unexpected updated token hash: got %x want %x", storedHash, expectedHash)
	}

	explicitHash := sha256.Sum256([]byte("explicit-token-hash"))
	err = db.QueryRow(
		`INSERT INTO tokens(user_id, token_hash, creation_time, last_used_at, app)
		 VALUES($1, $2, $3, $4, $5)
		 RETURNING token, token_hash`,
		userID, explicitHash[:], 2, 2, ente.Photos,
	).Scan(&storedToken, &storedHash)
	if err != nil {
		t.Fatalf("failed to insert explicit token hash: %v", err)
	}
	if storedToken.Valid || !bytes.Equal(storedHash, explicitHash[:]) {
		t.Fatalf("explicit token hash changed: token=%q hash=%x", storedToken.String, storedHash)
	}
	if err := db.QueryRow(
		`UPDATE tokens SET token = NULL WHERE token_hash = $1 RETURNING token_hash`, explicitHash[:],
	).Scan(&storedHash); err != nil {
		t.Fatalf("failed to clear token: %v", err)
	}
	if !bytes.Equal(storedHash, explicitHash[:]) {
		t.Fatalf("clearing token changed hash: got %x want %x", storedHash, explicitHash)
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

func TestAddTokenForPendingLoginConsumesPasskeyRecoverySession(t *testing.T) {
	testutil.WithServerRoot(t)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })

	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		Email:        "passkey-recovery@example.com",
		CreationTime: 1,
	})
	sessionID := "passkey-recovery-session"
	if _, err := db.Exec(`INSERT INTO passkey_login_sessions(user_id, session_id, creation_time, expiration_time) VALUES($1, $2, $3, $4)`, userID, sessionID, 1, time.Microseconds()+1000000); err != nil {
		t.Fatalf("failed to insert session: %v", err)
	}

	repo := &UserAuthRepository{DB: db}
	if err := repo.AddTokenForPendingLogin(context.Background(), userID, sessionID, PasskeyPendingLogin, false, ente.Photos, "first-token", "", "", nil); err != nil {
		t.Fatalf("first recovery failed: %v", err)
	}
	if err := repo.AddTokenForPendingLogin(context.Background(), userID, sessionID, PasskeyPendingLogin, false, ente.Photos, "second-token", "", "", nil); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("replayed recovery returned %v, want no rows", err)
	}
}

func TestAddLoginResultRejectsInvalidatedCredentials(t *testing.T) {
	testutil.WithServerRoot(t)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })

	userID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "stale-login@example.com", CreationTime: 1})
	keyAttributes := ente.KeyAttributes{
		KEKSalt: "old-salt", EncryptedKey: "old-key", KeyDecryptionNonce: "old-nonce",
		PublicKey: "public-key", EncryptedSecretKey: "secret-key", SecretKeyDecryptionNonce: "secret-nonce",
		MemLimit: 1, OpsLimit: 1,
	}
	if err := (&UserRepository{DB: db}).SetKeyAttributes(userID, keyAttributes); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO srp_auth(user_id, srp_user_id, salt, verifier) VALUES($1, '00000000-0000-0000-0000-000000000001', 'old-srp-salt', 'old-verifier')`, userID); err != nil {
		t.Fatal(err)
	}
	repo := &UserAuthRepository{DB: db}
	srpAuth, err := repo.GetSRPAuthEntity(context.Background(), userID)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`UPDATE key_attributes SET encrypted_key = 'new-key' WHERE user_id = $1`, userID); err != nil {
		t.Fatal(err)
	}

	err = repo.AddLoginResult(context.Background(), userID, srpAuth, &keyAttributes, ente.Photos, "token", "", "", "", "", 0)
	if !errors.Is(err, ente.ErrAuthenticationRequired) {
		t.Fatalf("stale key attributes returned %v", err)
	}
	if _, err = db.Exec(`UPDATE key_attributes SET encrypted_key = 'old-key' WHERE user_id = $1`, userID); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(`UPDATE srp_auth SET verifier = 'new-verifier' WHERE user_id = $1`, userID); err != nil {
		t.Fatal(err)
	}
	err = repo.AddLoginResult(context.Background(), userID, srpAuth, &keyAttributes, ente.Photos, "token", "", "", "", "", 0)
	if !errors.Is(err, ente.ErrInvalidPassword) {
		t.Fatalf("stale SRP returned %v", err)
	}
	var tokenCount int
	if err := db.QueryRow(`SELECT COUNT(*) FROM tokens WHERE user_id = $1`, userID).Scan(&tokenCount); err != nil || tokenCount != 0 {
		t.Fatalf("token count = %d, err = %v", tokenCount, err)
	}
	require.NoError(t, (&UserRepository{DB: db}).Delete(userID))
	err = repo.AddLoginResult(context.Background(), userID, srpAuth, &keyAttributes, ente.Photos, "token", "", "", "", "", 0)
	require.ErrorIs(t, err, ente.ErrUserDeleted)
}

func TestPasswordUpdateRollsBackRecoveryAuthorization(t *testing.T) {
	testutil.WithServerRoot(t)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })

	userID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "recovery-rollback@example.com", CreationTime: 1})
	contactID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "recovery-contact@example.com", CreationTime: 1})
	require.NoError(t, (&UserRepository{DB: db}).SetKeyAttributes(userID, ente.KeyAttributes{
		KEKSalt: "old-salt", EncryptedKey: "old-key", KeyDecryptionNonce: "old-nonce",
		PublicKey: "public-key", EncryptedSecretKey: "secret-key", SecretKeyDecryptionNonce: "secret-nonce",
		MemLimit: 1, OpsLimit: 1,
	}))
	oldSRPUserID, recoveryID := uuid.New(), uuid.New()
	tokenHash := sha256.Sum256([]byte("auth-token"))
	browserTokenHash := []byte("space-token")
	_, err := db.Exec(`INSERT INTO srp_auth(user_id, srp_user_id, salt, verifier) VALUES($1, $2, 'old-srp-salt', 'old-verifier')`, userID, oldSRPUserID)
	require.NoError(t, err)
	_, err = db.Exec(`INSERT INTO tokens(user_id, token_hash, creation_time, app) VALUES($1, $2, 1, $3)`, userID, tokenHash[:], ente.Photos)
	require.NoError(t, err)
	_, err = db.Exec(`INSERT INTO emergency_recovery(id, user_id, emergency_contact_id, status) VALUES($1, $2, $3, $4)`, recoveryID, userID, contactID, ente.RecoveryStatusReady)
	require.NoError(t, err)
	_, err = db.Exec(`INSERT INTO space_browser_sessions(token_hash, user_id, session_wrap_key, expires_at) VALUES($1, $2, 'wrap-key', 1)`, browserTokenHash, userID)
	require.NoError(t, err)

	authorizationErr := errors.New("authorization failed")
	_, err = (&UserAuthRepository{DB: db}).InsertOrUpdateSRPAuthAndKeyAttr(t.Context(), userID,
		ente.UpdateKeysRequest{KEKSalt: "new-salt", EncryptedKey: "new-key", KeyDecryptionNonce: "new-nonce", MemLimit: 2, OpsLimit: 2},
		&ente.SRPSetupEntity{SRPUserID: uuid.New(), Salt: "new-srp-salt", Verifier: "new-verifier"}, true, nil, false,
		func(ctx context.Context, tx *sql.Tx) error {
			if _, err := tx.ExecContext(ctx, `UPDATE emergency_recovery SET status=$1 WHERE id=$2`, ente.RecoveryStatusRecovered, recoveryID); err != nil {
				return err
			}
			if _, err := tx.ExecContext(ctx, `DELETE FROM space_browser_sessions WHERE user_id=$1`, userID); err != nil {
				return err
			}
			return authorizationErr
		})
	require.ErrorIs(t, err, authorizationErr)

	var unchanged bool
	require.NoError(t, db.QueryRow(`SELECT
		EXISTS (SELECT FROM srp_auth WHERE user_id=$1 AND srp_user_id=$2 AND salt='old-srp-salt' AND verifier='old-verifier') AND
		EXISTS (SELECT FROM key_attributes WHERE user_id=$1 AND kek_salt='old-salt' AND encrypted_key='old-key' AND key_decryption_nonce='old-nonce' AND mem_limit=1 AND ops_limit=1) AND
		EXISTS (SELECT FROM tokens WHERE user_id=$1 AND token_hash=$3 AND is_deleted=FALSE) AND
		EXISTS (SELECT FROM emergency_recovery WHERE id=$4 AND status=$5) AND
		EXISTS (SELECT FROM space_browser_sessions WHERE token_hash=$6 AND user_id=$1)`,
		userID, oldSRPUserID, tokenHash[:], recoveryID, ente.RecoveryStatusReady, browserTokenHash).Scan(&unchanged))
	require.True(t, unchanged)
}

func TestPushTokensRemovedOnSessionRevocation(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	for _, tc := range []struct {
		name      string
		remaining []string
	}{
		{"session", []string{"other", "locker", "other-account"}},
		{"other sessions", []string{"current", "rotated", "other-account"}},
		{"apps", []string{"locker", "other-account"}},
		{"wrong user", []string{"current", "rotated", "other", "locker", "other-account"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			testutil.ResetTables(t, db)
			t.Cleanup(func() { testutil.ResetTables(t, db) })
			for _, id := range []int64{1, 2} {
				testutil.InsertUser(t, db, testutil.UserFixture{UserID: id, Email: fmt.Sprintf("user%d@example.com", id), CreationTime: 1})
			}
			r := &UserAuthRepository{DB: db}
			for _, session := range []struct {
				token  string
				userID int64
				app    ente.App
			}{
				{"current", 1, ente.Photos}, {"other", 1, ente.Photos},
				{"locker", 1, ente.Locker}, {"other-account", 2, ente.Photos},
			} {
				require.NoError(t, r.AddToken(session.userID, session.app, session.token, "", ""))
				hash := sha256.Sum256([]byte(session.token))
				_, err := db.Exec(`INSERT INTO push_tokens(user_id, fcm_token, session_token_hash) VALUES($1, $2, $3)`, session.userID, session.token, hash[:])
				require.NoError(t, err)
			}
			currentHash := sha256.Sum256([]byte("current"))
			_, err := db.Exec(`INSERT INTO push_tokens(user_id, fcm_token, session_token_hash) VALUES(1, 'rotated', $1)`, currentHash[:])
			require.NoError(t, err)
			var revoked []RevokedToken
			switch tc.name {
			case "session":
				revoked, err = r.RemoveTokenByHash(1, currentHash[:])
			case "other sessions":
				revoked, err = r.RemoveAllOtherTokensByHash(1, currentHash[:])
			case "apps":
				revoked, err = r.RemoveTokensForApps(1, []ente.App{ente.Photos})
			case "wrong user":
				revoked, err = r.RemoveTokenByHash(2, currentHash[:])
			}
			require.NoError(t, err)
			for _, session := range revoked {
				var deleted bool
				require.NoError(t, db.QueryRow(`SELECT is_deleted FROM tokens WHERE token_hash = $1`, session.TokenHash).Scan(&deleted))
				require.True(t, deleted)
			}
			var remaining pq.StringArray
			require.NoError(t, db.QueryRow(`SELECT ARRAY(SELECT fcm_token FROM push_tokens)`).Scan(&remaining))
			require.ElementsMatch(t, tc.remaining, []string(remaining))
		})
	}
}

func TestPushTokenCleanupFailureRollsBackSessionRevocation(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	userID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "rollback@example.com", CreationTime: 1})
	r := &UserAuthRepository{DB: db}
	require.NoError(t, r.AddToken(userID, ente.Photos, "session", "", ""))
	hash := sha256.Sum256([]byte("session"))
	_, err := db.Exec(`INSERT INTO push_tokens(user_id, fcm_token, session_token_hash) VALUES($1, 'device', $2)`, userID, hash[:])
	require.NoError(t, err)
	_, err = db.Exec(`CREATE FUNCTION fail_push_cleanup() RETURNS trigger LANGUAGE plpgsql AS $$
		BEGIN RAISE EXCEPTION 'push cleanup failed'; END;
		$$;
		CREATE TRIGGER fail_push_cleanup BEFORE DELETE ON push_tokens
		FOR EACH ROW EXECUTE FUNCTION fail_push_cleanup()`)
	require.NoError(t, err)
	t.Cleanup(func() {
		_, err := db.Exec(`DROP TRIGGER fail_push_cleanup ON push_tokens; DROP FUNCTION fail_push_cleanup()`)
		require.NoError(t, err)
	})
	_, err = r.RemoveTokenByHash(userID, hash[:])
	require.ErrorContains(t, err, "push cleanup failed")
	var deleted bool
	require.NoError(t, db.QueryRow(`SELECT is_deleted FROM tokens WHERE token_hash = $1`, hash[:]).Scan(&deleted))
	require.False(t, deleted)
	var count int
	require.NoError(t, db.QueryRow(`SELECT count(*) FROM push_tokens WHERE fcm_token = 'device'`).Scan(&count))
	require.Equal(t, 1, count)
}

func TestSessionRevocationDeletesConcurrentPushRegistration(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	userID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "concurrent@example.com", CreationTime: 1})
	r := &UserAuthRepository{DB: db}
	require.NoError(t, r.AddToken(userID, ente.Photos, "session", "", ""))
	hash := sha256.Sum256([]byte("session"))
	registration, err := db.Begin()
	require.NoError(t, err)
	defer registration.Rollback()
	var sessionUserID int64
	require.NoError(t, registration.QueryRow(`SELECT user_id FROM tokens WHERE token_hash = $1 FOR SHARE`, hash[:]).Scan(&sessionUserID))
	_, err = registration.Exec(`INSERT INTO push_tokens(user_id, fcm_token, session_token_hash) VALUES($1, 'device', $2)`, userID, hash[:])
	require.NoError(t, err)
	var pid int
	require.NoError(t, registration.QueryRow(`SELECT pg_backend_pid()`).Scan(&pid))
	done := make(chan error, 1)
	go func() {
		_, err := r.RemoveTokenByHash(userID, hash[:])
		done <- err
	}()
	require.EventuallyWithT(t, func(collect *assert.CollectT) {
		var blocked bool
		require.NoError(collect, db.QueryRow(`SELECT EXISTS(SELECT 1 FROM pg_stat_activity
			WHERE datname = current_database() AND $1 = ANY(pg_blocking_pids(pid)))`, pid).Scan(&blocked))
		require.True(collect, blocked)
	}, 5*gotime.Second, 10*gotime.Millisecond)
	require.NoError(t, registration.Commit())
	select {
	case err := <-done:
		require.NoError(t, err)
	case <-gotime.After(5 * gotime.Second):
		t.Fatal("session revocation did not finish")
	}
	var count int
	require.NoError(t, db.QueryRow(`SELECT count(*) FROM push_tokens`).Scan(&count))
	require.Zero(t, count)
}
