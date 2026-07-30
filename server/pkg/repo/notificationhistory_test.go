package repo

import (
	"testing"

	"github.com/ente/museum/internal/testutil"
	"github.com/lib/pq"
)

func TestGrantStorageWarningLoginGraceClearsTerminalRowsAndInsertsGrace(t *testing.T) {
	db := getStorageWarningRepoTestDB(t)
	const userID int64 = 12345
	insertStorageWarningTestUser(t, db, userID, nil)
	testutil.InsertNotificationHistory(t, db, testutil.NotificationHistoryFixture{
		UserID:     userID,
		TemplateID: StorageWarningExpiredScheduledDeletionTemplateID,
		SentTime:   100,
	})
	testutil.InsertNotificationHistory(t, db, testutil.NotificationHistoryFixture{
		UserID:     userID,
		TemplateID: StorageWarningActiveOverageScheduledDeletionTemplateID,
		SentTime:   200,
	})

	graceUntil, granted, err := (&NotificationHistoryRepository{DB: db}).GrantStorageWarningLoginGrace(userID)
	if err != nil {
		t.Fatalf("GrantStorageWarningLoginGrace() error = %v", err)
	}
	if !granted {
		t.Fatal("expected login grace to be granted")
	}
	if graceUntil <= StorageWarningLoginGraceDurationMicroseconds {
		t.Fatalf("unexpected graceUntil: %d", graceUntil)
	}

	var terminalRows int
	if err := db.QueryRow(
		`SELECT count(*)
		   FROM notification_history
		  WHERE user_id = $1
		    AND template_id = ANY($2)`,
		userID,
		pq.Array(StorageWarningScheduledDeletionTemplateIDs()),
	).Scan(&terminalRows); err != nil {
		t.Fatalf("failed to count terminal rows: %v", err)
	}
	if terminalRows != 0 {
		t.Fatalf("terminal rows = %d, want 0", terminalRows)
	}

	var graceRows int
	var notificationGroup string
	if err := db.QueryRow(
		`SELECT count(*), max(notification_group)
		   FROM notification_history
		  WHERE user_id = $1
		    AND template_id = $2`,
		userID,
		StorageWarningLoginGraceTemplateID,
	).Scan(&graceRows, &notificationGroup); err != nil {
		t.Fatalf("failed to read grace row: %v", err)
	}
	if graceRows != 1 {
		t.Fatalf("grace rows = %d, want 1", graceRows)
	}
	if notificationGroup != StorageWarningLoginGraceNotificationGroup {
		t.Fatalf("notification group = %q, want %q", notificationGroup, StorageWarningLoginGraceNotificationGroup)
	}
}

func TestGrantStorageWarningLoginGraceSkipsWhenNoTerminalRowsExist(t *testing.T) {
	db := getStorageWarningRepoTestDB(t)
	const userID int64 = 12349
	insertStorageWarningTestUser(t, db, userID, nil)

	graceUntil, granted, err := (&NotificationHistoryRepository{DB: db}).GrantStorageWarningLoginGrace(userID)
	if err != nil {
		t.Fatalf("GrantStorageWarningLoginGrace() error = %v", err)
	}
	if granted {
		t.Fatal("expected login grace to be skipped when no terminal rows exist")
	}
	if graceUntil != 0 {
		t.Fatalf("graceUntil = %d, want 0", graceUntil)
	}

	active, _, err := (&NotificationHistoryRepository{DB: db}).IsStorageWarningLoginGraceActive(userID, 101)
	if err != nil {
		t.Fatalf("IsStorageWarningLoginGraceActive() error = %v", err)
	}
	if active {
		t.Fatal("expected no active login grace")
	}
}

func TestStorageWarningLoginGraceActiveUsesLatestSentTime(t *testing.T) {
	db := getStorageWarningRepoTestDB(t)
	const userID int64 = 12346
	insertStorageWarningTestUser(t, db, userID, nil)
	oldSentAt := int64(10)
	newSentAt := oldSentAt + StorageWarningLoginGraceDurationMicroseconds + 100
	testutil.InsertNotificationHistory(t, db, testutil.NotificationHistoryFixture{
		UserID:     userID,
		TemplateID: StorageWarningLoginGraceTemplateID,
		SentTime:   oldSentAt,
	})
	testutil.InsertNotificationHistory(t, db, testutil.NotificationHistoryFixture{
		UserID:     userID,
		TemplateID: StorageWarningLoginGraceTemplateID,
		SentTime:   newSentAt,
	})

	active, graceUntil, err := (&NotificationHistoryRepository{DB: db}).IsStorageWarningLoginGraceActive(userID, newSentAt+1)
	if err != nil {
		t.Fatalf("IsStorageWarningLoginGraceActive() error = %v", err)
	}
	if !active {
		t.Fatal("expected latest login grace to be active")
	}
	if want := newSentAt + StorageWarningLoginGraceDurationMicroseconds; graceUntil != want {
		t.Fatalf("graceUntil = %d, want %d", graceUntil, want)
	}
}

func TestClearStorageWarningLoginGrace(t *testing.T) {
	db := getStorageWarningRepoTestDB(t)
	const userID int64 = 12347
	insertStorageWarningTestUser(t, db, userID, nil)
	testutil.InsertNotificationHistory(t, db, testutil.NotificationHistoryFixture{
		UserID:     userID,
		TemplateID: StorageWarningLoginGraceTemplateID,
		SentTime:   100,
	})

	if err := (&NotificationHistoryRepository{DB: db}).ClearStorageWarningLoginGrace(userID); err != nil {
		t.Fatalf("ClearStorageWarningLoginGrace() error = %v", err)
	}

	active, graceUntil, err := (&NotificationHistoryRepository{DB: db}).IsStorageWarningLoginGraceActive(userID, 101)
	if err != nil {
		t.Fatalf("IsStorageWarningLoginGraceActive() error = %v", err)
	}
	if active || graceUntil != 0 {
		t.Fatalf("unexpected grace after clear: active=%v graceUntil=%d", active, graceUntil)
	}
}

func TestGetStorageWarningLoginGraceCandidatesIncludesUsersBelowThreshold(t *testing.T) {
	db := getStorageWarningRepoTestDB(t)
	const userID int64 = 12348
	insertStorageWarningTestUser(t, db, userID, nil)
	insertStorageWarningTestUsage(t, db, userID, 5*testGiB)
	testutil.InsertNotificationHistory(t, db, testutil.NotificationHistoryFixture{
		UserID:     userID,
		TemplateID: StorageWarningLoginGraceTemplateID,
		SentTime:   100,
	})

	candidates, err := (&NotificationHistoryRepository{DB: db}).GetStorageWarningLoginGraceCandidates(t.Context())
	if err != nil {
		t.Fatalf("GetStorageWarningLoginGraceCandidates() error = %v", err)
	}
	if len(candidates) != 1 {
		t.Fatalf("expected 1 grace candidate, got %d", len(candidates))
	}
	if candidates[0].RecipientID != userID {
		t.Fatalf("unexpected candidate: got %d want %d", candidates[0].RecipientID, userID)
	}
	if candidates[0].IsFamilyPlan {
		t.Fatal("expected grace individual candidate to not be marked as family plan")
	}
}
