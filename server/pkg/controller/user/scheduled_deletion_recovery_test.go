package user

import (
	"errors"
	"net/http/httptest"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	cleanuprepo "github.com/ente/museum/pkg/repo/datacleanup"
	"github.com/ente/museum/pkg/utils/crypto"
	"github.com/gin-gonic/gin"
)

func TestMarkAccountDeletedAndScheduleCleanupIsAtomic(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		if _, err := db.Exec(`DELETE FROM data_cleanup`); err != nil {
			t.Errorf("failed to clear data_cleanup: %v", err)
		}
		testutil.ResetTables(t, db)
	})

	userRepo := &repo.UserRepository{
		DB:                  db,
		SecretEncryptionKey: testutil.SecretEncryptionKey(),
		HashingKey:          testutil.HashingKey(),
	}
	controller := &UserController{
		UserRepo:        userRepo,
		DataCleanupRepo: &cleanuprepo.Repository{DB: db},
		HashingKey:      testutil.HashingKey(),
	}

	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       91,
		Email:        "deleted@example.com",
		CreationTime: 1,
	})
	if err := controller.markAccountDeletedAndScheduleCleanup(t.Context(), userID); err != nil {
		t.Fatalf("markAccountDeletedAndScheduleCleanup() error = %v", err)
	}
	if _, err := userRepo.Get(userID); !errors.Is(err, ente.ErrUserDeleted) {
		t.Fatalf("user state after deletion = %v, want deleted", err)
	}

	expectedHash, err := crypto.GetHash("deleted@example.com", testutil.HashingKey())
	if err != nil {
		t.Fatalf("GetHash() error = %v", err)
	}
	var storedHash string
	if err := db.QueryRow(`SELECT email_hash FROM data_cleanup WHERE user_id = $1`, userID).Scan(&storedHash); err != nil {
		t.Fatalf("failed to read scheduled deletion: %v", err)
	}
	if storedHash != expectedHash {
		t.Fatalf("stored email hash = %q, want original hash", storedHash)
	}

	items, err := controller.GetScheduledDeletions(t.Context(), " DELETED@EXAMPLE.COM ")
	if err != nil {
		t.Fatalf("GetScheduledDeletions() error = %v", err)
	}
	if len(items) != 1 || items[0].UserID != userID {
		t.Fatalf("GetScheduledDeletions() = %+v, want deleted user", items)
	}

	rollbackUserID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       92,
		Email:        "rollback@example.com",
		CreationTime: 1,
	})
	if _, err := db.Exec(`INSERT INTO data_cleanup(user_id) VALUES($1)`, rollbackUserID); err != nil {
		t.Fatalf("failed to create conflicting cleanup row: %v", err)
	}
	if err := controller.markAccountDeletedAndScheduleCleanup(t.Context(), rollbackUserID); err == nil {
		t.Fatal("markAccountDeletedAndScheduleCleanup() succeeded with conflicting cleanup row")
	}
	if _, err := userRepo.Get(rollbackUserID); err != nil {
		t.Fatalf("user was left deleted after cleanup insert failed: %v", err)
	}
}

func TestAccountRecoveryVerifiesScheduledEmailHash(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		if _, err := db.Exec(`DELETE FROM data_cleanup`); err != nil {
			t.Errorf("failed to clear data_cleanup: %v", err)
		}
		testutil.ResetTables(t, db)
	})

	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       82,
		Email:        "recover@example.com",
		CreationTime: 1,
	})
	insertKeyAttributes(t, db, userID)
	insertScheduledDelete(t, db, userID)

	mismatchedHash, err := crypto.GetHash("different@example.com", testutil.HashingKey())
	if err != nil {
		t.Fatalf("GetHash() error = %v", err)
	}
	if _, err := db.Exec(`UPDATE data_cleanup SET email_hash = $1 WHERE user_id = $2`, mismatchedHash, userID); err != nil {
		t.Fatalf("failed to set scheduled email hash: %v", err)
	}

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
	gin.SetMode(gin.TestMode)
	ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
	request := ente.RecoverAccountRequest{UserID: userID, EmailID: "recover@example.com"}

	if err := controller.HandleAccountRecovery(ctx, request); !errors.Is(err, ErrAccountRecoveryUnavailable) {
		t.Fatalf("HandleAccountRecovery() mismatch error = %v, want ErrAccountRecoveryUnavailable", err)
	}
	if _, err := userRepo.Get(userID); !errors.Is(err, ente.ErrUserDeleted) {
		t.Fatalf("user state after mismatched recovery = %v, want deleted", err)
	}

	matchingHash, err := crypto.GetHash(request.EmailID, testutil.HashingKey())
	if err != nil {
		t.Fatalf("GetHash() error = %v", err)
	}
	if _, err := db.Exec(`UPDATE data_cleanup SET email_hash = $1 WHERE user_id = $2`, matchingHash, userID); err != nil {
		t.Fatalf("failed to replace scheduled email hash: %v", err)
	}
	if err := controller.HandleAccountRecovery(ctx, request); err != nil {
		t.Fatalf("HandleAccountRecovery() with matching hash error = %v", err)
	}
	if _, err := userRepo.Get(userID); err != nil {
		t.Fatalf("user was not recovered with matching hash: %v", err)
	}
}
