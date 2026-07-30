package user

import (
	"database/sql"
	"errors"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
	stdtime "time"

	"github.com/ente/museum/ente"
	contactmodel "github.com/ente/museum/ente/contact"
	cleanupentity "github.com/ente/museum/ente/data_cleanup"
	enteJWT "github.com/ente/museum/ente/jwt"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	contactrepo "github.com/ente/museum/pkg/repo/contact"
	cleanuprepo "github.com/ente/museum/pkg/repo/datacleanup"
	"github.com/ente/museum/pkg/utils/config"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/gin-gonic/gin"
	"github.com/spf13/viper"
)

func TestGetAccountRecoveryLinkExpiresAfterSevenDays(t *testing.T) {
	viper.Reset()
	viper.Set("apps.accounts", "https://accounts.example.com/")
	t.Cleanup(viper.Reset)

	controller := &UserController{JwtSecret: []byte("test-jwt-secret")}

	before := time.Microseconds()
	recoveryLink, err := controller.getAccountRecoveryLink(42, "recover@ente.com")
	if err != nil {
		t.Fatalf("getAccountRecoveryLink() error = %v", err)
	}
	after := time.Microseconds()

	parsedLink, err := url.Parse(recoveryLink)
	if err != nil {
		t.Fatalf("failed to parse recovery link: %v", err)
	}
	if parsedLink.Scheme != "https" || parsedLink.Host != "accounts.example.com" || parsedLink.Path != "/recover-account" {
		t.Fatalf("recovery link = %q, want configured accounts recovery page", recoveryLink)
	}
	if parsedLink.RawQuery != "" {
		t.Fatalf("recovery link query = %q, want token only in fragment", parsedLink.RawQuery)
	}
	fragment, err := url.ParseQuery(parsedLink.Fragment)
	if err != nil {
		t.Fatalf("failed to parse recovery link fragment: %v", err)
	}
	claim, err := controller.ValidateJWTToken(fragment.Get("recoveryToken"), enteJWT.RestoreAccount)
	if err != nil {
		t.Fatalf("ValidateJWTToken() error = %v", err)
	}

	const sevenDays = int64(7*24) * time.MicroSecondsInOneHour
	if claim.ExpiryTime < before+sevenDays || claim.ExpiryTime > after+sevenDays {
		t.Fatalf("token expiry = %d, want approximately 7 days after issuance", claim.ExpiryTime)
	}
	if claim.UserID != 42 || claim.Email != "recover@ente.com" {
		t.Fatalf("recovery token claim = %+v, want user 42 and recover@ente.com", claim)
	}
}

func TestValidateSelfAccountRecoveryClassifiesTokenErrors(t *testing.T) {
	controller := &UserController{JwtSecret: []byte("test-jwt-secret")}
	expiredToken := accountRecoveryToken(t, controller, &enteJWT.WebCommonJWTClaim{
		UserID:     42,
		Email:      "recover@ente.com",
		ExpiryTime: time.Microseconds() - 1,
		ClaimScope: enteJWT.RestoreAccount.Ptr(),
	})
	wrongScopeToken := accountRecoveryToken(t, controller, &enteJWT.WebCommonJWTClaim{
		UserID:     42,
		Email:      "recover@ente.com",
		ExpiryTime: time.MicrosecondsAfterDays(1),
		ClaimScope: enteJWT.DELETE_ACCOUNT.Ptr(),
	})

	tests := []struct {
		name       string
		token      string
		wantError  *ente.ApiError
		wantCode   ente.ErrorCode
		wantStatus int
	}{
		{
			name:       "malformed",
			token:      "not-a-jwt",
			wantError:  ErrAccountRecoveryInvalidLink,
			wantCode:   accountRecoveryInvalidLinkCode,
			wantStatus: http.StatusBadRequest,
		},
		{
			name:       "wrong scope",
			token:      wrongScopeToken,
			wantError:  ErrAccountRecoveryInvalidLink,
			wantCode:   accountRecoveryInvalidLinkCode,
			wantStatus: http.StatusBadRequest,
		},
		{
			name:       "expired",
			token:      expiredToken,
			wantError:  ErrAccountRecoveryLinkExpired,
			wantCode:   accountRecoveryLinkExpiredCode,
			wantStatus: http.StatusGone,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			_, err := controller.ValidateSelfAccountRecovery(test.token)
			if !errors.Is(err, test.wantError) {
				t.Fatalf("ValidateSelfAccountRecovery() error = %v, want %v", err, test.wantError)
			}
			var apiErr *ente.ApiError
			if !errors.As(err, &apiErr) {
				t.Fatalf("ValidateSelfAccountRecovery() error = %v, want ApiError", err)
			}
			if apiErr.Code != test.wantCode || apiErr.HttpStatusCode != test.wantStatus {
				t.Fatalf("ApiError = %+v, want code %s and status %d", apiErr, test.wantCode, test.wantStatus)
			}
		})
	}
}

func TestSelfAccountRecoveryStatusAndRecovery(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })

	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       82,
		Email:        "recover@example.com",
		CreationTime: 1,
	})
	insertKeyAttributes(t, db, userID)
	insertScheduledDelete(t, db, userID)

	userRepo := &repo.UserRepository{
		DB:                  db,
		SecretEncryptionKey: testutil.SecretEncryptionKey(),
		HashingKey:          testutil.HashingKey(),
	}
	if err := userRepo.Delete(userID); err != nil {
		t.Fatalf("failed to delete user: %v", err)
	}
	controller := &UserController{
		UserRepo:            userRepo,
		DataCleanupRepo:     &cleanuprepo.Repository{DB: db},
		SecretEncryptionKey: testutil.SecretEncryptionKey(),
		HashingKey:          testutil.HashingKey(),
		JwtSecret:           []byte("test-jwt-secret"),
	}
	token := accountRecoveryToken(t, controller, &enteJWT.WebCommonJWTClaim{
		UserID:     userID,
		Email:      "recover@example.com",
		ExpiryTime: time.MicrosecondsAfterDays(1),
		ClaimScope: enteJWT.RestoreAccount.Ptr(),
	})

	response, err := controller.ValidateSelfAccountRecovery(token)
	if err != nil {
		t.Fatalf("ValidateSelfAccountRecovery() error = %v", err)
	}
	if response.Status != ente.AccountRecoveryReady {
		t.Fatalf("validation status = %q, want %q", response.Status, ente.AccountRecoveryReady)
	}
	if _, err := db.Exec(`UPDATE data_cleanup SET stage = $1 WHERE user_id = $2`, cleanupentity.Collection, userID); err != nil {
		t.Fatalf("failed to advance cleanup: %v", err)
	}
	if _, err := controller.ValidateSelfAccountRecovery(token); !errors.Is(err, ErrAccountRecoveryUnavailable) {
		t.Fatalf("validation after cleanup advanced error = %v, want ErrAccountRecoveryUnavailable", err)
	}
	if _, err := db.Exec(`UPDATE data_cleanup SET stage = $1 WHERE user_id = $2`, cleanupentity.Scheduled, userID); err != nil {
		t.Fatalf("failed to restore scheduled cleanup fixture: %v", err)
	}

	gin.SetMode(gin.TestMode)
	ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
	response, err = controller.RecoverSelfAccount(ctx, token)
	if err != nil {
		t.Fatalf("RecoverSelfAccount() error = %v", err)
	}
	if response.Status != ente.AccountRecoveryRecovered {
		t.Fatalf("recovery status = %q, want %q", response.Status, ente.AccountRecoveryRecovered)
	}
	if _, err := userRepo.Get(userID); err != nil {
		t.Fatalf("recovered user is not active: %v", err)
	}
	var cleanupRows int
	if err := db.QueryRow(`SELECT COUNT(*) FROM data_cleanup WHERE user_id = $1`, userID).Scan(&cleanupRows); err != nil {
		t.Fatalf("failed to count cleanup rows: %v", err)
	}
	if cleanupRows != 0 {
		t.Fatalf("cleanup row count = %d, want 0", cleanupRows)
	}

	response, err = controller.ValidateSelfAccountRecovery(token)
	if err != nil {
		t.Fatalf("ValidateSelfAccountRecovery() after recovery error = %v", err)
	}
	if response.Status != ente.AccountRecoveryRecovered {
		t.Fatalf("validation status after recovery = %q, want %q", response.Status, ente.AccountRecoveryRecovered)
	}

	err = controller.HandleAccountRecovery(ctx, ente.RecoverAccountRequest{
		UserID:  userID,
		EmailID: "recover@example.com",
	})
	var apiErr *ente.ApiError
	if !errors.As(err, &apiErr) || apiErr.Code != ente.BadRequest || apiErr.HttpStatusCode != http.StatusBadRequest {
		t.Fatalf("HandleAccountRecovery() for active account error = %v, want bad request", err)
	}
}

func TestValidateSelfAccountRecoveryReportsUnavailableAfterKeyCleanup(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })

	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       82,
		Email:        "recover@example.com",
		CreationTime: 1,
	})
	userRepo := &repo.UserRepository{
		DB:                  db,
		SecretEncryptionKey: testutil.SecretEncryptionKey(),
		HashingKey:          testutil.HashingKey(),
	}
	if err := userRepo.Delete(userID); err != nil {
		t.Fatalf("failed to delete user: %v", err)
	}
	controller := &UserController{
		UserRepo:  userRepo,
		JwtSecret: []byte("test-jwt-secret"),
	}
	token := accountRecoveryToken(t, controller, &enteJWT.WebCommonJWTClaim{
		UserID:     userID,
		Email:      "recover@example.com",
		ExpiryTime: time.MicrosecondsAfterDays(1),
		ClaimScope: enteJWT.RestoreAccount.Ptr(),
	})

	_, err := controller.ValidateSelfAccountRecovery(token)
	if !errors.Is(err, ErrAccountRecoveryUnavailable) {
		t.Fatalf("ValidateSelfAccountRecovery() error = %v, want ErrAccountRecoveryUnavailable", err)
	}
	var apiErr *ente.ApiError
	if !errors.As(err, &apiErr) || apiErr.Code != accountRecoveryUnavailableCode || apiErr.HttpStatusCode != http.StatusGone {
		t.Fatalf("ValidateSelfAccountRecovery() error = %v, want unavailable ApiError", err)
	}
}

func TestAccountRecoveryLosesRaceToCleanupStageAdvance(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })

	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       82,
		Email:        "recover@example.com",
		CreationTime: 1,
	})
	insertKeyAttributes(t, db, userID)
	insertScheduledDelete(t, db, userID)
	userRepo := &repo.UserRepository{
		DB:                  db,
		SecretEncryptionKey: testutil.SecretEncryptionKey(),
		HashingKey:          testutil.HashingKey(),
	}
	if err := userRepo.Delete(userID); err != nil {
		t.Fatalf("failed to delete user: %v", err)
	}
	controller := &UserController{
		UserRepo:            userRepo,
		DataCleanupRepo:     &cleanuprepo.Repository{DB: db},
		SecretEncryptionKey: testutil.SecretEncryptionKey(),
		HashingKey:          testutil.HashingKey(),
	}

	cleanupTx, err := db.BeginTx(t.Context(), nil)
	if err != nil {
		t.Fatalf("failed to start cleanup transaction: %v", err)
	}
	defer cleanupTx.Rollback()
	if _, err := cleanupTx.ExecContext(t.Context(),
		`UPDATE data_cleanup SET stage = $1 WHERE user_id = $2`,
		cleanupentity.Collection,
		userID,
	); err != nil {
		t.Fatalf("failed to advance cleanup: %v", err)
	}

	gin.SetMode(gin.TestMode)
	ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
	recoveryDone := make(chan error, 1)
	go func() {
		recoveryDone <- controller.HandleAccountRecovery(ctx, ente.RecoverAccountRequest{
			UserID:  userID,
			EmailID: "recover@example.com",
		})
	}()
	waitForDataCleanupRowLock(t, db)
	if err := cleanupTx.Commit(); err != nil {
		t.Fatalf("failed to commit cleanup stage advance: %v", err)
	}

	select {
	case err := <-recoveryDone:
		if !errors.Is(err, ErrAccountRecoveryUnavailable) {
			t.Fatalf("HandleAccountRecovery() error = %v, want ErrAccountRecoveryUnavailable", err)
		}
	case <-stdtime.After(2 * stdtime.Second):
		t.Fatal("account recovery did not finish after cleanup committed")
	}
	if _, err := userRepo.Get(userID); !errors.Is(err, ente.ErrUserDeleted) {
		t.Fatalf("user state after lost recovery race = %v, want deleted", err)
	}
	var stage cleanupentity.Stage
	if err := db.QueryRow(`SELECT stage FROM data_cleanup WHERE user_id = $1`, userID).Scan(&stage); err != nil {
		t.Fatalf("failed to read cleanup stage: %v", err)
	}
	if stage != cleanupentity.Collection {
		t.Fatalf("cleanup stage = %q, want %q", stage, cleanupentity.Collection)
	}
}

func waitForDataCleanupRowLock(t *testing.T, db *sql.DB) {
	t.Helper()
	deadline := stdtime.Now().Add(2 * stdtime.Second)
	for {
		var waiting bool
		err := db.QueryRow(`SELECT EXISTS(
			SELECT 1 FROM pg_stat_activity
			WHERE datname = current_database()
			  AND pid <> pg_backend_pid()
			  AND wait_event_type = 'Lock'
			  AND query LIKE '%data_cleanup%'
			  AND query LIKE '%FOR UPDATE%'
		)`).Scan(&waiting)
		if err != nil {
			t.Fatalf("failed to inspect recovery lock wait: %v", err)
		}
		if waiting {
			return
		}
		if stdtime.Now().After(deadline) {
			t.Fatal("account recovery did not wait for the cleanup row lock")
		}
		stdtime.Sleep(10 * stdtime.Millisecond)
	}
}

func accountRecoveryToken(t *testing.T, controller *UserController, claim *enteJWT.WebCommonJWTClaim) string {
	t.Helper()
	token, err := controller.GetJWTTokenForClaim(claim)
	if err != nil {
		t.Fatalf("failed to create account recovery token: %v", err)
	}
	return token
}

func TestHandleAccountRecoveryTouchesContactsForResolvedEmailSync(t *testing.T) {
	testutil.WithServerRoot(t)
	viper.Reset()
	if err := config.ConfigureViper("local"); err != nil {
		t.Fatalf("failed to configure viper: %v", err)
	}
	t.Cleanup(viper.Reset)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "owner@ente.com",
		CreationTime: 1,
	})
	contactUserID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       82,
		Email:        "before-recovery@ente.com",
		CreationTime: 1,
	})

	insertKeyAttributes(t, db, contactUserID)
	insertScheduledDelete(t, db, contactUserID)

	objectCleanupRepo := &repo.ObjectCleanupRepository{DB: db}
	contactsRepo := &contactrepo.Repository{
		DB:                  db,
		ObjectCleanupRepo:   objectCleanupRepo,
		SecretEncryptionKey: testutil.SecretEncryptionKey(),
	}
	contactID, err := contactsRepo.Create(t.Context(), ownerID, contactmodel.CreateRequest{
		ContactUserID: contactUserID,
		EncryptedKey:  []byte("wrapped-key"),
		EncryptedData: []byte("payload"),
	})
	if err != nil {
		t.Fatalf("failed to create contact: %v", err)
	}
	created, err := contactsRepo.Get(t.Context(), ownerID, contactID)
	if err != nil {
		t.Fatalf("failed to fetch created contact: %v", err)
	}
	if created.Email == nil || *created.Email != "before-recovery@ente.com" {
		t.Fatalf("unexpected initial email: %v", created.Email)
	}

	userRepo := &repo.UserRepository{
		DB:                  db,
		SecretEncryptionKey: testutil.SecretEncryptionKey(),
		HashingKey:          testutil.HashingKey(),
	}
	if err := userRepo.Delete(contactUserID); err != nil {
		t.Fatalf("failed to soft-delete contact user: %v", err)
	}

	gin.SetMode(gin.TestMode)
	recorder := httptest.NewRecorder()
	ctx, _ := gin.CreateTestContext(recorder)
	ctx.Request = httptest.NewRequest("POST", "/", nil)
	ctx.Set("req_id", "recovery-test")

	controller := &UserController{
		UserRepo:            userRepo,
		DataCleanupRepo:     &cleanuprepo.Repository{DB: db},
		ContactRepo:         contactsRepo,
		SecretEncryptionKey: testutil.SecretEncryptionKey(),
		HashingKey:          testutil.HashingKey(),
	}

	if err := controller.HandleAccountRecovery(ctx, ente.RecoverAccountRequest{
		UserID:  contactUserID,
		EmailID: "after-recovery@ente.com",
	}); err != nil {
		t.Fatalf("HandleAccountRecovery() error = %v", err)
	}

	diff, err := contactsRepo.GetDiff(t.Context(), ownerID, created.UpdatedAt, 10)
	if err != nil {
		t.Fatalf("GetDiff() error = %v", err)
	}
	if len(diff) != 1 {
		t.Fatalf("diff length = %d, want 1", len(diff))
	}
	if diff[0].Email == nil || *diff[0].Email != "after-recovery@ente.com" {
		t.Fatalf("resolved email after recovery = %v, want updated email", diff[0].Email)
	}
}

func TestHandleAccountRecoveryReportsEmailInUse(t *testing.T) {
	testutil.WithServerRoot(t)
	viper.Reset()
	if err := config.ConfigureViper("local"); err != nil {
		t.Fatalf("failed to configure viper: %v", err)
	}
	t.Cleanup(viper.Reset)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	deletedUserID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       82,
		Email:        "recover@example.com",
		CreationTime: 1,
	})
	insertKeyAttributes(t, db, deletedUserID)
	insertScheduledDelete(t, db, deletedUserID)

	userRepo := &repo.UserRepository{
		DB:                  db,
		SecretEncryptionKey: testutil.SecretEncryptionKey(),
		HashingKey:          testutil.HashingKey(),
	}
	if err := userRepo.Delete(deletedUserID); err != nil {
		t.Fatalf("failed to delete user: %v", err)
	}
	testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       83,
		Email:        "recover@example.com",
		CreationTime: 1,
	})

	gin.SetMode(gin.TestMode)
	ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
	controller := &UserController{
		UserRepo:            userRepo,
		DataCleanupRepo:     &cleanuprepo.Repository{DB: db},
		SecretEncryptionKey: testutil.SecretEncryptionKey(),
		HashingKey:          testutil.HashingKey(),
	}

	err := controller.HandleAccountRecovery(ctx, ente.RecoverAccountRequest{
		UserID:  deletedUserID,
		EmailID: "recover@example.com",
	})
	if !errors.Is(err, ErrAccountRecoveryEmailInUse) {
		t.Fatalf("HandleAccountRecovery() error = %v, want ErrAccountRecoveryEmailInUse", err)
	}
	var apiErr *ente.ApiError
	if !errors.As(err, &apiErr) || apiErr.Code != accountRecoveryEmailInUseCode || apiErr.HttpStatusCode != http.StatusConflict {
		t.Fatalf("HandleAccountRecovery() error = %v, want email-in-use ApiError", err)
	}
}

func insertKeyAttributes(t *testing.T, db *sql.DB, userID int64) {
	t.Helper()
	_, err := db.Exec(
		`INSERT INTO key_attributes(
			user_id, kek_salt, kek_hash_bytes, encrypted_key, key_decryption_nonce,
			public_key, encrypted_secret_key, secret_key_decryption_nonce, mem_limit, ops_limit
		) VALUES($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
		userID,
		"kek-salt",
		[]byte("kek-hash"),
		"encrypted-key",
		"key-nonce",
		"public-key",
		"encrypted-secret-key",
		"secret-key-nonce",
		int64(67108864),
		int64(2),
	)
	if err != nil {
		t.Fatalf("failed to insert key_attributes for user %d: %v", userID, err)
	}
}

func insertScheduledDelete(t *testing.T, db *sql.DB, userID int64) {
	t.Helper()
	t.Cleanup(func() {
		if _, err := db.Exec(`DELETE FROM data_cleanup WHERE user_id = $1`, userID); err != nil {
			t.Errorf("failed to remove data_cleanup fixture for user %d: %v", userID, err)
		}
	})
	_, err := db.Exec(
		`INSERT INTO data_cleanup(user_id, stage, stage_schedule_time, stage_attempt_count)
		 VALUES($1, $2, $3, $4)`,
		userID,
		cleanupentity.Scheduled,
		int64(1),
		0,
	)
	if err != nil {
		t.Fatalf("failed to insert scheduled delete row for user %d: %v", userID, err)
	}
}
