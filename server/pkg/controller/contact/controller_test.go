package contact

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"net/http/httptest"
	"reflect"
	"sort"
	"strings"
	"testing"

	"github.com/ente/museum/ente"
	contactmodel "github.com/ente/museum/ente/contact"
	"github.com/ente/museum/internal/testutil"
	basecontroller "github.com/ente/museum/pkg/controller"
	repo "github.com/ente/museum/pkg/repo"
	contactrepo "github.com/ente/museum/pkg/repo/contact"
	"github.com/ente/museum/pkg/utils/config"
	"github.com/ente/museum/pkg/utils/crypto"
	"github.com/ente/museum/pkg/utils/s3config"
	"github.com/gin-gonic/gin"
	"github.com/lib/pq"
	"github.com/spf13/viper"
)

func setupContactControllerTest(t *testing.T) (*Controller, *sql.DB, *gin.Context, *s3config.S3Config) {
	t.Helper()

	testutil.WithServerRoot(t)
	viper.Reset()
	if err := config.ConfigureViper("local"); err != nil {
		t.Fatalf("failed to configure viper: %v", err)
	}
	viper.Set("s3.b2-eu-cen.key", "test-key")
	viper.Set("s3.b2-eu-cen.secret", "test-secret")
	viper.Set("s3.b2-eu-cen.endpoint", "http://localhost:9000")
	viper.Set("s3.b2-eu-cen.region", "us-east-1")
	viper.Set("s3.b2-eu-cen.bucket", "test-bucket")
	viper.Set("s3.b2-eu-cen.disable_ssl", true)
	viper.Set("s3.use_path_style_urls", true)
	viper.Set("s3.attachment-config.profile_picture.primaryBucket", "b2-eu-cen")
	t.Cleanup(viper.Reset)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	gin.SetMode(gin.TestMode)
	recorder := httptest.NewRecorder()
	ctx, _ := gin.CreateTestContext(recorder)
	ctx.Request = httptest.NewRequest("GET", "/", nil)
	ctx.Request.Header.Set("X-Auth-User-ID", "1")

	s3Cfg := s3config.NewS3Config()
	objectCleanupRepo := &repo.ObjectCleanupRepository{DB: db}
	objectCleanupCtrl := &basecontroller.ObjectCleanupController{Repo: objectCleanupRepo}
	contactRepository := &contactrepo.Repository{
		DB:                  db,
		ObjectCleanupRepo:   objectCleanupRepo,
		SecretEncryptionKey: testutil.SecretEncryptionKey(),
	}
	ctrl := New(contactRepository, objectCleanupCtrl, s3Cfg)
	ctrl.verifyAttachmentFn = func(bucketID string, objectKey string, expectedSize int64) error {
		return nil
	}
	return ctrl, db, ctx, s3Cfg
}

func createContactForTest(
	t *testing.T,
	db *sql.DB,
	ctrl *Controller,
	ctx *gin.Context,
	contactUserID int64,
	encryptedKey string,
	encryptedData string,
) *contactmodel.Entity {
	t.Helper()
	mustInsertTestUser(t, db, contactUserID)
	mustInsertEmergencyContact(t, db, 1, contactUserID, ente.UserInvitedContact)
	entity, err := ctrl.Create(ctx, contactmodel.CreateRequest{
		ContactUserID: contactUserID,
		EncryptedKey:  []byte(encryptedKey),
		EncryptedData: []byte(encryptedData),
	})
	if err != nil {
		t.Fatalf("Create() error = %v", err)
	}
	return entity
}

func mustInsertTestUser(t *testing.T, db *sql.DB, userID int64) {
	t.Helper()
	var existing int64
	err := db.QueryRow(`SELECT user_id FROM users WHERE user_id = $1`, userID).Scan(&existing)
	if err == nil {
		return
	}
	if !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("failed to check existing user %d: %v", userID, err)
	}

	testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       userID,
		Email:        fmt.Sprintf("contacts-%d@ente.com", userID),
		CreationTime: 1,
	})
}

func mustInsertEmergencyContact(
	t *testing.T,
	db *sql.DB,
	userID int64,
	emergencyContactID int64,
	state ente.ContactState,
) {
	t.Helper()
	mustInsertTestUser(t, db, userID)
	mustInsertTestUser(t, db, emergencyContactID)

	var encryptedKey *string
	if state == ente.UserInvitedContact || state == ente.ContactAccepted {
		value := "encrypted-emergency-key"
		encryptedKey = &value
	}
	_, err := db.Exec(
		`INSERT INTO emergency_contact(
		    user_id, emergency_contact_id, state, notice_period_in_hrs, encrypted_key
		) VALUES($1, $2, $3, $4, $5)`,
		userID,
		emergencyContactID,
		state,
		24,
		encryptedKey,
	)
	if err != nil {
		t.Fatalf(
			"failed to insert emergency contact relationship %d->%d in state %s: %v",
			userID,
			emergencyContactID,
			state,
			err,
		)
	}
}

func mustSetSharedFamilyAdmin(t *testing.T, db *sql.DB, adminID int64, memberIDs ...int64) {
	t.Helper()
	mustInsertTestUser(t, db, adminID)

	if _, err := db.Exec(
		`UPDATE users SET family_admin_id = $1 WHERE user_id = $1`,
		adminID,
	); err != nil {
		t.Fatalf("failed to set family_admin_id for admin %d: %v", adminID, err)
	}
	if _, err := db.Exec(
		`INSERT INTO families(id, admin_id, member_id, status) VALUES(gen_random_uuid(), $1, $1, $2)
		 ON CONFLICT (admin_id, member_id) DO NOTHING`,
		adminID,
		ente.SELF,
	); err != nil {
		t.Fatalf("failed to insert self family membership for admin %d: %v", adminID, err)
	}

	for _, memberID := range memberIDs {
		mustInsertTestUser(t, db, memberID)
		if _, err := db.Exec(
			`UPDATE users SET family_admin_id = $1 WHERE user_id = $2`,
			adminID,
			memberID,
		); err != nil {
			t.Fatalf("failed to set family_admin_id for member %d: %v", memberID, err)
		}
		if _, err := db.Exec(
			`INSERT INTO families(id, admin_id, member_id, status) VALUES(gen_random_uuid(), $1, $2, $3)
			 ON CONFLICT (admin_id, member_id) DO NOTHING`,
			adminID,
			memberID,
			ente.ACCEPTED,
		); err != nil {
			t.Fatalf("failed to insert active family membership %d->%d: %v", adminID, memberID, err)
		}
	}
}

func mustInsertFamilyInvite(t *testing.T, db *sql.DB, adminID int64, memberID int64) {
	t.Helper()
	mustInsertTestUser(t, db, adminID)
	mustInsertTestUser(t, db, memberID)
	if _, err := db.Exec(
		`INSERT INTO families(id, admin_id, member_id, status, token) VALUES(gen_random_uuid(), $1, $2, $3, $4)`,
		adminID,
		memberID,
		ente.INVITED,
		fmt.Sprintf("invite-token-%d-%d", adminID, memberID),
	); err != nil {
		t.Fatalf("failed to insert invited family relationship %d->%d: %v", adminID, memberID, err)
	}
}

func mustInsertSharedCollection(t *testing.T, db *sql.DB, ownerID int64, shareeIDs ...int64) int64 {
	t.Helper()
	mustInsertTestUser(t, db, ownerID)
	var collectionID int64
	err := db.QueryRow(
		`INSERT INTO collections(owner_id, encrypted_key, key_decryption_nonce, name, type, attributes, updation_time, is_deleted, app)
		 VALUES($1, $2, $3, $4, $5, $6::jsonb, $7, $8, $9)
		 RETURNING collection_id`,
		ownerID,
		"encrypted-key",
		"key-nonce",
		"Test collection",
		"album",
		"{}",
		int64(1),
		false,
		string(ente.Photos),
	).Scan(&collectionID)
	if err != nil {
		t.Fatalf("failed to insert shared collection for owner %d: %v", ownerID, err)
	}
	for _, shareeID := range shareeIDs {
		mustInsertTestUser(t, db, shareeID)
		if _, err := db.Exec(
			`INSERT INTO collection_shares(collection_id, from_user_id, to_user_id, encrypted_key, updation_time, role_type, shared_at)
			 VALUES($1, $2, $3, $4, $5, $6, $7)`,
			collectionID,
			ownerID,
			shareeID,
			"share-key",
			int64(1),
			string(ente.VIEWER),
			int64(1),
		); err != nil {
			t.Fatalf("failed to insert collection share for collection %d to user %d: %v", collectionID, shareeID, err)
		}
	}
	return collectionID
}

func TestContactCRUDAndDiff(t *testing.T) {
	ctrl, db, ctx, _ := setupContactControllerTest(t)
	mustInsertTestUser(t, db, 1)

	created := createContactForTest(t, db, ctrl, ctx, 11, "wrapped-key-1", "payload-1")
	if !strings.HasPrefix(created.ID, "ct_") {
		t.Fatalf("contact id = %q, want ct_ prefix", created.ID)
	}
	if created.ContactUserID != 11 {
		t.Fatalf("contactUserID = %d, want 11", created.ContactUserID)
	}
	expectedCreateEmail := "contacts-11@ente.com"
	if created.Email == nil || *created.Email != expectedCreateEmail {
		t.Fatalf("email = %v, want %q", created.Email, expectedCreateEmail)
	}
	if created.EncryptedKey == nil || string(*created.EncryptedKey) != "wrapped-key-1" {
		t.Fatalf("unexpected encrypted key: %v", created.EncryptedKey)
	}

	got, err := ctrl.Get(ctx, created.ID)
	if err != nil {
		t.Fatalf("Get() error = %v", err)
	}
	if got.ID != created.ID {
		t.Fatalf("Get().ID = %q, want %q", got.ID, created.ID)
	}
	if got.Email == nil || *got.Email != expectedCreateEmail {
		t.Fatalf("Get().Email = %v, want %q", got.Email, expectedCreateEmail)
	}

	mustInsertTestUser(t, db, 12)
	mustInsertEmergencyContact(t, db, 1, 12, ente.UserInvitedContact)

	updated, err := ctrl.Update(ctx, created.ID, contactmodel.UpdateRequest{
		ContactUserID: 12,
		EncryptedData: []byte("payload-2"),
	})
	if err != nil {
		t.Fatalf("Update() error = %v", err)
	}
	if updated.ContactUserID != 12 {
		t.Fatalf("updated contactUserID = %d, want 12", updated.ContactUserID)
	}
	expectedUpdatedEmail := "contacts-12@ente.com"
	if updated.Email == nil || *updated.Email != expectedUpdatedEmail {
		t.Fatalf("updated email = %v, want %q", updated.Email, expectedUpdatedEmail)
	}
	if updated.EncryptedData == nil || string(*updated.EncryptedData) != "payload-2" {
		t.Fatalf("updated encrypted data = %v", updated.EncryptedData)
	}

	diff, err := ctrl.GetDiff(ctx, contactmodel.DiffRequest{
		SinceTime: ptrInt64(0),
		Limit:     10,
	})
	if err != nil {
		t.Fatalf("GetDiff() error = %v", err)
	}
	if len(diff) != 1 {
		t.Fatalf("diff length = %d, want 1", len(diff))
	}
	if diff[0].ID != created.ID || diff[0].ContactUserID != 12 {
		t.Fatalf("unexpected diff row: %+v", diff[0])
	}
	if diff[0].Email == nil || *diff[0].Email != expectedUpdatedEmail {
		t.Fatalf("unexpected diff email: %v", diff[0].Email)
	}

	if err := ctrl.Delete(ctx, created.ID); err != nil {
		t.Fatalf("Delete() error = %v", err)
	}
	deleted, err := ctrl.Get(ctx, created.ID)
	if err != nil {
		t.Fatalf("Get() after delete error = %v", err)
	}
	if !deleted.IsDeleted {
		t.Fatalf("deleted contact should be tombstoned")
	}
	if deleted.EncryptedKey != nil || deleted.EncryptedData != nil || deleted.ProfilePictureAttachmentID != nil {
		t.Fatalf("deleted contact leaked encrypted fields or attachment ref: %+v", deleted)
	}
	if deleted.Email != nil {
		t.Fatalf("deleted contact leaked email: %+v", deleted)
	}
}

func TestUpdateRevivesDeletedContact(t *testing.T) {
	ctrl, db, ctx, _ := setupContactControllerTest(t)
	mustInsertTestUser(t, db, 1)

	created := createContactForTest(t, db, ctrl, ctx, 31, "wrapped-key-1", "payload-1")
	if err := ctrl.Delete(ctx, created.ID); err != nil {
		t.Fatalf("Delete() error = %v", err)
	}

	mustInsertTestUser(t, db, 32)
	mustInsertEmergencyContact(t, db, 1, 32, ente.UserInvitedContact)

	revived, err := ctrl.Update(ctx, created.ID, contactmodel.UpdateRequest{
		ContactUserID: 32,
		EncryptedData: []byte("payload-2"),
	})
	if err != nil {
		t.Fatalf("Update() revive error = %v", err)
	}
	if revived.IsDeleted {
		t.Fatal("revived contact should not remain deleted")
	}
	if revived.ContactUserID != 32 {
		t.Fatalf("revived contactUserID = %d, want 32", revived.ContactUserID)
	}
	if revived.EncryptedData == nil || string(*revived.EncryptedData) != "payload-2" {
		t.Fatalf("revived encrypted data = %v, want payload-2", revived.EncryptedData)
	}
	expectedEmail := "contacts-32@ente.com"
	if revived.Email == nil || *revived.Email != expectedEmail {
		t.Fatalf("revived email = %v, want %q", revived.Email, expectedEmail)
	}
}

func TestCreateContactRejectsDuplicateContactUserID(t *testing.T) {
	ctrl, db, ctx, _ := setupContactControllerTest(t)
	mustInsertTestUser(t, db, 1)

	createContactForTest(t, db, ctrl, ctx, 21, "wrapped-key-1", "payload-1")
	_, err := ctrl.Create(ctx, contactmodel.CreateRequest{
		ContactUserID: 21,
		EncryptedKey:  []byte("wrapped-key-2"),
		EncryptedData: []byte("payload-2"),
	})
	if err == nil {
		t.Fatal("expected duplicate contactUserID create to fail")
	}
}

func TestCreateContactRequiresEligibleRelationship(t *testing.T) {
	ctrl, db, ctx, _ := setupContactControllerTest(t)
	mustInsertTestUser(t, db, 1)
	mustInsertTestUser(t, db, 71)

	_, err := ctrl.Create(ctx, contactmodel.CreateRequest{
		ContactUserID: 71,
		EncryptedKey:  []byte("wrapped-key"),
		EncryptedData: []byte("payload"),
	})
	if err == nil {
		t.Fatal("expected ineligible contact create to fail")
	}
	if !strings.Contains(err.Error(), "not eligible to be added as a contact") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestUpdateContactRequiresEligibleRelationshipWhenContactUserIDChanges(t *testing.T) {
	ctrl, db, ctx, _ := setupContactControllerTest(t)
	created := createContactForTest(t, db, ctrl, ctx, 21, "wrapped-key-1", "payload-1")
	mustInsertTestUser(t, db, 22)

	_, err := ctrl.Update(ctx, created.ID, contactmodel.UpdateRequest{
		ContactUserID: 22,
		EncryptedData: []byte("payload-2"),
	})
	if err == nil {
		t.Fatal("expected ineligible contact update to fail")
	}
	if !strings.Contains(err.Error(), "not eligible to be added as a contact") {
		t.Fatalf("unexpected error: %v", err)
	}

	got, err := ctrl.Get(ctx, created.ID)
	if err != nil {
		t.Fatalf("Get() error = %v", err)
	}
	if got.ContactUserID != 21 {
		t.Fatalf("contactUserID = %d, want 21", got.ContactUserID)
	}
	if got.Email == nil || *got.Email != "contacts-21@ente.com" {
		t.Fatalf("email = %v, want contacts-21@ente.com", got.Email)
	}
	if got.EncryptedData == nil || string(*got.EncryptedData) != "payload-1" {
		t.Fatalf("encryptedData = %v, want payload-1", got.EncryptedData)
	}
}

func TestUpdateContactAllowsSameContactUserIDAfterRelationshipEnds(t *testing.T) {
	ctrl, db, ctx, _ := setupContactControllerTest(t)
	created := createContactForTest(t, db, ctrl, ctx, 31, "wrapped-key-1", "payload-1")
	if _, err := db.Exec(
		`UPDATE emergency_contact
		    SET state = $1,
		        encrypted_key = NULL
		  WHERE user_id = $2 AND emergency_contact_id = $3`,
		ente.ContactLeft,
		int64(1),
		int64(31),
	); err != nil {
		t.Fatalf("failed to end emergency contact relationship: %v", err)
	}

	updated, err := ctrl.Update(ctx, created.ID, contactmodel.UpdateRequest{
		ContactUserID: 31,
		EncryptedData: []byte("payload-2"),
	})
	if err != nil {
		t.Fatalf("Update() error = %v", err)
	}
	if updated.ContactUserID != 31 {
		t.Fatalf("contactUserID = %d, want 31", updated.ContactUserID)
	}
	if updated.Email == nil || *updated.Email != "contacts-31@ente.com" {
		t.Fatalf("email = %v, want contacts-31@ente.com", updated.Email)
	}
	if updated.EncryptedData == nil || string(*updated.EncryptedData) != "payload-2" {
		t.Fatalf("encryptedData = %v, want payload-2", updated.EncryptedData)
	}
}

func TestUpdateContactRequiresEligibleRelationshipToReviveDeletedContact(t *testing.T) {
	ctrl, db, ctx, _ := setupContactControllerTest(t)
	created := createContactForTest(t, db, ctrl, ctx, 41, "wrapped-key-1", "payload-1")
	if err := ctrl.Delete(ctx, created.ID); err != nil {
		t.Fatalf("Delete() error = %v", err)
	}
	if _, err := db.Exec(
		`UPDATE emergency_contact
		    SET state = $1,
		        encrypted_key = NULL
		  WHERE user_id = $2 AND emergency_contact_id = $3`,
		ente.ContactLeft,
		int64(1),
		int64(41),
	); err != nil {
		t.Fatalf("failed to end emergency contact relationship: %v", err)
	}

	_, err := ctrl.Update(ctx, created.ID, contactmodel.UpdateRequest{
		ContactUserID: 41,
		EncryptedData: []byte("payload-2"),
	})
	if err == nil {
		t.Fatal("expected ineligible deleted contact update to fail")
	}
	if !strings.Contains(err.Error(), "not eligible to be added as a contact") {
		t.Fatalf("unexpected error: %v", err)
	}

	got, err := ctrl.Get(ctx, created.ID)
	if err != nil {
		t.Fatalf("Get() error = %v", err)
	}
	if !got.IsDeleted {
		t.Fatalf("contact should remain deleted: %+v", got)
	}
	if got.ContactUserID != 41 {
		t.Fatalf("contactUserID = %d, want 41", got.ContactUserID)
	}
	if got.Email != nil {
		t.Fatalf("deleted contact leaked email: %v", got.Email)
	}
	if got.EncryptedData != nil {
		t.Fatalf("deleted contact restored encryptedData: %v", got.EncryptedData)
	}
}

func TestCreateAndUpdateRejectUnknownContactUserID(t *testing.T) {
	ctrl, db, ctx, _ := setupContactControllerTest(t)
	mustInsertTestUser(t, db, 1)

	_, err := ctrl.Create(ctx, contactmodel.CreateRequest{
		ContactUserID: 9999,
		EncryptedKey:  []byte("wrapped-key"),
		EncryptedData: []byte("payload"),
	})
	if err == nil || !strings.Contains(err.Error(), "contactUserID does not exist") {
		t.Fatalf("expected unknown contact user create to fail, got %v", err)
	}

	created := createContactForTest(t, db, ctrl, ctx, 21, "wrapped-key-1", "payload-1")
	_, err = ctrl.Update(ctx, created.ID, contactmodel.UpdateRequest{
		ContactUserID: 9999,
		EncryptedData: []byte("payload-2"),
	})
	if err == nil || !strings.Contains(err.Error(), "contactUserID does not exist") {
		t.Fatalf("expected unknown contact user update to fail, got %v", err)
	}
}

func TestCreateContactAllowedForEmergencyRelationshipInEitherDirection(t *testing.T) {
	tests := []struct {
		name  string
		setup func(t *testing.T, db *sql.DB)
	}{
		{
			name: "actor invited target",
			setup: func(t *testing.T, db *sql.DB) {
				mustInsertEmergencyContact(t, db, 1, 72, ente.UserInvitedContact)
			},
		},
		{
			name: "target invited actor",
			setup: func(t *testing.T, db *sql.DB) {
				mustInsertEmergencyContact(t, db, 72, 1, ente.UserInvitedContact)
			},
		},
		{
			name: "accepted relationship",
			setup: func(t *testing.T, db *sql.DB) {
				mustInsertEmergencyContact(t, db, 1, 72, ente.ContactAccepted)
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			ctrl, db, ctx, _ := setupContactControllerTest(t)
			mustInsertTestUser(t, db, 1)
			mustInsertTestUser(t, db, 72)
			tc.setup(t, db)

			created, err := ctrl.Create(ctx, contactmodel.CreateRequest{
				ContactUserID: 72,
				EncryptedKey:  []byte("wrapped-key"),
				EncryptedData: []byte("payload"),
			})
			if err != nil {
				t.Fatalf("Create() error = %v", err)
			}
			if created.ContactUserID != 72 {
				t.Fatalf("contactUserID = %d, want 72", created.ContactUserID)
			}
		})
	}
}

func TestCreateContactRejectsHistoricalEmergencyRelationship(t *testing.T) {
	states := []ente.ContactState{
		ente.UserRevokedContact,
		ente.ContactLeft,
		ente.ContactDenied,
	}

	for _, state := range states {
		t.Run(string(state), func(t *testing.T) {
			ctrl, db, ctx, _ := setupContactControllerTest(t)
			mustInsertTestUser(t, db, 1)
			mustInsertEmergencyContact(t, db, 1, 73, state)

			_, err := ctrl.Create(ctx, contactmodel.CreateRequest{
				ContactUserID: 73,
				EncryptedKey:  []byte("wrapped-key"),
				EncryptedData: []byte("payload"),
			})
			if err == nil {
				t.Fatalf("expected state %s to be ineligible", state)
			}
		})
	}
}

func TestCreateContactAllowedForSharedActiveFamily(t *testing.T) {
	ctrl, db, ctx, _ := setupContactControllerTest(t)
	mustSetSharedFamilyAdmin(t, db, 90, 1, 74)

	created, err := ctrl.Create(ctx, contactmodel.CreateRequest{
		ContactUserID: 74,
		EncryptedKey:  []byte("wrapped-key"),
		EncryptedData: []byte("payload"),
	})
	if err != nil {
		t.Fatalf("Create() error = %v", err)
	}
	if created.ContactUserID != 74 {
		t.Fatalf("contactUserID = %d, want 74", created.ContactUserID)
	}
}

func TestCreateContactRejectsInactiveFamilyRelationship(t *testing.T) {
	ctrl, db, ctx, _ := setupContactControllerTest(t)
	mustInsertTestUser(t, db, 1)
	mustInsertFamilyInvite(t, db, 91, 75)

	_, err := ctrl.Create(ctx, contactmodel.CreateRequest{
		ContactUserID: 75,
		EncryptedKey:  []byte("wrapped-key"),
		EncryptedData: []byte("payload"),
	})
	if err == nil {
		t.Fatal("expected invited-only family relationship to be ineligible")
	}
}

func TestCreateContactAllowedForSharedCollectionAccess(t *testing.T) {
	tests := []struct {
		name  string
		setup func(t *testing.T, db *sql.DB)
	}{
		{
			name: "owner shared directly with contact",
			setup: func(t *testing.T, db *sql.DB) {
				mustInsertSharedCollection(t, db, 1, 76)
			},
		},
		{
			name: "both share same third-party collection",
			setup: func(t *testing.T, db *sql.DB) {
				mustInsertSharedCollection(t, db, 300, 1, 76)
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			ctrl, db, ctx, _ := setupContactControllerTest(t)
			mustInsertTestUser(t, db, 1)
			mustInsertTestUser(t, db, 76)
			tc.setup(t, db)

			created, err := ctrl.Create(ctx, contactmodel.CreateRequest{
				ContactUserID: 76,
				EncryptedKey:  []byte("wrapped-key"),
				EncryptedData: []byte("payload"),
			})
			if err != nil {
				t.Fatalf("Create() error = %v", err)
			}
			if created.ContactUserID != 76 {
				t.Fatalf("contactUserID = %d, want 76", created.ContactUserID)
			}
		})
	}
}

func TestTouchContactsForContactUserRefreshesResolvedEmailInDiff(t *testing.T) {
	ctrl, db, ctx, _ := setupContactControllerTest(t)
	mustInsertTestUser(t, db, 1)

	created := createContactForTest(t, db, ctrl, ctx, 82, "wrapped-key-1", "payload-1")

	userRepo := &repo.UserRepository{
		DB:                  db,
		SecretEncryptionKey: testutil.SecretEncryptionKey(),
		HashingKey:          testutil.HashingKey(),
	}
	encryptedEmail, err := crypto.Encrypt("updated-82@ente.com", testutil.SecretEncryptionKey())
	if err != nil {
		t.Fatalf("failed to encrypt email: %v", err)
	}
	emailHash, err := crypto.GetHash("updated-82@ente.com", testutil.HashingKey())
	if err != nil {
		t.Fatalf("failed to hash email: %v", err)
	}
	if err := userRepo.UpdateEmail(82, encryptedEmail, emailHash); err != nil {
		t.Fatalf("failed to update user email: %v", err)
	}
	if err := ctrl.Repo.TouchContactsForContactUser(ctx, 82); err != nil {
		t.Fatalf("failed to touch contacts for updated email: %v", err)
	}

	diff, err := ctrl.GetDiff(ctx, contactmodel.DiffRequest{
		SinceTime: ptrInt64(created.UpdatedAt),
		Limit:     10,
	})
	if err != nil {
		t.Fatalf("GetDiff() error = %v", err)
	}
	if len(diff) != 1 {
		t.Fatalf("diff length = %d, want 1", len(diff))
	}
	if diff[0].Email == nil || *diff[0].Email != "updated-82@ente.com" {
		t.Fatalf("resolved email = %v, want updated email", diff[0].Email)
	}
}

func TestContactEntityEncryptedKeyIsImmutable(t *testing.T) {
	ctrl, db, ctx, _ := setupContactControllerTest(t)
	mustInsertTestUser(t, db, 1)

	created := createContactForTest(t, db, ctrl, ctx, 31, "wrapped-key-1", "payload-1")
	if _, err := db.Exec(`UPDATE contact_entity SET encrypted_key = $1 WHERE id = $2`, []byte("wrapped-key-2"), created.ID); err == nil {
		t.Fatal("expected encrypted_key update to fail")
	}
}

func TestDeletedContactMustClearProfilePictureReference(t *testing.T) {
	ctrl, db, ctx, _ := setupContactControllerTest(t)
	mustInsertTestUser(t, db, 1)

	created := createContactForTest(t, db, ctrl, ctx, 35, "wrapped-key-1", "payload-1")
	if _, err := db.Exec(
		`UPDATE contact_entity
		    SET is_deleted = TRUE, encrypted_data = NULL, profile_picture_attachment_id = $1
		  WHERE id = $2`,
		"ua_fakeAttachment",
		created.ID,
	); err == nil {
		t.Fatal("expected deleted contact with profile picture ref to violate constraint")
	}
}

func TestUserAttachmentsRejectDuplicateBucketMembership(t *testing.T) {
	_, db, _, _ := setupContactControllerTest(t)
	mustInsertTestUser(t, db, 1)

	_, err := db.Exec(
		`INSERT INTO user_attachments(
		    attachment_id, user_id, attachment_type, size, latest_bucket, replicated_buckets
		) VALUES($1, $2, $3, $4, $5, ARRAY[$6]::s3region[])`,
		"ua_duplicateBuckets",
		1,
		"profile_picture",
		128,
		"b2-eu-cen",
		"b2-eu-cen",
	)
	if err == nil {
		t.Fatal("expected duplicate attachment bucket membership to fail")
	}
}

func TestAttachmentLifecycle(t *testing.T) {
	ctrl, db, ctx, s3Cfg := setupContactControllerTest(t)
	mustInsertTestUser(t, db, 1)

	created := createContactForTest(t, db, ctrl, ctx, 41, "wrapped-key-1", "payload-1")

	upload1, err := ctrl.GetAttachmentUploadURL(ctx, string(contactmodel.ProfilePicture), contactmodel.AttachmentUploadURLRequest{
		ContentLength: 128,
		ContentMD5:    "ZmFrZS1tZDU=",
	})
	if err != nil {
		t.Fatalf("GetAttachmentUploadURL() error = %v", err)
	}
	if !strings.HasPrefix(upload1.AttachmentID, "ua_") {
		t.Fatalf("attachment id = %q, want ua_ prefix", upload1.AttachmentID)
	}

	objectKey1 := contactmodel.AttachmentObjectKey(1, contactmodel.ProfilePicture, upload1.AttachmentID)
	var bucketID string
	if err := db.QueryRow(`SELECT bucket_id FROM temp_objects WHERE object_key = $1`, objectKey1).Scan(&bucketID); err != nil {
		t.Fatalf("temp_objects lookup failed: %v", err)
	}
	if bucketID != s3Cfg.GetAttachmentBucketID(string(contactmodel.ProfilePicture)) {
		t.Fatalf("bucket_id = %q, want %q", bucketID, s3Cfg.GetAttachmentBucketID(string(contactmodel.ProfilePicture)))
	}

	withPicture, err := ctrl.AttachContactAttachment(ctx, created.ID, string(contactmodel.ProfilePicture), contactmodel.CommitAttachmentRequest{
		AttachmentID: upload1.AttachmentID,
		Size:         128,
	})
	if err != nil {
		t.Fatalf("AttachContactAttachment() error = %v", err)
	}
	if withPicture.ProfilePictureAttachmentID == nil || *withPicture.ProfilePictureAttachmentID != upload1.AttachmentID {
		t.Fatalf("unexpected profile picture ref after attach: %+v", withPicture)
	}
	if err := db.QueryRow(`SELECT bucket_id FROM temp_objects WHERE object_key = $1`, objectKey1).Scan(&bucketID); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("temp_objects row should be removed after attach, got err=%v bucket=%q", err, bucketID)
	}

	signedURL, err := ctrl.GetAttachmentURL(ctx, string(contactmodel.ProfilePicture), upload1.AttachmentID)
	if err != nil {
		t.Fatalf("GetAttachmentURL() error = %v", err)
	}
	if signedURL.URL == "" {
		t.Fatal("expected signed attachment url")
	}

	upload2, err := ctrl.GetAttachmentUploadURL(ctx, string(contactmodel.ProfilePicture), contactmodel.AttachmentUploadURLRequest{
		ContentLength: 256,
		ContentMD5:    "ZmFrZS1tZDUtMg==",
	})
	if err != nil {
		t.Fatalf("second GetAttachmentUploadURL() error = %v", err)
	}
	replaced, err := ctrl.AttachContactAttachment(ctx, created.ID, string(contactmodel.ProfilePicture), contactmodel.CommitAttachmentRequest{
		AttachmentID: upload2.AttachmentID,
		Size:         256,
	})
	if err != nil {
		t.Fatalf("second AttachContactAttachment() error = %v", err)
	}
	if replaced.ProfilePictureAttachmentID == nil || *replaced.ProfilePictureAttachmentID != upload2.AttachmentID {
		t.Fatalf("unexpected profile picture ref after replace: %+v", replaced)
	}

	oldAttachment, err := ctrl.Repo.GetAttachment(ctx, 1, upload1.AttachmentID)
	if err != nil {
		t.Fatalf("GetAttachment(old) error = %v", err)
	}
	if !oldAttachment.IsDeleted {
		t.Fatalf("old attachment should be marked deleted after replace")
	}

	cleared, err := ctrl.DeleteContactAttachment(ctx, created.ID, string(contactmodel.ProfilePicture))
	if err != nil {
		t.Fatalf("DeleteContactAttachment() error = %v", err)
	}
	if cleared.ProfilePictureAttachmentID != nil {
		t.Fatalf("profile picture should be cleared, got %+v", cleared.ProfilePictureAttachmentID)
	}
	newAttachment, err := ctrl.Repo.GetAttachment(ctx, 1, upload2.AttachmentID)
	if err != nil {
		t.Fatalf("GetAttachment(new) error = %v", err)
	}
	if !newAttachment.IsDeleted {
		t.Fatalf("current attachment should be marked deleted after picture removal")
	}
}

func TestAttachContactAttachmentFailsWhenStagedObjectVerificationFails(t *testing.T) {
	ctrl, db, ctx, _ := setupContactControllerTest(t)
	mustInsertTestUser(t, db, 1)

	created := createContactForTest(t, db, ctrl, ctx, 42, "wrapped-key-1", "payload-1")
	upload, err := ctrl.GetAttachmentUploadURL(ctx, string(contactmodel.ProfilePicture), contactmodel.AttachmentUploadURLRequest{
		ContentLength: 128,
		ContentMD5:    "ZmFrZS1tZDU=",
	})
	if err != nil {
		t.Fatalf("GetAttachmentUploadURL() error = %v", err)
	}

	ctrl.verifyAttachmentFn = func(bucketID string, objectKey string, expectedSize int64) error {
		return errors.New("staged object missing")
	}

	if _, err := ctrl.AttachContactAttachment(ctx, created.ID, string(contactmodel.ProfilePicture), contactmodel.CommitAttachmentRequest{
		AttachmentID: upload.AttachmentID,
		Size:         128,
	}); err == nil {
		t.Fatal("expected attach to fail when staged object verification fails")
	}

	objectKey := contactmodel.AttachmentObjectKey(1, contactmodel.ProfilePicture, upload.AttachmentID)
	var bucketID string
	if err := db.QueryRow(`SELECT bucket_id FROM temp_objects WHERE object_key = $1`, objectKey).Scan(&bucketID); err != nil {
		t.Fatalf("temp_objects row should remain after failed attach, err=%v", err)
	}
	if _, err := ctrl.Repo.GetAttachment(ctx, 1, upload.AttachmentID); err == nil {
		t.Fatal("attachment row should not be created when staged verification fails")
	} else if !errors.Is(err, &ente.ErrNotFoundError) {
		t.Fatalf("unexpected GetAttachment error = %v", err)
	}

	refetched, err := ctrl.Get(ctx, created.ID)
	if err != nil {
		t.Fatalf("Get() error = %v", err)
	}
	if refetched.ProfilePictureAttachmentID != nil {
		t.Fatalf("contact should not reference profile picture after failed attach")
	}
}

func TestDeleteContactMarksCurrentProfilePictureDeleted(t *testing.T) {
	ctrl, db, ctx, _ := setupContactControllerTest(t)
	mustInsertTestUser(t, db, 1)

	created := createContactForTest(t, db, ctrl, ctx, 51, "wrapped-key-1", "payload-1")
	upload, err := ctrl.GetAttachmentUploadURL(ctx, string(contactmodel.ProfilePicture), contactmodel.AttachmentUploadURLRequest{
		ContentLength: 128,
		ContentMD5:    "ZmFrZS1tZDU=",
	})
	if err != nil {
		t.Fatalf("GetAttachmentUploadURL() error = %v", err)
	}
	withPicture, err := ctrl.AttachContactAttachment(ctx, created.ID, string(contactmodel.ProfilePicture), contactmodel.CommitAttachmentRequest{
		AttachmentID: upload.AttachmentID,
		Size:         128,
	})
	if err != nil {
		t.Fatalf("AttachContactAttachment() error = %v", err)
	}
	if withPicture.ProfilePictureAttachmentID == nil {
		t.Fatal("expected profile picture ref before delete")
	}

	if err := ctrl.Delete(ctx, created.ID); err != nil {
		t.Fatalf("Delete() error = %v", err)
	}
	attachment, err := ctrl.Repo.GetAttachment(ctx, 1, upload.AttachmentID)
	if err != nil {
		t.Fatalf("GetAttachment() error = %v", err)
	}
	if !attachment.IsDeleted {
		t.Fatalf("attachment should be marked deleted when contact is deleted")
	}
	deleted, err := ctrl.Get(ctx, created.ID)
	if err != nil {
		t.Fatalf("Get() after delete error = %v", err)
	}
	if deleted.ProfilePictureAttachmentID != nil {
		t.Fatalf("deleted contact should not reference profile picture")
	}
}

func TestAttachmentUploadURLRejectsInvalidType(t *testing.T) {
	ctrl, _, ctx, _ := setupContactControllerTest(t)

	_, err := ctrl.GetAttachmentUploadURL(ctx, "unknown_type", contactmodel.AttachmentUploadURLRequest{
		ContentLength: 128,
		ContentMD5:    "ZmFrZS1tZDU=",
	})
	if err == nil {
		t.Fatal("expected invalid attachment type error")
	}
}

func TestGetAttachmentURLRejectsWrongUserAndDeletedRows(t *testing.T) {
	ctrl, db, ctx, _ := setupContactControllerTest(t)
	mustInsertTestUser(t, db, 1)
	mustInsertTestUser(t, db, 2)

	mustInsertAttachmentRow(t, db, "ua_owned", 1, false, "b2-eu-cen", nil, nil, nil)
	if _, err := ctrl.GetAttachmentURL(ctx, string(contactmodel.ProfilePicture), "ua_owned"); err != nil {
		t.Fatalf("GetAttachmentURL() for owner error = %v", err)
	}

	ctxOther := ctx.Copy()
	ctxOther.Request = ctx.Request.Clone(ctx.Request.Context())
	ctxOther.Request.Header.Set("X-Auth-User-ID", "2")
	if _, err := ctrl.GetAttachmentURL(ctxOther, string(contactmodel.ProfilePicture), "ua_owned"); err == nil {
		t.Fatal("expected wrong-user attachment lookup to fail")
	}

	mustInsertAttachmentRow(t, db, "ua_deleted", 1, true, "b2-eu-cen", nil, []string{"scw-eu-fr"}, nil)
	if _, err := ctrl.GetAttachmentURL(ctx, string(contactmodel.ProfilePicture), "ua_deleted"); err == nil {
		t.Fatal("expected deleted attachment lookup to fail")
	}

	if _, err := ctrl.GetAttachmentURL(ctx, "unknown_type", "ua_owned"); err == nil {
		t.Fatal("expected invalid attachment type error")
	}
}

func TestAttachmentReplicationLifecycle(t *testing.T) {
	ctrl, db, _, _ := setupContactControllerTest(t)
	mustInsertTestUser(t, db, 1)
	viper.Set("s3.attachment-config.profile_picture.primaryBucket", "b2-eu-cen")
	viper.Set("s3.attachment-config.profile_picture.replicaBuckets", []string{"scw-eu-fr"})
	ctrl.S3Config = s3config.NewS3Config()

	mustInsertAttachmentRow(t, db, "ua_replication", 1, false, "b2-eu-cen", nil, nil, nil)

	replicatedTo := make([]string, 0)
	ctrl.replicateAttachmentFn = func(_ context.Context, row contactmodel.Attachment, dstBucketID string) error {
		replicatedTo = append(replicatedTo, dstBucketID)
		if row.AttachmentID != "ua_replication" {
			t.Fatalf("unexpected attachment id %q", row.AttachmentID)
		}
		return nil
	}

	if err := ctrl.tryReplicate(); err != nil {
		t.Fatalf("tryReplicate() first pass error = %v", err)
	}
	if !reflect.DeepEqual(replicatedTo, []string{"scw-eu-fr"}) {
		t.Fatalf("replicated buckets = %v, want [scw-eu-fr]", replicatedTo)
	}

	attachment, err := ctrl.Repo.GetAttachment(t.Context(), 1, "ua_replication")
	if err != nil {
		t.Fatalf("GetAttachment() error = %v", err)
	}
	if !reflect.DeepEqual(attachment.ReplicatedBuckets, []string{"scw-eu-fr"}) {
		t.Fatalf("replicated buckets after first pass = %v", attachment.ReplicatedBuckets)
	}
	if attachment.PendingSync {
		t.Fatal("attachment should not be pending after replication is complete")
	}
}

func TestAttachmentDeletionLifecycle(t *testing.T) {
	ctrl, db, _, _ := setupContactControllerTest(t)
	mustInsertTestUser(t, db, 1)

	mustInsertAttachmentRow(t, db, "ua_delete", 1, true, "b2-eu-cen", nil, []string{"scw-eu-fr"}, nil)

	deletedFrom := make([]string, 0)
	ctrl.deleteAttachmentFn = func(row contactmodel.Attachment, bucketID string) error {
		deletedFrom = append(deletedFrom, bucketID)
		if row.AttachmentID != "ua_delete" {
			t.Fatalf("unexpected attachment id %q", row.AttachmentID)
		}
		return nil
	}

	if err := ctrl.tryDelete(); err != nil {
		t.Fatalf("tryDelete() error = %v", err)
	}

	if _, err := ctrl.Repo.GetAttachment(t.Context(), 1, "ua_delete"); err == nil {
		t.Fatal("attachment row should be removed after deletion")
	} else if !errors.Is(err, &ente.ErrNotFoundError) {
		t.Fatalf("unexpected GetAttachment error = %v", err)
	}

	sort.Strings(deletedFrom)
	if !reflect.DeepEqual(deletedFrom, []string{"b2-eu-cen", "scw-eu-fr"}) {
		t.Fatalf("deleted buckets = %v", deletedFrom)
	}
}

func ptrInt64(v int64) *int64 {
	return &v
}

func mustInsertAttachmentRow(
	t *testing.T,
	db *sql.DB,
	attachmentID string,
	userID int64,
	isDeleted bool,
	latestBucket string,
	replicatedBuckets []string,
	deleteFromBuckets []string,
	inflightBuckets []string,
) {
	t.Helper()
	if replicatedBuckets == nil {
		replicatedBuckets = []string{}
	}
	if deleteFromBuckets == nil {
		deleteFromBuckets = []string{}
	}
	if inflightBuckets == nil {
		inflightBuckets = []string{}
	}
	if _, err := db.Exec(
		`INSERT INTO user_attachments(
		    attachment_id, user_id, attachment_type, size, latest_bucket, replicated_buckets,
		    delete_from_buckets, inflight_rep_buckets, pending_sync, is_deleted
		) VALUES($1, $2, $3, $4, $5, $6::s3region[], $7::s3region[], $8::s3region[], TRUE, $9)`,
		attachmentID,
		userID,
		"profile_picture",
		128,
		latestBucket,
		pq.Array(replicatedBuckets),
		pq.Array(deleteFromBuckets),
		pq.Array(inflightBuckets),
		isDeleted,
	); err != nil {
		t.Fatalf("failed to insert attachment row: %v", err)
	}
}
