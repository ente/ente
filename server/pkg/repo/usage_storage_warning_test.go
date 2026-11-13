package repo

import (
	"database/sql"
	"fmt"
	"testing"

	"github.com/ente/museum/internal/testutil"
	"github.com/google/uuid"
)

const testGiB = int64(1 << 30)

func getStorageWarningRepoTestDB(t *testing.T) *sql.DB {
	t.Helper()
	db := testutil.RequireTestDB(t)
	resetStorageWarningRepoTestTables(t, db)
	t.Cleanup(func() {
		resetStorageWarningRepoTestTables(t, db)
	})
	return db
}

func resetStorageWarningRepoTestTables(t *testing.T, db *sql.DB) {
	t.Helper()
	testutil.ResetTables(t, db)
}

func insertStorageWarningTestUser(t *testing.T, db *sql.DB, userID int64, familyAdminID *int64) {
	t.Helper()
	testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:        userID,
		Email:         fmt.Sprintf("user-%d@example.com", userID),
		CreationTime:  1,
		FamilyAdminID: familyAdminID,
	})
}

func insertStorageWarningTestUsage(t *testing.T, db *sql.DB, userID int64, usage int64) {
	t.Helper()
	_, err := db.Exec(`INSERT INTO usage(user_id, storage_consumed) VALUES($1, $2)`, userID, usage)
	if err != nil {
		t.Fatalf("failed to insert usage for user %d: %v", userID, err)
	}
}

func insertStorageWarningTestSubscription(t *testing.T, db *sql.DB, userID int64, productID string) {
	t.Helper()
	_, err := db.Exec(
		`INSERT INTO subscriptions(user_id, storage, original_transaction_id, expiry_time, product_id, payment_provider, latest_verification_data, attributes)
		 VALUES($1, $2, $3, $4, $5, $6, $7, $8::jsonb)`,
		userID,
		100*testGiB,
		fmt.Sprintf("txn-%d", userID),
		int64(1),
		productID,
		"stripe",
		"",
		"{}",
	)
	if err != nil {
		t.Fatalf("failed to insert subscription for user %d: %v", userID, err)
	}
}

func insertStorageWarningTestFamilyMember(t *testing.T, db *sql.DB, adminID int64, memberID int64, status string) {
	t.Helper()
	_, err := db.Exec(
		`INSERT INTO families(id, admin_id, member_id, status)
		 VALUES($1, $2, $3, $4)`,
		uuid.New(),
		adminID,
		memberID,
		status,
	)
	if err != nil {
		t.Fatalf("failed to insert family member %d for admin %d: %v", memberID, adminID, err)
	}
}

func TestGetStorageWarningCandidatesCollapsesThresholdQualifiedMembersToAdmin(t *testing.T) {
	db := getStorageWarningRepoTestDB(t)
	repo := &UsageRepository{DB: db}
	ctx := t.Context()

	adminID := int64(101)
	memberOneID := int64(102)
	memberTwoID := int64(103)

	insertStorageWarningTestUser(t, db, adminID, &adminID)
	insertStorageWarningTestUser(t, db, memberOneID, &adminID)
	insertStorageWarningTestUser(t, db, memberTwoID, &adminID)
	insertStorageWarningTestFamilyMember(t, db, adminID, adminID, "SELF")
	insertStorageWarningTestFamilyMember(t, db, adminID, memberOneID, "ACCEPTED")
	insertStorageWarningTestFamilyMember(t, db, adminID, memberTwoID, "ACCEPTED")
	insertStorageWarningTestUsage(t, db, adminID, 0)
	insertStorageWarningTestUsage(t, db, memberOneID, 26*testGiB)
	insertStorageWarningTestUsage(t, db, memberTwoID, 27*testGiB)
	insertStorageWarningTestSubscription(t, db, adminID, "photos_yearly")

	candidates, err := repo.GetStorageWarningCandidates(ctx, 25*testGiB)
	if err != nil {
		t.Fatalf("GetStorageWarningCandidates() error = %v", err)
	}
	if len(candidates) != 1 {
		t.Fatalf("expected 1 candidate, got %d", len(candidates))
	}
	if candidates[0].RecipientID != adminID {
		t.Fatalf("unexpected recipient id: got %d want %d", candidates[0].RecipientID, adminID)
	}
	if !candidates[0].IsFamilyPlan {
		t.Fatal("expected family candidate to be marked as family plan")
	}
}

func TestGetStorageWarningCandidatesExcludesFamilyTotalBelowPerMemberThreshold(t *testing.T) {
	db := getStorageWarningRepoTestDB(t)
	repo := &UsageRepository{DB: db}
	ctx := t.Context()

	adminID := int64(201)
	memberID := int64(202)

	insertStorageWarningTestUser(t, db, adminID, &adminID)
	insertStorageWarningTestUser(t, db, memberID, &adminID)
	insertStorageWarningTestFamilyMember(t, db, adminID, adminID, "SELF")
	insertStorageWarningTestFamilyMember(t, db, adminID, memberID, "ACCEPTED")
	insertStorageWarningTestUsage(t, db, adminID, 12*testGiB)
	insertStorageWarningTestUsage(t, db, memberID, 14*testGiB)
	insertStorageWarningTestSubscription(t, db, adminID, "photos_yearly")

	candidates, err := repo.GetStorageWarningCandidates(ctx, 25*testGiB)
	if err != nil {
		t.Fatalf("GetStorageWarningCandidates() error = %v", err)
	}
	if len(candidates) != 0 {
		t.Fatalf("expected no candidates when no member exceeds threshold, got %+v", candidates)
	}
}

func TestGetStorageWarningCandidatesUsesFamilyAdminIDForMembershipAwareness(t *testing.T) {
	db := getStorageWarningRepoTestDB(t)
	repo := &UsageRepository{DB: db}
	ctx := t.Context()

	adminID := int64(251)
	memberID := int64(252)

	insertStorageWarningTestUser(t, db, adminID, &adminID)
	insertStorageWarningTestUser(t, db, memberID, nil)
	insertStorageWarningTestFamilyMember(t, db, adminID, memberID, "INVITED")
	insertStorageWarningTestUsage(t, db, memberID, 26*testGiB)

	candidates, err := repo.GetStorageWarningCandidates(ctx, 25*testGiB)
	if err != nil {
		t.Fatalf("GetStorageWarningCandidates() error = %v", err)
	}
	if len(candidates) != 1 {
		t.Fatalf("expected invited member without family_admin_id to be treated as an individual candidate, got %+v", candidates)
	}
	if candidates[0].RecipientID != memberID {
		t.Fatalf("unexpected recipient id: got %d want %d", candidates[0].RecipientID, memberID)
	}
	if candidates[0].IsFamilyPlan {
		t.Fatal("expected invited member without family_admin_id to not be marked as family plan")
	}
}

func TestGetStorageWarningCandidatesIncludesFreeFamiliesAboveThreshold(t *testing.T) {
	db := getStorageWarningRepoTestDB(t)
	repo := &UsageRepository{DB: db}
	ctx := t.Context()

	adminID := int64(301)

	insertStorageWarningTestUser(t, db, adminID, &adminID)
	insertStorageWarningTestFamilyMember(t, db, adminID, adminID, "SELF")
	insertStorageWarningTestUsage(t, db, adminID, 30*testGiB)
	insertStorageWarningTestSubscription(t, db, adminID, "free")

	candidates, err := repo.GetStorageWarningCandidates(ctx, 25*testGiB)
	if err != nil {
		t.Fatalf("GetStorageWarningCandidates() error = %v", err)
	}
	if len(candidates) != 1 || candidates[0].RecipientID != adminID {
		t.Fatalf("expected free family admin %d to be selected, got %+v", adminID, candidates)
	}
	if !candidates[0].IsFamilyPlan {
		t.Fatal("expected free family candidate to be marked as family plan")
	}
}

func TestGetStorageWarningCandidatesIncludeFreeUsersAndExcludeLowUsage(t *testing.T) {
	db := getStorageWarningRepoTestDB(t)
	repo := &UsageRepository{DB: db}
	ctx := t.Context()

	paidUserID := int64(401)
	freeUserID := int64(402)
	lowUsageUserID := int64(403)

	insertStorageWarningTestUser(t, db, paidUserID, nil)
	insertStorageWarningTestUsage(t, db, paidUserID, 26*testGiB)
	insertStorageWarningTestSubscription(t, db, paidUserID, "photos_yearly")

	insertStorageWarningTestUser(t, db, freeUserID, nil)
	insertStorageWarningTestUsage(t, db, freeUserID, 27*testGiB)
	insertStorageWarningTestSubscription(t, db, freeUserID, "free")

	insertStorageWarningTestUser(t, db, lowUsageUserID, nil)
	insertStorageWarningTestUsage(t, db, lowUsageUserID, 5*testGiB)
	insertStorageWarningTestSubscription(t, db, lowUsageUserID, "photos_yearly")

	candidates, err := repo.GetStorageWarningCandidates(ctx, 25*testGiB)
	if err != nil {
		t.Fatalf("GetStorageWarningCandidates() error = %v", err)
	}
	if len(candidates) != 2 {
		t.Fatalf("expected 2 candidates, got %d", len(candidates))
	}
	if candidates[0].RecipientID != paidUserID {
		t.Fatalf("unexpected first candidate: got %d want %d", candidates[0].RecipientID, paidUserID)
	}
	if candidates[1].RecipientID != freeUserID {
		t.Fatalf("unexpected second candidate: got %d want %d", candidates[1].RecipientID, freeUserID)
	}
	if candidates[0].IsFamilyPlan || candidates[1].IsFamilyPlan {
		t.Fatal("expected individual candidates to not be marked as family plans")
	}
}
