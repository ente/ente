package email

import (
	"database/sql"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/controller/lock"
	"github.com/ente/museum/pkg/repo"
	storageBonusRepo "github.com/ente/museum/pkg/repo/storagebonus"
	timeutil "github.com/ente/museum/pkg/utils/time"
)

const storageWarningIntegrationTestGiB = int64(1 << 30)
const storageWarningIntegrationTestUserID int64 = 1

func TestSendStorageWarningMailsActiveOverageIntegration(t *testing.T) {
	testutil.WithServerRoot(t)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	now := timeutil.Microseconds()
	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       storageWarningIntegrationTestUserID,
		Email:        "active-overage@ente.com",
		CreationTime: now - timeutil.MicroSecondsInOneHour,
	})
	testutil.InsertUsage(t, db, userID, 36*storageWarningIntegrationTestGiB)
	testutil.InsertSubscription(t, db, testutil.SubscriptionFixture{
		UserID:          userID,
		Storage:         10 * storageWarningIntegrationTestGiB,
		ExpiryTime:      now + 24*timeutil.MicroSecondsInOneHour,
		ProductID:       "photos_yearly",
		PaymentProvider: ente.Stripe,
	})

	controller := newStorageWarningIntegrationController(db)
	controller.SendStorageWarningMails()

	assertStorageWarningNotificationCount(t, db, userID, StorageWarningActiveOverageAnchorTemplateID, 1)
}

func TestSendStorageWarningMailsExpiredIntegration(t *testing.T) {
	testutil.WithServerRoot(t)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	now := timeutil.Microseconds()
	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       storageWarningIntegrationTestUserID,
		Email:        "expired-subscription@ente.com",
		CreationTime: now - timeutil.MicroSecondsInOneHour,
	})
	testutil.InsertUsage(t, db, userID, 26*storageWarningIntegrationTestGiB)
	testutil.InsertSubscription(t, db, testutil.SubscriptionFixture{
		UserID:          userID,
		Storage:         10 * storageWarningIntegrationTestGiB,
		ExpiryTime:      now - storageWarningExpiredAnchorDelay - (10 * 24 * timeutil.MicroSecondsInOneHour),
		ProductID:       "photos_yearly",
		PaymentProvider: ente.Stripe,
	})

	controller := newStorageWarningIntegrationController(db)
	controller.SendStorageWarningMails()

	assertStorageWarningNotificationCount(t, db, userID, storageWarningExpired0TemplateID, 1)
}

func TestBuildIndividualStorageWarningSnapshotExpiredBackfillUsesBufferedRecoveryIntegration(t *testing.T) {
	testutil.WithServerRoot(t)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	now := timeutil.Microseconds()
	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       storageWarningIntegrationTestUserID,
		Email:        "expired-backfill@ente.com",
		CreationTime: now - timeutil.MicroSecondsInOneHour,
	})
	testutil.InsertUsage(t, db, userID, 26*storageWarningIntegrationTestGiB)
	testutil.InsertSubscription(t, db, testutil.SubscriptionFixture{
		UserID:          userID,
		Storage:         10 * storageWarningIntegrationTestGiB,
		ExpiryTime:      now - storageWarningExpiredAnchorDelay - storageWarningExpiredDeletionDelay - (10 * 24 * timeutil.MicroSecondsInOneHour),
		ProductID:       "photos_yearly",
		PaymentProvider: ente.Stripe,
	})

	controller := newStorageWarningIntegrationController(db)
	snapshot, err := controller.buildIndividualStorageWarningSnapshot(t.Context(), userID, now)
	if err != nil {
		t.Fatalf("buildIndividualStorageWarningSnapshot() error = %v", err)
	}

	if snapshot.ExpiredStage != expiredWarningStage0 {
		t.Fatalf("unexpected expired stage: got %q want %q", snapshot.ExpiredStage, expiredWarningStage0)
	}
	if !snapshot.ExpiredBufferedCycle {
		t.Fatal("expected expired backfill snapshot to use buffered recovery")
	}
	if snapshot.WarningCycleStart != now {
		t.Fatalf("unexpected warning cycle start: got %d want %d", snapshot.WarningCycleStart, now)
	}
	wantAutoDeleteDate := now + storageWarningExpiredBackfillMinRecoveryDelay
	if snapshot.AutoDeleteDate != wantAutoDeleteDate {
		t.Fatalf("unexpected auto delete date: got %d want %d", snapshot.AutoDeleteDate, wantAutoDeleteDate)
	}
}

func TestBuildIndividualStorageWarningSnapshotExpiredBackfillContinuesBufferedCycleIntegration(t *testing.T) {
	testutil.WithServerRoot(t)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	anchorNow := timeutil.Microseconds()
	cycleStart := anchorNow - (16 * 24 * timeutil.MicroSecondsInOneHour)
	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       storageWarningIntegrationTestUserID,
		Email:        "expired-buffered-progress@ente.com",
		CreationTime: anchorNow - timeutil.MicroSecondsInOneHour,
	})
	testutil.InsertUsage(t, db, userID, 26*storageWarningIntegrationTestGiB)
	testutil.InsertSubscription(t, db, testutil.SubscriptionFixture{
		UserID:          userID,
		Storage:         10 * storageWarningIntegrationTestGiB,
		ExpiryTime:      cycleStart - storageWarningExpiredAnchorDelay - storageWarningExpiredDeletionDelay - (10 * 24 * timeutil.MicroSecondsInOneHour),
		ProductID:       "photos_yearly",
		PaymentProvider: ente.Stripe,
	})
	testutil.InsertNotificationHistory(t, db, testutil.NotificationHistoryFixture{
		UserID:            userID,
		TemplateID:        storageWarningExpired0TemplateID,
		SentTime:          cycleStart,
		NotificationGroup: storageWarningExpiredNotificationGroup,
	})

	controller := newStorageWarningIntegrationController(db)
	snapshot, err := controller.buildIndividualStorageWarningSnapshot(t.Context(), userID, anchorNow)
	if err != nil {
		t.Fatalf("buildIndividualStorageWarningSnapshot() error = %v", err)
	}

	if snapshot.ExpiredStage != expiredWarningStage60 {
		t.Fatalf("unexpected expired stage: got %q want %q", snapshot.ExpiredStage, expiredWarningStage60)
	}
	if !snapshot.ExpiredBufferedCycle {
		t.Fatal("expected persisted late first-contact history to keep buffered recovery")
	}
	if snapshot.WarningCycleStart != cycleStart {
		t.Fatalf("unexpected warning cycle start: got %d want %d", snapshot.WarningCycleStart, cycleStart)
	}
	wantAutoDeleteDate := cycleStart + storageWarningExpiredBackfillMinRecoveryDelay
	if snapshot.AutoDeleteDate != wantAutoDeleteDate {
		t.Fatalf("unexpected auto delete date: got %d want %d", snapshot.AutoDeleteDate, wantAutoDeleteDate)
	}
}

func TestBuildIndividualStorageWarningSnapshotExpiredBackfillWithExisting0dAnd30dSkipsImmediateSend(t *testing.T) {
	testutil.WithServerRoot(t)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	day := int64(24 * timeutil.MicroSecondsInOneHour)
	t0 := int64(200 * day)
	now := t0 + (2 * day)
	anchor := t0 - (40 * day)
	userID := setupExpiredBackfillWithOld0dAnd30dHistory(t, db, anchor-(30*day), t0)

	controller := newStorageWarningIntegrationController(db)
	snapshot, err := controller.buildIndividualStorageWarningSnapshot(t.Context(), userID, now)
	if err != nil {
		t.Fatalf("buildIndividualStorageWarningSnapshot() error = %v", err)
	}

	if snapshot.CurrentBucket != storageWarningBucketExpired {
		t.Fatalf("unexpected current bucket: got %q want %q", snapshot.CurrentBucket, storageWarningBucketExpired)
	}
	if snapshot.Bucket != storageWarningBucketNone {
		t.Fatalf("unexpected decorated bucket: got %q want %q", snapshot.Bucket, storageWarningBucketNone)
	}
	if snapshot.ExpiredStage != expiredWarningStageNone {
		t.Fatalf("unexpected expired stage: got %q want %q", snapshot.ExpiredStage, expiredWarningStageNone)
	}
	if !snapshot.ExpiredBufferedCycle {
		t.Fatal("expected persisted old 0d send to establish buffered cycle")
	}
	if snapshot.WarningCycleStart != t0 {
		t.Fatalf("unexpected warning cycle start: got %d want %d", snapshot.WarningCycleStart, t0)
	}
	wantAutoDeleteDate := maxInt64(t0+storageWarningExpiredBackfillMinRecoveryDelay, anchor+storageWarningExpiredDeletionDelay)
	if snapshot.AutoDeleteDate != wantAutoDeleteDate {
		t.Fatalf("unexpected auto delete date: got %d want %d", snapshot.AutoDeleteDate, wantAutoDeleteDate)
	}
}

func TestBuildIndividualStorageWarningSnapshotExpiredBackfillWithExisting0dAnd30dTransitionsTo60dLater(t *testing.T) {
	testutil.WithServerRoot(t)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	day := int64(24 * timeutil.MicroSecondsInOneHour)
	t0 := int64(200 * day)
	anchor := t0 - (40 * day)
	standardAutoDeleteDate := anchor + storageWarningExpiredDeletionDelay
	now := expiredBufferedWarning60At(t0, standardAutoDeleteDate) + day
	userID := setupExpiredBackfillWithOld0dAnd30dHistory(t, db, anchor-(30*day), t0)

	controller := newStorageWarningIntegrationController(db)
	snapshot, err := controller.buildIndividualStorageWarningSnapshot(t.Context(), userID, now)
	if err != nil {
		t.Fatalf("buildIndividualStorageWarningSnapshot() error = %v", err)
	}

	if snapshot.CurrentBucket != storageWarningBucketExpired {
		t.Fatalf("unexpected current bucket: got %q want %q", snapshot.CurrentBucket, storageWarningBucketExpired)
	}
	if snapshot.Bucket != storageWarningBucketExpired {
		t.Fatalf("unexpected decorated bucket: got %q want %q", snapshot.Bucket, storageWarningBucketExpired)
	}
	if snapshot.ExpiredStage != expiredWarningStage60 {
		t.Fatalf("unexpected expired stage: got %q want %q", snapshot.ExpiredStage, expiredWarningStage60)
	}
	if !snapshot.ExpiredBufferedCycle {
		t.Fatal("expected persisted old 0d send to keep buffered cycle")
	}
	if snapshot.WarningCycleStart != t0 {
		t.Fatalf("unexpected warning cycle start: got %d want %d", snapshot.WarningCycleStart, t0)
	}
	wantAutoDeleteDate := maxInt64(t0+storageWarningExpiredBackfillMinRecoveryDelay, standardAutoDeleteDate)
	if snapshot.AutoDeleteDate != wantAutoDeleteDate {
		t.Fatalf("unexpected auto delete date: got %d want %d", snapshot.AutoDeleteDate, wantAutoDeleteDate)
	}
	if broken, alert := storageWarningCadenceBroken(snapshot); broken {
		t.Fatalf("expected buffered expired stage 60 cadence to pass, got alert %q", alert)
	}
}

func setupExpiredBackfillWithOld0dAnd30dHistory(t *testing.T, db *sql.DB, subscriptionExpiry int64, firstSendAt int64) int64 {
	t.Helper()

	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       storageWarningIntegrationTestUserID,
		Email:        "expired-old-ladder@ente.com",
		CreationTime: firstSendAt - timeutil.MicroSecondsInOneHour,
	})
	testutil.InsertUsage(t, db, userID, 26*storageWarningIntegrationTestGiB)
	testutil.InsertSubscription(t, db, testutil.SubscriptionFixture{
		UserID:          userID,
		Storage:         10 * storageWarningIntegrationTestGiB,
		ExpiryTime:      subscriptionExpiry,
		ProductID:       "photos_yearly",
		PaymentProvider: ente.Stripe,
	})
	testutil.InsertNotificationHistory(t, db, testutil.NotificationHistoryFixture{
		UserID:            userID,
		TemplateID:        storageWarningExpired0TemplateID,
		SentTime:          firstSendAt,
		NotificationGroup: storageWarningExpiredNotificationGroup,
	})
	testutil.InsertNotificationHistory(t, db, testutil.NotificationHistoryFixture{
		UserID:            userID,
		TemplateID:        storageWarningExpired30TemplateID,
		SentTime:          firstSendAt + (2 * 24 * timeutil.MicroSecondsInOneHour),
		NotificationGroup: storageWarningExpiredNotificationGroup,
	})

	return userID
}

func maxInt64(a int64, b int64) int64 {
	if a >= b {
		return a
	}
	return b
}

func newStorageWarningIntegrationController(db *sql.DB) *EmailNotificationController {
	userRepo := &repo.UserRepository{
		DB:                  db,
		SecretEncryptionKey: testutil.SecretEncryptionKey(),
		HashingKey:          testutil.HashingKey(),
	}

	return &EmailNotificationController{
		UserRepo:         userRepo,
		UsageRepo:        &repo.UsageRepository{DB: db, UserRepo: userRepo},
		BillingRepo:      &repo.BillingRepository{DB: db},
		StorageBonusRepo: &storageBonusRepo.Repository{DB: db},
		LockController: &lock.LockController{
			TaskLockingRepo: &repo.TaskLockRepository{DB: db},
			HostName:        "storage-warning-test-host",
		},
		NotificationHistoryRepo: &repo.NotificationHistoryRepository{DB: db},
	}
}

func assertStorageWarningNotificationCount(t *testing.T, db *sql.DB, userID int64, templateID string, want int) {
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
