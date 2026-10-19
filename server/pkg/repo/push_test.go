package repo

import (
	"context"
	"crypto/sha256"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestPushTokenRegistrationMigration(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	tx, err := db.Begin()
	require.NoError(t, err)
	defer tx.Rollback()
	_, err = tx.Exec(`CREATE TEMP TABLE push_tokens (fcm_token TEXT, apns_token TEXT) ON COMMIT DROP;
		INSERT INTO push_tokens VALUES ('with-apns', 'apns'), ('without-apns', '');`)
	require.NoError(t, err)
	up, err := os.ReadFile("migrations/149_push_token_registration.up.sql")
	require.NoError(t, err)
	_, err = tx.Exec(string(up))
	require.NoError(t, err)
	_, err = tx.Exec(`INSERT INTO push_tokens (fcm_token) VALUES ('old-server')`)
	require.NoError(t, err)
	var count int
	require.NoError(t, tx.QueryRow(`SELECT count(*) FROM push_tokens WHERE session_token_hash IS NULL`).Scan(&count))
	require.Equal(t, 3, count)
	down, err := os.ReadFile("migrations/149_push_token_registration.down.sql")
	require.NoError(t, err)
	_, err = tx.Exec(string(down))
	require.NoError(t, err)
	require.NoError(t, tx.QueryRow(`SELECT count(*) FROM push_tokens`).Scan(&count))
	require.Equal(t, 3, count)
}

func TestPeriodicPushExcludesRevokedSessions(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	for _, id := range []int64{1, 2} {
		testutil.InsertUser(t, db, testutil.UserFixture{UserID: id, Email: fmt.Sprintf("user%d@example.com", id), CreationTime: 1})
	}
	authRepo := &UserAuthRepository{DB: db}
	for _, session := range []struct {
		token  string
		userID int64
	}{
		{"active", 1}, {"revoked", 1}, {"other-user", 2},
	} {
		require.NoError(t, authRepo.AddToken(session.userID, ente.Photos, session.token, "", ""))
	}
	revokedHash := sha256.Sum256([]byte("revoked"))
	_, err := authRepo.RemoveTokenByHash(1, revokedHash[:])
	require.NoError(t, err)
	for _, token := range []string{"active", "revoked", "other-user", "missing"} {
		hash := sha256.Sum256([]byte(token))
		_, err := db.Exec(`INSERT INTO push_tokens(user_id, fcm_token, session_token_hash, last_notified_at) VALUES(1, $1, $2, 0)`, token, hash[:])
		require.NoError(t, err)
	}
	_, err = db.Exec(`INSERT INTO push_tokens(user_id, fcm_token, last_notified_at) VALUES(1, 'legacy', 0), (1, 'recent', 1)`)
	require.NoError(t, err)
	r := &PushTokenRepository{DB: db}
	tokens, err := r.GetTokensToBeNotified(1, 2)
	require.NoError(t, err)
	var fcmTokens []string
	for _, token := range tokens {
		fcmTokens = append(fcmTokens, token.FCMToken)
	}
	require.ElementsMatch(t, []string{"active", "legacy"}, fcmTokens)
}

func TestPushRegistrationRejectsRevokedSessionAfterAccountSwitch(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	authRepo := &UserAuthRepository{DB: db}
	pushRepo := &PushTokenRepository{DB: db}
	for _, id := range []int64{1, 2} {
		testutil.InsertUser(t, db, testutil.UserFixture{UserID: id, Email: fmt.Sprintf("user%d@example.com", id), CreationTime: 1})
		require.NoError(t, authRepo.AddToken(id, ente.Photos, fmt.Sprint(id), "", ""))
	}
	oldHash, newHash := sha256.Sum256([]byte("1")), sha256.Sum256([]byte("2"))
	platform := "ios"
	request := ente.PushTokenRequest{FCMToken: "device", Platform: &platform}
	require.NoError(t, pushRepo.AddToken(1, oldHash[:], request))
	_, err := authRepo.RemoveTokenByHash(1, oldHash[:])
	require.NoError(t, err)
	var count int
	require.NoError(t, db.QueryRow(`SELECT count(*) FROM push_tokens`).Scan(&count))
	require.Zero(t, count)
	require.NoError(t, pushRepo.AddToken(2, newHash[:], request))
	for _, tc := range []struct {
		name   string
		userID int64
		hash   []byte
	}{
		{"revoked", 1, oldHash[:]}, {"wrong owner", 1, newHash[:]}, {"missing", 1, nil},
	} {
		t.Run(tc.name, func(t *testing.T) {
			require.ErrorIs(t, pushRepo.AddToken(tc.userID, tc.hash, request), ente.ErrAuthenticationRequired)
			var owner int64
			var hash []byte
			require.NoError(t, db.QueryRow(`SELECT user_id, session_token_hash FROM push_tokens WHERE fcm_token = 'device'`).Scan(&owner, &hash))
			require.Equal(t, int64(2), owner)
			require.Equal(t, newHash[:], hash)
		})
	}
}

func TestPushRegistrationWaitsForSessionRevocation(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	userID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "registration-race@example.com", CreationTime: 1})
	require.NoError(t, (&UserAuthRepository{DB: db}).AddToken(userID, ente.Photos, "session", "", ""))
	hash := sha256.Sum256([]byte("session"))
	revocation, err := db.Begin()
	require.NoError(t, err)
	defer revocation.Rollback()
	_, err = revocation.Exec(`UPDATE tokens SET is_deleted = true WHERE token_hash = $1`, hash[:])
	require.NoError(t, err)
	var pid int
	require.NoError(t, revocation.QueryRow(`SELECT pg_backend_pid()`).Scan(&pid))
	platform := "ios"
	done := make(chan error, 1)
	go func() {
		done <- (&PushTokenRepository{DB: db}).AddToken(userID, hash[:], ente.PushTokenRequest{FCMToken: "device", Platform: &platform})
	}()
	require.EventuallyWithT(t, func(collect *assert.CollectT) {
		var blocked bool
		require.NoError(collect, db.QueryRow(`SELECT EXISTS(SELECT 1 FROM pg_stat_activity
			WHERE datname = current_database() AND $1 = ANY(pg_blocking_pids(pid)))`, pid).Scan(&blocked))
		require.True(collect, blocked)
	}, 5*time.Second, 10*time.Millisecond)
	require.NoError(t, revocation.Commit())
	select {
	case err := <-done:
		require.ErrorIs(t, err, ente.ErrAuthenticationRequired)
	case <-time.After(5 * time.Second):
		t.Fatal("push registration did not finish")
	}
	var count int
	require.NoError(t, db.QueryRow(`SELECT count(*) FROM push_tokens`).Scan(&count))
	require.Zero(t, count)
}

func TestPushPlatformRegistrationMigration(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	tx, err := db.Begin()
	require.NoError(t, err)
	defer tx.Rollback()
	_, err = tx.Exec(`CREATE TEMP TABLE push_tokens (fcm_token TEXT) ON COMMIT DROP;
		INSERT INTO push_tokens VALUES ('legacy')`)
	require.NoError(t, err)
	up, err := os.ReadFile("migrations/151_push_notification_registration.up.sql")
	require.NoError(t, err)
	_, err = tx.Exec(string(up))
	require.NoError(t, err)
	_, err = tx.Exec(`INSERT INTO push_tokens (fcm_token) VALUES ('old-server')`)
	require.NoError(t, err)
	var count int
	require.NoError(t, tx.QueryRow(`SELECT count(*) FROM push_tokens WHERE platform='ios'`).Scan(&count))
	require.Equal(t, 2, count)
	down, err := os.ReadFile("migrations/151_push_notification_registration.down.sql")
	require.NoError(t, err)
	_, err = tx.Exec(string(down))
	require.NoError(t, err)
	require.NoError(t, tx.QueryRow(`SELECT count(*) FROM push_tokens`).Scan(&count))
	require.Equal(t, 2, count)
}

func TestAlbumShareTokensRequireInternalAndActiveSession(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	var userIDs []int64
	for id, tc := range []struct {
		name, platform, flag, session string
		app                           ente.App
	}{
		{"eligible", "android", "true", "active", ente.Photos},
		{"ios", "ios", "true", "active", ente.Photos},
		{"non-internal", "android", "false", "active", ente.Photos},
		{"missing flag", "android", "", "active", ente.Photos},
		{"legacy", "android", "true", "missing", ente.Photos},
		{"revoked", "android", "true", "revoked", ente.Photos},
		{"wrong owner", "android", "true", "wrong owner", ente.Photos},
		{"other app", "android", "true", "active", ente.Locker},
	} {
		userID := int64(id + 1)
		userIDs = append(userIDs, userID)
		testutil.InsertUser(t, db, testutil.UserFixture{UserID: userID, Email: fmt.Sprintf("user%d@example.com", userID), CreationTime: 1})
		hash := sha256.Sum256([]byte(tc.name))
		var sessionHash []byte
		if tc.session != "missing" {
			require.NoError(t, (&UserAuthRepository{DB: db}).AddToken(userID, tc.app, tc.name, "", ""))
			sessionHash = hash[:]
		}
		if tc.session == "revoked" {
			_, err := db.Exec(`UPDATE tokens SET is_deleted=true WHERE token_hash=$1`, hash[:])
			require.NoError(t, err)
		}
		if tc.session == "wrong owner" {
			hash = sha256.Sum256([]byte("eligible"))
			sessionHash = hash[:]
		}
		_, err := db.Exec(`INSERT INTO push_tokens(user_id,fcm_token,apns_token,platform,session_token_hash,last_notified_at)
			VALUES($1,$2,'apns',$3,$4,0)`, userID, tc.name, tc.platform, sessionHash)
		require.NoError(t, err)
		if tc.flag != "" {
			_, err = db.Exec(`INSERT INTO remote_store(user_id,key_name,key_value) VALUES($1,'internalUser',$2)`, userID, tc.flag)
			require.NoError(t, err)
		}
	}
	r := &PushTokenRepository{DB: db}
	tokens, err := r.GetTokensForAlbumShare(context.Background(), userIDs)
	require.NoError(t, err)
	var selected []string
	for _, token := range tokens {
		selected = append(selected, token.FCMToken)
	}
	require.Equal(t, []string{"eligible"}, selected)
	for _, apnsToken := range []any{"", nil} {
		_, err := db.Exec(`UPDATE push_tokens SET apns_token=$1 WHERE fcm_token='eligible'`, apnsToken)
		require.NoError(t, err)
		tokens, err := r.GetTokensForAlbumShare(context.Background(), []int64{1})
		require.NoError(t, err)
		require.Len(t, tokens, 1)
		require.Equal(t, "eligible", tokens[0].FCMToken)
	}
	tokens, err = r.GetTokensToBeNotified(1, 100)
	require.NoError(t, err)
	require.Len(t, tokens, 1)
	require.Equal(t, "ios", tokens[0].FCMToken)
	_, err = db.Exec(`UPDATE remote_store SET key_value='false' WHERE user_id=1`)
	require.NoError(t, err)
	tokens, err = r.GetTokensForAlbumShare(context.Background(), []int64{1})
	require.NoError(t, err)
	require.Empty(t, tokens)
}
