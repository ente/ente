package collections

import (
	"context"
	"database/sql"
	"errors"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	museumcontroller "github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/repo"
	castRepo "github.com/ente/museum/pkg/repo/cast"
	publicRepo "github.com/ente/museum/pkg/repo/public"
	"github.com/gin-gonic/gin"
)

type panicUserLookup struct{}

func (panicUserLookup) LookupUserID(int64, string) (int64, error) {
	panic("user lookup must not be called while revoking collection access")
}

func (panicUserLookup) VerifyUserID(int64, string, int64) error {
	panic("user lookup must not be called while revoking collection access")
}

type fixedUserLookup struct {
	userID int64
}

func (l fixedUserLookup) LookupUserID(int64, string) (int64, error) {
	return l.userID, nil
}

func (fixedUserLookup) VerifyUserID(int64, string, int64) error {
	return nil
}

func newShareTestCollectionRepo(db *sql.DB) *repo.CollectionRepository {
	return &repo.CollectionRepository{
		DB:                  db,
		CollectionLinkRepo:  publicRepo.NewCollectionLinkRepository(db, ""),
		SecretEncryptionKey: testutil.SecretEncryptionKey(),
	}
}

func newShareTestUserLookup(db *sql.DB) *museumcontroller.UserLookupController {
	return museumcontroller.NewUserLookupController(&repo.UserRepository{
		DB:         db,
		HashingKey: testutil.HashingKey(),
	}, nil)
}

func createShareTestCollection(t *testing.T, collectionRepo *repo.CollectionRepository, ownerID int64) int64 {
	return createShareTestCollectionOfType(t, collectionRepo, ownerID, "album")
}

func createShareTestCollectionOfType(
	t *testing.T,
	collectionRepo *repo.CollectionRepository,
	ownerID int64,
	collectionType string,
) int64 {
	t.Helper()
	collection, err := collectionRepo.Create(ente.Collection{
		Owner:              ente.CollectionUser{ID: ownerID},
		EncryptedKey:       "encrypted-key",
		KeyDecryptionNonce: "key-nonce",
		Name:               "Test collection",
		Type:               collectionType,
		Attributes:         ente.CollectionAttributes{},
		UpdationTime:       1,
		App:                string(ente.Photos),
	})
	if err != nil {
		t.Fatal(err)
	}
	return collection.ID
}

func setupCollectionShareTest(
	t *testing.T,
) (*sql.DB, *repo.CollectionRepository, int64, int64) {
	t.Helper()
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "owner@example.com",
		CreationTime: 1,
	})
	shareeID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       2,
		Email:        "sharee@example.com",
		CreationTime: 1,
	})
	return db, newShareTestCollectionRepo(db), ownerID, shareeID
}

func setShareTestFamilyAdmin(t *testing.T, db *sql.DB, userID int64, familyAdminID any) {
	t.Helper()
	if _, err := db.Exec(
		`UPDATE users SET family_admin_id = $1 WHERE user_id = $2`,
		familyAdminID,
		userID,
	); err != nil {
		t.Fatal(err)
	}
}

func requireCollectionShareStatus(
	t *testing.T,
	status, want ente.CollectionShareStatus,
	err error,
) {
	t.Helper()
	if err != nil || status != want {
		t.Fatalf("share status = %q, want %q; error = %v", status, want, err)
	}
}

func collectionUpdationTime(t *testing.T, db *sql.DB, collectionID int64) int64 {
	t.Helper()
	var updationTime int64
	err := db.QueryRow(
		`SELECT updation_time FROM collections WHERE collection_id = $1`,
		collectionID,
	).Scan(&updationTime)
	if err != nil {
		t.Fatal(err)
	}
	return updationTime
}

func addShareTestShare(
	t *testing.T,
	collectionRepo *repo.CollectionRepository,
	collectionID, ownerID, shareeID int64,
	role ente.CollectionParticipantRole,
) {
	t.Helper()
	if err := collectionRepo.Share(collectionID, ownerID, shareeID, "share-key", role, 1); err != nil {
		t.Fatal(err)
	}
}

func addShareTestOwnerFile(t *testing.T, db *sql.DB, collectionID, ownerID int64) int64 {
	t.Helper()
	var fileID int64
	err := db.QueryRow(
		`WITH inserted_file AS (
			INSERT INTO files(owner_id, file_decryption_header, thumbnail_decryption_header, metadata_decryption_header, encrypted_metadata, updation_time, info)
			VALUES($1, 'file-header', 'thumbnail-header', 'metadata-header', 'encrypted-metadata', 1, '{}'::jsonb)
			RETURNING file_id
		)
		INSERT INTO collection_files(collection_id, file_id, encrypted_key, key_decryption_nonce, updation_time, c_owner_id, f_owner_id)
		SELECT $2, file_id, 'collection-file-key', 'collection-file-nonce', 1, $1, $1 FROM inserted_file
		RETURNING file_id`,
		ownerID,
		collectionID,
	).Scan(&fileID)
	if err != nil {
		t.Fatal(err)
	}
	return fileID
}

func TestUnShareResolvesTargetFromCurrentSharees(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "owner@example.com",
		CreationTime: 1,
	})
	shareeID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       2,
		Email:        "sharee@example.com",
		CreationTime: 1,
	})

	collectionRepo := newShareTestCollectionRepo(db)
	collectionID := createShareTestCollection(t, collectionRepo, ownerID)
	addShareTestShare(t, collectionRepo, collectionID, ownerID, shareeID, ente.VIEWER)
	controller := &CollectionController{
		CollectionRepo: collectionRepo,
		CastRepo:       &castRepo.Repository{DB: db},
		UserLookup:     panicUserLookup{},
	}
	gin.SetMode(gin.TestMode)
	ctx, _ := gin.CreateTestContext(httptest.NewRecorder())

	sharees, err := controller.UnShare(ctx, collectionID, ownerID, " SHAREE@example.com ")
	if err != nil {
		t.Fatalf("unshare returned error: %v", err)
	}
	if len(sharees) != 0 {
		t.Fatalf("sharees after unshare = %+v, want none", sharees)
	}

	var isDeleted bool
	err = db.QueryRow(
		`SELECT is_deleted FROM collection_shares WHERE collection_id = $1 AND to_user_id = $2`,
		collectionID,
		shareeID,
	).Scan(&isDeleted)
	if err != nil {
		t.Fatal(err)
	}
	if !isDeleted {
		t.Fatal("collection share remains active after unshare")
	}

	_, err = controller.UnShare(ctx, collectionID, ownerID, "missing@example.com")
	if !errors.Is(err, ente.ErrNotFound) {
		t.Fatalf("missing sharee error = %v, want %v", err, ente.ErrNotFound)
	}
}

func TestShareAuthorizesBeforeUserLookup(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "owner@example.com",
		CreationTime: 1,
	})
	collectionRepo := newShareTestCollectionRepo(db)
	controller := &CollectionController{
		CollectionRepo: collectionRepo,
		UserLookup:     panicUserLookup{},
	}
	ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
	ctx.Request = httptest.NewRequest("POST", "/collections/share", nil)
	ctx.Request.Header.Set("X-Auth-User-ID", "2")

	_, err := controller.Share(ctx, ente.AlterShareRequest{
		CollectionID: createShareTestCollection(t, collectionRepo, ownerID),
		Email:        "target@example.com",
		EncryptedKey: b64OfLen(sealedCollectionKeyLen),
	})
	if !errors.Is(err, ente.ErrPermissionDenied) {
		t.Fatalf("share error = %v, want %v", err, ente.ErrPermissionDenied)
	}
}

func TestCollectionOwnerCannotBecomeShareeOrBeUnshared(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "owner@example.com",
		CreationTime: 1,
	})
	adminID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       2,
		Email:        "admin@example.com",
		CreationTime: 1,
	})

	collectionRepo := newShareTestCollectionRepo(db)
	collectionID := createShareTestCollection(t, collectionRepo, ownerID)
	addShareTestShare(t, collectionRepo, collectionID, ownerID, adminID, ente.ADMIN)
	controller := &CollectionController{
		CollectionRepo: collectionRepo,
		UserLookup:     fixedUserLookup{userID: ownerID},
	}
	gin.SetMode(gin.TestMode)
	ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
	ctx.Request = httptest.NewRequest("POST", "/collections/share", nil)
	ctx.Request.Header.Set("X-Auth-User-ID", strconv.FormatInt(adminID, 10))

	_, err := controller.Share(ctx, ente.AlterShareRequest{
		CollectionID: collectionID,
		Email:        "owner@example.com",
		EncryptedKey: b64OfLen(sealedCollectionKeyLen),
	})
	if !errors.Is(err, ente.ErrBadRequest) {
		t.Fatalf("sharing to owner error = %v, want %v", err, ente.ErrBadRequest)
	}

	addShareTestShare(t, collectionRepo, collectionID, ownerID, ownerID, ente.VIEWER)
	fileID := addShareTestOwnerFile(t, db, collectionID, ownerID)

	_, err = controller.UnShare(ctx, collectionID, adminID, "owner@example.com")
	if !errors.Is(err, ente.ErrPermissionDenied) {
		t.Fatalf("unsharing owner error = %v, want %v", err, ente.ErrPermissionDenied)
	}

	var ownerShareDeleted, ownerFileDeleted bool
	err = db.QueryRow(
		`SELECT cs.is_deleted, cf.is_deleted
		 FROM collection_shares cs
		 JOIN collection_files cf ON cf.collection_id = cs.collection_id
		 WHERE cs.collection_id = $1 AND cs.to_user_id = $2 AND cf.file_id = $3`,
		collectionID,
		ownerID,
		fileID,
	).Scan(&ownerShareDeleted, &ownerFileDeleted)
	if err != nil {
		t.Fatal(err)
	}
	if ownerShareDeleted || ownerFileDeleted {
		t.Fatalf("owner state changed: share deleted=%t, file deleted=%t", ownerShareDeleted, ownerFileDeleted)
	}
}

func TestAutomaticShareLifecycle(t *testing.T) {
	db, collectionRepo, ownerID, shareeID := setupCollectionShareTest(t)
	ctx := context.Background()

	manualCollectionID := createShareTestCollection(t, collectionRepo, ownerID)
	if err := collectionRepo.Share(
		manualCollectionID,
		ownerID,
		shareeID,
		"manual-key",
		ente.ADMIN,
		1,
	); err != nil {
		t.Fatal(err)
	}
	status, err := collectionRepo.ShareAutomatically(
		ctx,
		manualCollectionID,
		ownerID,
		shareeID,
		"automatic-key",
		ente.VIEWER,
		2,
	)
	requireCollectionShareStatus(t, status, ente.CollectionAlreadyShared, err)

	var encryptedKey, role string
	var isDeleted bool
	err = db.QueryRow(
		`SELECT encrypted_key, role_type, is_deleted
		 FROM collection_shares
		 WHERE collection_id = $1 AND to_user_id = $2`,
		manualCollectionID,
		shareeID,
	).Scan(&encryptedKey, &role, &isDeleted)
	if err != nil {
		t.Fatal(err)
	}
	if encryptedKey != "manual-key" || role != string(ente.ADMIN) || isDeleted {
		t.Fatalf(
			"manual share changed: key=%q role=%q deleted=%t",
			encryptedKey,
			role,
			isDeleted,
		)
	}
	status, err = collectionRepo.UnShareContext(
		ctx,
		manualCollectionID,
		shareeID,
	)
	requireCollectionShareStatus(t, status, ente.CollectionUnshared, err)
	status, err = collectionRepo.ShareAutomatically(
		ctx,
		manualCollectionID,
		ownerID,
		shareeID,
		"automatic-key",
		ente.VIEWER,
		3,
	)
	requireCollectionShareStatus(t, status, ente.CollectionBlockedPriorRemoval, err)

	automaticCollectionID := createShareTestCollection(t, collectionRepo, ownerID)
	status, err = collectionRepo.ShareAutomatically(
		ctx,
		automaticCollectionID,
		ownerID,
		shareeID,
		"automatic-key",
		ente.VIEWER,
		1,
	)
	requireCollectionShareStatus(t, status, ente.CollectionShared, err)
}

func TestUnShareContextBumpsCollectionForDeletedShareRow(t *testing.T) {
	db, collectionRepo, ownerID, shareeID := setupCollectionShareTest(t)
	ctx := context.Background()
	collectionID := createShareTestCollection(t, collectionRepo, ownerID)
	if err := collectionRepo.Share(
		collectionID,
		ownerID,
		shareeID,
		"share-key",
		ente.VIEWER,
		1,
	); err != nil {
		t.Fatal(err)
	}

	status, err := collectionRepo.UnShareContext(ctx, collectionID, shareeID)
	requireCollectionShareStatus(t, status, ente.CollectionUnshared, err)
	if _, err := db.Exec(
		`UPDATE collections SET updation_time = 1 WHERE collection_id = $1`,
		collectionID,
	); err != nil {
		t.Fatal(err)
	}

	status, err = collectionRepo.UnShareContext(ctx, collectionID, shareeID)
	requireCollectionShareStatus(t, status, ente.CollectionAlreadyUnshared, err)
	if got := collectionUpdationTime(t, db, collectionID); got == 1 {
		t.Fatal("collection updation_time was not bumped for deleted share row")
	}
}

func TestUncategorizedCollectionsOnlyAllowViewerShares(t *testing.T) {
	_, collectionRepo, ownerID, shareeID := setupCollectionShareTest(t)
	collectionID := createShareTestCollectionOfType(
		t,
		collectionRepo,
		ownerID,
		"uncategorized",
	)
	controller := &CollectionController{CollectionRepo: collectionRepo}
	item := ente.BulkCollectionShareItem{
		CollectionID: collectionID,
		EncryptedKey: b64OfLen(sealedCollectionKeyLen),
		Role:         ente.VIEWER,
	}

	status, err := controller.shareCollectionWithUserID(
		context.Background(),
		ownerID,
		shareeID,
		ente.ManualShare,
		item,
	)
	requireCollectionShareStatus(t, status, ente.CollectionShared, err)

	item.Role = ente.ADMIN
	_, err = controller.shareCollectionWithUserID(
		context.Background(),
		ownerID,
		shareeID,
		ente.ManualShare,
		item,
	)
	if !errors.Is(err, ente.ErrBadRequest) {
		t.Fatalf("admin share error = %v, want %v", err, ente.ErrBadRequest)
	}
}

func TestBulkShareAndUnshareReturnPerCollectionStatuses(t *testing.T) {
	db, collectionRepo, ownerID, shareeID := setupCollectionShareTest(t)
	setShareTestFamilyAdmin(t, db, ownerID, ownerID)
	setShareTestFamilyAdmin(t, db, shareeID, ownerID)
	albumID := createShareTestCollection(t, collectionRepo, ownerID)
	neverSharedID := createShareTestCollection(t, collectionRepo, ownerID)
	uncategorizedID := createShareTestCollectionOfType(
		t,
		collectionRepo,
		ownerID,
		"uncategorized",
	)
	controller := &CollectionController{
		CollectionRepo: collectionRepo,
		CastRepo:       &castRepo.Repository{DB: db},
		UserRepo:       &repo.UserRepository{DB: db},
		UserLookup:     newShareTestUserLookup(db),
	}
	ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
	ctx.Request = httptest.NewRequest("POST", "/collections/share/bulk", nil)
	ctx.Request.Header.Set("X-Auth-User-ID", strconv.FormatInt(ownerID, 10))

	results, err := controller.BulkShare(ctx, ente.BulkCollectionShareRequest{
		RecipientUserID: shareeID,
		RecipientEmail:  "sharee@example.com",
		Source:          ente.AutomaticShare,
		Collections: []ente.BulkCollectionShareItem{
			{
				CollectionID: albumID,
				EncryptedKey: b64OfLen(sealedCollectionKeyLen),
				Role:         ente.VIEWER,
			},
			{
				CollectionID: uncategorizedID,
				EncryptedKey: b64OfLen(sealedCollectionKeyLen),
				Role:         ente.ADMIN,
			},
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	if results[0].Status != ente.CollectionShared ||
		results[1].Status != ente.CollectionShareOperationFailed {
		t.Fatalf("bulk share results = %+v", results)
	}

	controller.UserLookup = panicUserLookup{}
	unshareResults, err := controller.BulkUnShare(ctx, ente.BulkCollectionUnshareRequest{
		RecipientUserID: shareeID,
		Source:          ente.AutomaticShare,
		CollectionIDs:   []int64{albumID, neverSharedID},
	})
	if err != nil {
		t.Fatal(err)
	}
	if unshareResults[0].Status != ente.CollectionUnshared ||
		unshareResults[1].Status != ente.CollectionNotShared {
		t.Fatalf("bulk unshare results = %+v", unshareResults)
	}
}

func TestBulkShareAutomaticRecipientMustBeInSameFamily(t *testing.T) {
	db, collectionRepo, ownerID, shareeID := setupCollectionShareTest(t)
	controller := &CollectionController{
		CollectionRepo: collectionRepo,
		UserRepo:       &repo.UserRepository{DB: db},
		UserLookup:     newShareTestUserLookup(db),
	}
	ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
	ctx.Request = httptest.NewRequest("POST", "/collections/share/bulk", nil)
	ctx.Request.Header.Set("X-Auth-User-ID", strconv.FormatInt(ownerID, 10))
	share := func(collectionID int64, source ente.CollectionShareSource) error {
		_, err := controller.BulkShare(ctx, ente.BulkCollectionShareRequest{
			RecipientUserID: shareeID,
			RecipientEmail:  "sharee@example.com",
			Source:          source,
			Collections: []ente.BulkCollectionShareItem{{
				CollectionID: collectionID,
				EncryptedKey: b64OfLen(sealedCollectionKeyLen),
				Role:         ente.VIEWER,
			}},
		})
		return err
	}

	setShareTestFamilyAdmin(t, db, ownerID, ownerID)
	setShareTestFamilyAdmin(t, db, shareeID, shareeID)
	if err := share(createShareTestCollection(t, collectionRepo, ownerID), ente.AutomaticShare); !errors.Is(err, ente.ErrAutomaticShareRecipientNotEligible) {
		t.Fatalf("unrelated automatic share error = %v, want %v", err, ente.ErrAutomaticShareRecipientNotEligible)
	}

	setShareTestFamilyAdmin(t, db, shareeID, nil)
	if err := share(createShareTestCollection(t, collectionRepo, ownerID), ente.AutomaticShare); !errors.Is(err, ente.ErrAutomaticShareRecipientNotEligible) {
		t.Fatalf("former family member automatic share error = %v, want %v", err, ente.ErrAutomaticShareRecipientNotEligible)
	}

	var shareCount int
	if err := db.QueryRow(`SELECT count(*) FROM collection_shares`).Scan(&shareCount); err != nil {
		t.Fatal(err)
	}
	if shareCount != 0 {
		t.Fatalf("collection shares after rejected requests = %d, want 0", shareCount)
	}

	if err := share(createShareTestCollection(t, collectionRepo, ownerID), ente.ManualShare); err != nil {
		t.Fatalf("manual share error = %v", err)
	}

	setShareTestFamilyAdmin(t, db, shareeID, ownerID)
	if err := share(createShareTestCollection(t, collectionRepo, ownerID), ente.AutomaticShare); err != nil {
		t.Fatalf("same-family automatic share error = %v", err)
	}
}

func TestBulkShareRejectsRecipientIdentityMismatchBeforeMutation(t *testing.T) {
	db, collectionRepo, ownerID, shareeID := setupCollectionShareTest(t)
	collectionID := createShareTestCollection(t, collectionRepo, ownerID)
	controller := &CollectionController{
		CollectionRepo: collectionRepo,
		UserLookup:     newShareTestUserLookup(db),
	}
	ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
	ctx.Request = httptest.NewRequest("POST", "/collections/share/bulk", nil)
	ctx.Request.Header.Set("X-Auth-User-ID", strconv.FormatInt(ownerID, 10))

	_, err := controller.BulkShare(ctx, ente.BulkCollectionShareRequest{
		RecipientUserID: shareeID + 1,
		RecipientEmail:  "sharee@example.com",
		Source:          ente.AutomaticShare,
		Collections: []ente.BulkCollectionShareItem{{
			CollectionID: collectionID,
			EncryptedKey: b64OfLen(sealedCollectionKeyLen),
			Role:         ente.VIEWER,
		}},
	})
	if !errors.Is(err, ente.ErrRecipientIdentityMismatch) {
		t.Fatalf("bulk share error = %v, want %v", err, ente.ErrRecipientIdentityMismatch)
	}

	var shareCount int
	if err := db.QueryRow(
		`SELECT count(*) FROM collection_shares WHERE collection_id = $1`,
		collectionID,
	).Scan(&shareCount); err != nil {
		t.Fatal(err)
	}
	if shareCount != 0 {
		t.Fatalf("collection shares after rejected request = %d, want 0", shareCount)
	}
}

func TestBulkShareRejectsOversizedBatch(t *testing.T) {
	items := make([]ente.BulkCollectionShareItem, ente.MaxCollectionShareBatchSize+1)
	for index := range items {
		items[index].CollectionID = int64(index + 1)
	}
	controller := &CollectionController{}
	_, err := controller.BulkShare(&gin.Context{}, ente.BulkCollectionShareRequest{
		RecipientUserID: 1,
		Source:          ente.AutomaticShare,
		Collections:     items,
	})
	if !errors.Is(err, ente.ErrBatchSizeTooLarge) {
		t.Fatalf("oversized batch error = %v, want %v", err, ente.ErrBatchSizeTooLarge)
	}
}
