package user

import (
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/time"
)

func TestEnsureStorageWarningDeletionLoginAllowedHonorsActiveLoginGrace(t *testing.T) {
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	const userID int64 = 12345
	testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       userID,
		Email:        "user@example.com",
		CreationTime: 1,
	})
	testutil.InsertNotificationHistory(t, db, testutil.NotificationHistoryFixture{
		UserID:     userID,
		TemplateID: repo.StorageWarningActiveOverageScheduledDeletionTemplateID,
		SentTime:   100,
	})
	testutil.InsertNotificationHistory(t, db, testutil.NotificationHistoryFixture{
		UserID:     userID,
		TemplateID: repo.StorageWarningLoginGraceTemplateID,
		SentTime:   time.Microseconds(),
	})

	err := (&UserController{
		NotificationHistoryRepo: &repo.NotificationHistoryRepository{DB: db},
	}).ensureStorageWarningDeletionLoginAllowed(userID, ente.Photos)
	if err != nil {
		t.Fatalf("expected active login grace to allow login, got %v", err)
	}
}

func TestEnsureStorageWarningDeletionLoginAllowedDoesNotBlockAuthApp(t *testing.T) {
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	const userID int64 = 12347
	testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       userID,
		Email:        "auth-user@example.com",
		CreationTime: 1,
	})
	testutil.InsertNotificationHistory(t, db, testutil.NotificationHistoryFixture{
		UserID:     userID,
		TemplateID: repo.StorageWarningExpiredScheduledDeletionTemplateID,
		SentTime:   100,
	})

	err := (&UserController{
		NotificationHistoryRepo: &repo.NotificationHistoryRepository{DB: db},
	}).ensureStorageWarningDeletionLoginAllowed(userID, ente.Auth)
	if err != nil {
		t.Fatalf("expected auth app login to remain allowed, got %v", err)
	}
}

func TestEnsureStorageWarningDeletionLoginAllowedBlocksAfterLoginGraceExpires(t *testing.T) {
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	const userID int64 = 12346
	testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       userID,
		Email:        "user@example.com",
		CreationTime: 1,
	})
	testutil.InsertNotificationHistory(t, db, testutil.NotificationHistoryFixture{
		UserID:     userID,
		TemplateID: repo.StorageWarningExpiredScheduledDeletionTemplateID,
		SentTime:   100,
	})
	testutil.InsertNotificationHistory(t, db, testutil.NotificationHistoryFixture{
		UserID:     userID,
		TemplateID: repo.StorageWarningLoginGraceTemplateID,
		SentTime:   200,
	})

	err := (&UserController{
		NotificationHistoryRepo: &repo.NotificationHistoryRepository{DB: db},
	}).ensureStorageWarningDeletionLoginAllowed(userID, ente.Photos)
	if err == nil {
		t.Fatal("expected expired login grace to block login")
	}
}
