package user

import (
	"database/sql"
	"fmt"
	"net/http/httptest"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/ente/cache"
	"github.com/ente/museum/internal/testutil"
	museumcontroller "github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/controller/family"
	"github.com/ente/museum/pkg/controller/usercache"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/repo/passkey"
	storagebonusrepo "github.com/ente/museum/pkg/repo/storagebonus"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

func TestGetLockerUsageExcludesInvitedFamilyMembersFromFamilyTotals(t *testing.T) {
	controller, db, ctx := setupLockerUsageControllerTest(t)

	adminID := int64(101)
	acceptedMemberID := int64(102)
	invitedMemberID := int64(103)

	insertLockerUsageTestUser(t, db, adminID, &adminID)
	insertLockerUsageTestUser(t, db, acceptedMemberID, &adminID)
	insertLockerUsageTestUser(t, db, invitedMemberID, &adminID)

	insertLockerUsageTestFamilyMember(t, db, adminID, adminID, ente.SELF)
	insertLockerUsageTestFamilyMember(t, db, adminID, acceptedMemberID, ente.ACCEPTED)
	insertLockerUsageTestFamilyMember(t, db, adminID, invitedMemberID, ente.INVITED)

	insertLockerUsageTestLockerFile(t, db, adminID, 101)
	insertLockerUsageTestLockerFile(t, db, acceptedMemberID, 201)
	insertLockerUsageTestLockerFile(t, db, acceptedMemberID, 202)
	insertLockerUsageTestLockerFile(t, db, invitedMemberID, 301)
	insertLockerUsageTestLockerFile(t, db, invitedMemberID, 302)
	insertLockerUsageTestLockerFile(t, db, invitedMemberID, 303)

	resp, err := controller.GetLockerUsage(ctx, adminID)
	if err != nil {
		t.Fatalf("GetLockerUsage() error = %v", err)
	}

	if !resp.IsFamily {
		t.Fatal("expected family locker usage response")
	}
	if resp.UsedFileCount != 3 {
		t.Fatalf("unexpected used file count: got %d want %d", resp.UsedFileCount, 3)
	}
	if resp.UsedStorage != 504 {
		t.Fatalf("unexpected used storage: got %d want %d", resp.UsedStorage, 504)
	}
	if resp.UserFileCount != 1 {
		t.Fatalf("unexpected admin file count: got %d want %d", resp.UserFileCount, 1)
	}
	if resp.UserStorage != 101 {
		t.Fatalf("unexpected admin storage: got %d want %d", resp.UserStorage, 101)
	}
}

func TestGetLockerUsageReturnsRequesterSpecificUsageWithinActiveFamilyScope(t *testing.T) {
	controller, db, ctx := setupLockerUsageControllerTest(t)

	adminID := int64(201)
	acceptedMemberID := int64(202)
	invitedMemberID := int64(203)

	insertLockerUsageTestUser(t, db, adminID, &adminID)
	insertLockerUsageTestUser(t, db, acceptedMemberID, &adminID)
	insertLockerUsageTestUser(t, db, invitedMemberID, &adminID)

	insertLockerUsageTestFamilyMember(t, db, adminID, adminID, ente.SELF)
	insertLockerUsageTestFamilyMember(t, db, adminID, acceptedMemberID, ente.ACCEPTED)
	insertLockerUsageTestFamilyMember(t, db, adminID, invitedMemberID, ente.INVITED)

	insertLockerUsageTestLockerFile(t, db, adminID, 111)
	insertLockerUsageTestLockerFile(t, db, acceptedMemberID, 211)
	insertLockerUsageTestLockerFile(t, db, acceptedMemberID, 212)
	insertLockerUsageTestLockerFile(t, db, invitedMemberID, 311)

	resp, err := controller.GetLockerUsage(ctx, acceptedMemberID)
	if err != nil {
		t.Fatalf("GetLockerUsage() error = %v", err)
	}

	if !resp.IsFamily {
		t.Fatal("expected family locker usage response")
	}
	if resp.UsedFileCount != 3 {
		t.Fatalf("unexpected used file count: got %d want %d", resp.UsedFileCount, 3)
	}
	if resp.UsedStorage != 534 {
		t.Fatalf("unexpected used storage: got %d want %d", resp.UsedStorage, 534)
	}
	if resp.UserFileCount != 2 {
		t.Fatalf("unexpected member file count: got %d want %d", resp.UserFileCount, 2)
	}
	if resp.UserStorage != 423 {
		t.Fatalf("unexpected member storage: got %d want %d", resp.UserStorage, 423)
	}
}

func TestGetDetailsV2DiscountsOnlyRequesterLockerUsageInFamily(t *testing.T) {
	controller, db, ctx := setupLockerUsageControllerTest(t)

	adminID := int64(301)
	acceptedMemberID := int64(302)
	invitedMemberID := int64(303)

	insertLockerUsageTestUser(t, db, adminID, &adminID)
	insertLockerUsageTestUser(t, db, acceptedMemberID, &adminID)
	insertLockerUsageTestUser(t, db, invitedMemberID, nil)

	insertLockerUsageTestFamilyMember(t, db, adminID, adminID, ente.SELF)
	insertLockerUsageTestFamilyMember(t, db, adminID, acceptedMemberID, ente.ACCEPTED)
	insertLockerUsageTestFamilyMember(t, db, adminID, invitedMemberID, ente.INVITED)

	insertLockerUsageTestLockerFile(t, db, adminID, 101)
	insertLockerUsageTestLockerFile(t, db, acceptedMemberID, 201)
	insertLockerUsageTestLockerFile(t, db, invitedMemberID, 301)

	testutil.InsertUsage(t, db, adminID, 1000+101)
	testutil.InsertUsage(t, db, acceptedMemberID, 50+201)
	for _, userID := range []int64{adminID, acceptedMemberID, invitedMemberID} {
		testutil.InsertSubscription(t, db, testutil.SubscriptionFixture{UserID: userID, Storage: 1, ProductID: ente.FreePlanProductID})
	}

	photosDetails, err := controller.GetDetailsV2(ctx, acceptedMemberID, false, ente.Photos)
	if err != nil {
		t.Fatalf("GetDetailsV2() error = %v", err)
	}
	if photosDetails.Usage != 50 {
		t.Fatalf("unexpected member usage: got %d want %d", photosDetails.Usage, 50)
	}
	familyUsage := map[int64]int64{}
	for _, member := range photosDetails.FamilyData.Members {
		familyUsage[member.MemberUserID] = member.Usage
	}
	wantFamilyUsage := map[int64]int64{adminID: 1000 + 101, acceptedMemberID: 50 + 201, invitedMemberID: 0}
	if len(familyUsage) != len(wantFamilyUsage) {
		t.Fatalf("unexpected family member count: got %d want %d", len(familyUsage), len(wantFamilyUsage))
	}
	for memberID, want := range wantFamilyUsage {
		if got, ok := familyUsage[memberID]; !ok || got != want {
			t.Fatalf("unexpected family usage for %d: got %d want %d", memberID, got, want)
		}
	}

	lockerDetails, err := controller.GetDetailsV2(ctx, acceptedMemberID, false, ente.Locker)
	if err != nil {
		t.Fatalf("GetDetailsV2() error = %v", err)
	}
	if lockerDetails.LockerFamilyUsage.FamilyFileCount != 2 {
		t.Fatalf("unexpected family file count: got %d want %d", lockerDetails.LockerFamilyUsage.FamilyFileCount, 2)
	}
}

func setupLockerUsageControllerTest(t *testing.T) (*UserController, *sql.DB, *gin.Context) {
	t.Helper()

	testutil.WithServerRoot(t)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	gin.SetMode(gin.TestMode)
	recorder := httptest.NewRecorder()
	ctx, _ := gin.CreateTestContext(recorder)
	ctx.Request = httptest.NewRequest("GET", "/users/details/v2", nil)

	userRepo := &repo.UserRepository{
		DB:                  db,
		SecretEncryptionKey: testutil.SecretEncryptionKey(),
		HashingKey:          testutil.HashingKey(),
	}
	usageRepo := &repo.UsageRepository{
		DB:       db,
		UserRepo: userRepo,
	}
	billingRepo := &repo.BillingRepository{DB: db}
	storageBonusRepo := &storagebonusrepo.Repository{DB: db}
	userCacheCtrl := &usercache.Controller{
		StoreBonusRepo: storageBonusRepo,
		UserCache:      cache.NewUserCache(),
	}

	return &UserController{
		UserRepo:     userRepo,
		UsageRepo:    usageRepo,
		UserAuthRepo: &repo.UserAuthRepository{DB: db},
		PasskeyRepo:  &passkey.Repository{DB: db},
		BillingController: &museumcontroller.BillingController{
			BillingRepo:      billingRepo,
			UserRepo:         userRepo,
			StorageBonusRepo: storageBonusRepo,
		},
		FamilyController: &family.Controller{
			UserRepo:      userRepo,
			FamilyRepo:    &repo.FamilyRepository{DB: db},
			UserCacheCtrl: userCacheCtrl,
		},
		UserCacheController: userCacheCtrl,
	}, db, ctx
}

func insertLockerUsageTestUser(t *testing.T, db *sql.DB, userID int64, familyAdminID *int64) {
	t.Helper()

	testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:        userID,
		Email:         fmt.Sprintf("locker-usage-user-%d@ente.com", userID),
		CreationTime:  1,
		FamilyAdminID: familyAdminID,
	})
}

func insertLockerUsageTestFamilyMember(t *testing.T, db *sql.DB, adminID, memberID int64, status ente.MemberStatus) {
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

func insertLockerUsageTestLockerFile(t *testing.T, db *sql.DB, ownerID, size int64) {
	t.Helper()

	var collectionID int64
	err := db.QueryRow(
		`INSERT INTO collections(owner_id, encrypted_key, key_decryption_nonce, name, type, attributes, updation_time, is_deleted, app)
		 VALUES($1, $2, $3, $4, $5, $6::jsonb, $7, $8, $9)
		 RETURNING collection_id`,
		ownerID,
		"encrypted-key",
		"key-nonce",
		"Locker collection",
		"album",
		"{}",
		size,
		false,
		string(ente.Locker),
	).Scan(&collectionID)
	if err != nil {
		t.Fatalf("failed to insert collection for owner %d: %v", ownerID, err)
	}

	var fileID int64
	err = db.QueryRow(
		`INSERT INTO files(owner_id, file_decryption_header, thumbnail_decryption_header, metadata_decryption_header, encrypted_metadata, updation_time, info)
		 VALUES($1, $2, $3, $4, $5, $6, $7::jsonb)
		 RETURNING file_id`,
		ownerID,
		"file-header",
		"thumbnail-header",
		"metadata-header",
		"encrypted-metadata",
		size,
		"{}",
	).Scan(&fileID)
	if err != nil {
		t.Fatalf("failed to insert file for owner %d: %v", ownerID, err)
	}

	_, err = db.Exec(
		`INSERT INTO collection_files(collection_id, file_id, encrypted_key, key_decryption_nonce, is_deleted, updation_time, c_owner_id, f_owner_id)
		 VALUES($1, $2, $3, $4, $5, $6, $7, $8)`,
		collectionID,
		fileID,
		"collection-file-key",
		"collection-file-nonce",
		false,
		size,
		ownerID,
		ownerID,
	)
	if err != nil {
		t.Fatalf("failed to link file %d to collection %d: %v", fileID, collectionID, err)
	}

	_, err = db.Exec(
		`INSERT INTO object_keys(file_id, o_type, object_key, size, datacenters)
		 VALUES($1, 'file', $2, $3, ARRAY['b2-eu-cen']::s3region[])`,
		fileID,
		uuid.NewString(),
		size,
	)
	if err != nil {
		t.Fatalf("failed to insert object key for file %d: %v", fileID, err)
	}
}
