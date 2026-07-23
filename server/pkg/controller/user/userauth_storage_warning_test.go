package user

import (
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/time"
	logtest "github.com/sirupsen/logrus/hooks/test"
)

func TestAlertStorageWarningDeletionScheduledLoginBlockLogsUserIDAndApp(t *testing.T) {
	hook := logtest.NewGlobal()
	t.Cleanup(hook.Reset)

	(&UserController{}).alertStorageWarningDeletionScheduledLoginBlock(123, ente.Photos)

	entry := hook.LastEntry()
	if entry == nil {
		t.Fatal("expected a log entry")
	}
	if entry.Message != "blocked login due to storage warning scheduled deletion" {
		t.Fatalf("log message = %q, want storage warning login block message", entry.Message)
	}
	if got := entry.Data["user_id"]; got != int64(123) {
		t.Fatalf("user_id field = %v, want 123", got)
	}
	if got := entry.Data["app"]; got != ente.Photos {
		t.Fatalf("app field = %v, want %s", got, ente.Photos)
	}
	if got := entry.Data["code"]; got != StorageWarningDeletionScheduledCode {
		t.Fatalf("code field = %v, want %s", got, StorageWarningDeletionScheduledCode)
	}
}

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
