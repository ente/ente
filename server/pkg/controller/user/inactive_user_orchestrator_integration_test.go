package user

import (
	"database/sql"
	"testing"

	"github.com/ente/museum/internal/testutil"
	museumController "github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/controller/lock"
	"github.com/ente/museum/pkg/repo"
	storageBonusRepo "github.com/ente/museum/pkg/repo/storagebonus"
	timeutil "github.com/ente/museum/pkg/utils/time"
)

func TestProcessInactiveUsersWarn2mIntegration(t *testing.T) {
	testutil.WithServerRoot(t)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	now := timeutil.Microseconds()
	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "inactive-user@ente.com",
		CreationTime: now - inactiveUserWarn2MonthsInMicroSeconds - inactiveUserOneDayInMicroSeconds,
	})

	userRepo := &repo.UserRepository{
		DB:                  db,
		SecretEncryptionKey: testutil.SecretEncryptionKey(),
		HashingKey:          testutil.HashingKey(),
	}
	storageBonusRepo := &storageBonusRepo.Repository{DB: db}
	billingRepo := &repo.BillingRepository{DB: db}
	billingController := &museumController.BillingController{
		BillingRepo:      billingRepo,
		UserRepo:         userRepo,
		StorageBonusRepo: storageBonusRepo,
	}
	orchestrator := &InactiveUserOrchestrator{
		UserRepo:                userRepo,
		NotificationHistoryRepo: &repo.NotificationHistoryRepository{DB: db},
		LockController: &lock.LockController{
			TaskLockingRepo: &repo.TaskLockRepository{DB: db},
			HostName:        "inactive-user-test-host",
		},
		UserController: &UserController{
			BillingController: billingController,
		},
	}

	orchestrator.ProcessInactiveUsers()

	assertNotificationHistoryCount(t, db, userID, InactiveUserDeletionWarn2mTemplateID, 1)
}

func assertNotificationHistoryCount(t *testing.T, db *sql.DB, userID int64, templateID string, want int) {
	t.Helper()

	var got int
	err := db.QueryRow(
		`SELECT COUNT(*)
		   FROM notification_history
		  WHERE user_id = $1 AND template_id = $2`,
		userID,
		templateID,
	).Scan(&got)
	if err != nil {
		t.Fatalf("failed to count notification history for user %d template %q: %v", userID, templateID, err)
	}
	if got != want {
		t.Fatalf("unexpected notification count for user %d template %q: got %d want %d", userID, templateID, got, want)
	}
}
