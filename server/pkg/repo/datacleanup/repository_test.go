package datacleanup

import (
	"database/sql"
	"testing"

	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/utils/crypto"
)

func TestDeleteTableDataDeletesContactsAndAttachmentsForUser(t *testing.T) {
	testutil.WithServerRoot(t)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	targetUserID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "target@ente.com",
		CreationTime: 1,
	})
	otherUserID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       2,
		Email:        "other@ente.com",
		CreationTime: 1,
	})

	mustExecCleanupTest(t, db,
		`INSERT INTO contact_entity(id, user_id, contact_user_id, encrypted_key, encrypted_data)
		 VALUES($1, $2, $3, $4, $5)`,
		"ct_target",
		targetUserID,
		otherUserID,
		[]byte("wrapped-key-target"),
		[]byte("payload-target"),
	)
	mustExecCleanupTest(t, db,
		`INSERT INTO contact_entity(id, user_id, contact_user_id, encrypted_key, encrypted_data)
		 VALUES($1, $2, $3, $4, $5)`,
		"ct_other",
		otherUserID,
		targetUserID,
		[]byte("wrapped-key-other"),
		[]byte("payload-other"),
	)
	mustExecCleanupTest(t, db,
		`INSERT INTO user_attachments(attachment_id, user_id, attachment_type, size, latest_bucket)
		 VALUES($1, $2, $3, $4, $5)`,
		"ua_target",
		targetUserID,
		"profile_picture",
		128,
		"b2-eu-cen",
	)
	mustExecCleanupTest(t, db,
		`INSERT INTO user_attachments(attachment_id, user_id, attachment_type, size, latest_bucket)
		 VALUES($1, $2, $3, $4, $5)`,
		"ua_other",
		otherUserID,
		"profile_picture",
		256,
		"b2-eu-cen",
	)

	repo := &Repository{DB: db}
	if err := repo.DeleteTableData(t.Context(), targetUserID); err != nil {
		t.Fatalf("DeleteTableData() error = %v", err)
	}

	assertCleanupRowCount(t, db, `SELECT COUNT(*) FROM contact_entity WHERE user_id = $1`, targetUserID, 0)
	assertCleanupRowCount(t, db, `SELECT COUNT(*) FROM user_attachments WHERE user_id = $1`, targetUserID, 1)
	assertCleanupRowCount(t, db, `SELECT COUNT(*) FROM contact_entity WHERE user_id = $1`, otherUserID, 1)
	assertCleanupRowCount(t, db, `SELECT COUNT(*) FROM user_attachments WHERE user_id = $1`, otherUserID, 1)

	var isDeleted, pendingSync bool
	if err := db.QueryRow(
		`SELECT is_deleted, pending_sync FROM user_attachments WHERE attachment_id = $1`,
		"ua_target",
	).Scan(&isDeleted, &pendingSync); err != nil {
		t.Fatalf("failed to query target attachment row: %v", err)
	}
	if !isDeleted || !pendingSync {
		t.Fatalf("target attachment row = {is_deleted:%v pending_sync:%v}, want both true", isDeleted, pendingSync)
	}
}

func TestFindScheduledByEmailHash(t *testing.T) {
	testutil.WithServerRoot(t)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		if _, err := db.Exec(`DELETE FROM data_cleanup`); err != nil {
			t.Errorf("failed to clear data_cleanup: %v", err)
		}
		testutil.ResetTables(t, db)
	})

	for _, fixture := range []testutil.UserFixture{
		{UserID: 1, Email: "first@ente.com", CreationTime: 11},
		{UserID: 2, Email: "second@ente.com", CreationTime: 22},
		{UserID: 3, Email: "advanced@ente.com", CreationTime: 33},
		{UserID: 4, Email: "unrelated@ente.com", CreationTime: 44},
	} {
		testutil.InsertUser(t, db, fixture)
	}

	emailHash, err := crypto.GetHash("deleted@ente.com", testutil.HashingKey())
	if err != nil {
		t.Fatalf("GetHash() error = %v", err)
	}
	otherHash, err := crypto.GetHash("other@ente.com", testutil.HashingKey())
	if err != nil {
		t.Fatalf("GetHash() error = %v", err)
	}

	mustExecCleanupTest(t, db, `INSERT INTO usage(user_id, storage_consumed) VALUES($1, $2)`, 1, 2048)
	mustExecCleanupTest(t, db, `INSERT INTO authenticator_key(user_id, encrypted_key, header) VALUES($1, $2, $3)`, 1, "key", "header")
	mustExecCleanupTest(t, db, `INSERT INTO authenticator_entity(id, user_id, encrypted_data, header, is_deleted)
		VALUES($1, $2, $3, $4, FALSE), ($5, $2, NULL, $4, TRUE)`,
		"00000000-0000-0000-0000-000000000001", 1, "active", "header",
		"00000000-0000-0000-0000-000000000002",
	)
	mustExecCleanupTest(t, db, `INSERT INTO data_cleanup(user_id, email_hash, stage, stage_schedule_time, created_at)
		VALUES
			(1, $1, 'scheduled', 1001, 101),
			(2, $1, 'scheduled', 1002, 202),
			(3, $1, 'collection', 1003, 303),
			(4, $2, 'scheduled', 1004, 404)`,
		emailHash, otherHash,
	)

	repository := &Repository{DB: db}
	items, err := repository.FindScheduledByEmailHash(t.Context(), emailHash)
	if err != nil {
		t.Fatalf("FindScheduledByEmailHash() error = %v", err)
	}
	if len(items) != 2 {
		t.Fatalf("FindScheduledByEmailHash() returned %d items, want 2", len(items))
	}
	if items[0].UserID != 2 || items[0].UserCreatedAt != 22 || items[0].ScheduledAt != 202 || items[0].DeletionStartsAt != 1002 {
		t.Fatalf("newest scheduled deletion = %+v, want user 2", items[0])
	}
	if items[1].UserID != 1 || items[1].StorageConsumed != 2048 || items[1].AuthenticatorEntryCount != 1 {
		t.Fatalf("older scheduled deletion = %+v, want user 1 details", items[1])
	}

	if err := repository.MoveToNextStage(t.Context(), 2, "collection", 2002); err != nil {
		t.Fatalf("MoveToNextStage() error = %v", err)
	}
	var storedHash sql.NullString
	if err := db.QueryRow(`SELECT email_hash FROM data_cleanup WHERE user_id = 2`).Scan(&storedHash); err != nil {
		t.Fatalf("failed to read advanced cleanup row: %v", err)
	}
	if storedHash.Valid {
		t.Fatalf("email hash was retained after stage advance: %q", storedHash.String)
	}

	items, err = repository.FindScheduledByEmailHash(t.Context(), emailHash)
	if err != nil {
		t.Fatalf("FindScheduledByEmailHash() after stage advance error = %v", err)
	}
	if len(items) != 1 || items[0].UserID != 1 {
		t.Fatalf("scheduled deletions after stage advance = %+v, want only user 1", items)
	}
}

func mustExecCleanupTest(t *testing.T, db *sql.DB, query string, args ...any) {
	t.Helper()
	if _, err := db.Exec(query, args...); err != nil {
		t.Fatalf("exec failed for %q: %v", query, err)
	}
}

func assertCleanupRowCount(t *testing.T, db *sql.DB, query string, arg any, want int) {
	t.Helper()
	var got int
	if err := db.QueryRow(query, arg).Scan(&got); err != nil {
		t.Fatalf("query failed for %q: %v", query, err)
	}
	if got != want {
		t.Fatalf("row count for %q = %d, want %d", query, got, want)
	}
}
