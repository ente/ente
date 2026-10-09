package collections

import (
	"context"
	"database/sql"
	"errors"
	"net/http/httptest"
	"strconv"
	"sync/atomic"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	museumcontroller "github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/controller/access"
	"github.com/ente/museum/pkg/repo"
	castRepo "github.com/ente/museum/pkg/repo/cast"
	publicRepo "github.com/ente/museum/pkg/repo/public"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type panicUserLookup struct{}

func requireBadRequestError(t *testing.T, err error) {
	t.Helper()
	var apiErr *ente.ApiError
	if !errors.As(err, &apiErr) || apiErr.Code != ente.BadRequest {
		t.Fatalf("error = %v, want %s", err, ente.BadRequest)
	}
}

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

func newBatchShareTestController(
	db *sql.DB,
	collectionRepo *repo.CollectionRepository,
) *CollectionController {
	return &CollectionController{
		PushCtrl:       &museumcontroller.PushController{},
		AccessCtrl:     access.NewAccessController(collectionRepo, nil),
		CollectionRepo: collectionRepo,
		UserLookup:     newShareTestUserLookup(db),
	}
}

func newBatchShareTestContext(userID int64) *gin.Context {
	ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
	ctx.Request = httptest.NewRequest("POST", "/collections/share/batch", nil)
	ctx.Request.Header.Set("X-Auth-User-ID", strconv.FormatInt(userID, 10))
	return ctx
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

func collectionShareCount(t *testing.T, db *sql.DB, collectionID int64) int {
	t.Helper()
	var count int
	if err := db.QueryRow(
		`SELECT count(*) FROM collection_shares WHERE collection_id = $1`,
		collectionID,
	).Scan(&count); err != nil {
		t.Fatal(err)
	}
	return count
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

	status, _, err := controller.shareCollectionWithUserID(
		context.Background(),
		ownerID,
		shareeID,
		ente.ManualShare,
		item,
	)
	requireCollectionShareStatus(t, status, ente.CollectionShared, err)

	item.Role = ente.ADMIN
	_, _, err = controller.shareCollectionWithUserID(
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
		PushCtrl:       &museumcontroller.PushController{},
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

func TestBatchShareWritesEveryShareWithOneTimestamp(t *testing.T) {
	db, collectionRepo, ownerID, firstShareeID := setupCollectionShareTest(t)
	secondShareeID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       3,
		Email:        "second-sharee@example.com",
		CreationTime: 1,
	})
	collectionID := createShareTestCollection(t, collectionRepo, ownerID)
	addShareTestShare(t, collectionRepo, collectionID, ownerID, firstShareeID, ente.VIEWER)
	if _, err := collectionRepo.UnShareContext(context.Background(), collectionID, firstShareeID); err != nil {
		t.Fatal(err)
	}
	controller := newBatchShareTestController(db, collectionRepo)
	ctx := newBatchShareTestContext(ownerID)
	admin := ente.ADMIN
	collaborator := ente.COLLABORATOR

	sharees, err := controller.BatchShare(ctx, []ente.AlterShareRequest{
		{
			CollectionID: collectionID,
			Email:        "sharee@example.com",
			EncryptedKey: b64OfLen(sealedCollectionKeyLen),
			Role:         &admin,
		},
		{
			CollectionID: collectionID,
			Email:        "second-sharee@example.com",
			EncryptedKey: b64OfLen(sealedCollectionKeyLen),
			Role:         &collaborator,
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(sharees) != 2 {
		t.Fatalf("sharees = %+v, want 2", sharees)
	}

	roles := make(map[int64]ente.CollectionParticipantRole, len(sharees))
	for _, sharee := range sharees {
		roles[sharee.ID] = sharee.Role
	}
	if roles[firstShareeID] != ente.ADMIN || roles[secondShareeID] != ente.COLLABORATOR {
		t.Fatalf("sharee roles = %+v", roles)
	}
	var existingKey string
	if err := db.QueryRow(
		`SELECT encrypted_key FROM collection_shares
		 WHERE collection_id = $1 AND to_user_id = $2`,
		collectionID,
		firstShareeID,
	).Scan(&existingKey); err != nil {
		t.Fatal(err)
	}
	if existingKey != "share-key" {
		t.Fatalf("existing encrypted key = %q, want %q", existingKey, "share-key")
	}

	var collectionTime, shareTime int64
	var distinctShareTimes int
	if err := db.QueryRow(
		`SELECT count(DISTINCT updation_time), min(updation_time)
		 FROM collection_shares WHERE collection_id = $1`,
		collectionID,
	).Scan(&distinctShareTimes, &shareTime); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRow(
		`SELECT updation_time FROM collections WHERE collection_id = $1`,
		collectionID,
	).Scan(&collectionTime); err != nil {
		t.Fatal(err)
	}
	if distinctShareTimes != 1 || shareTime != collectionTime {
		t.Fatalf("share times = %d distinct at %d; collection time = %d", distinctShareTimes, shareTime, collectionTime)
	}
}

func TestBatchShareDoesNotWriteWhenAnyLookupFails(t *testing.T) {
	db, collectionRepo, ownerID, _ := setupCollectionShareTest(t)
	collectionID := createShareTestCollection(t, collectionRepo, ownerID)
	controller := newBatchShareTestController(db, collectionRepo)
	ctx := newBatchShareTestContext(ownerID)

	_, err := controller.BatchShare(ctx, []ente.AlterShareRequest{
		{
			CollectionID: collectionID,
			Email:        "sharee@example.com",
			EncryptedKey: b64OfLen(sealedCollectionKeyLen),
		},
		{
			CollectionID: collectionID,
			Email:        "missing@example.com",
			EncryptedKey: b64OfLen(sealedCollectionKeyLen),
		},
	})
	if err == nil {
		t.Fatal("BatchShare() error = nil, want missing-user error")
	}

	if count := collectionShareCount(t, db, collectionID); count != 0 {
		t.Fatalf("collection shares = %d, want 0", count)
	}
}

func TestBatchShareRollsBackWhenAnyWriteFails(t *testing.T) {
	db, collectionRepo, ownerID, shareeID := setupCollectionShareTest(t)
	collectionID := createShareTestCollection(t, collectionRepo, ownerID)
	originalCollectionTime := collectionUpdationTime(t, db, collectionID)

	err := collectionRepo.BatchShare(
		context.Background(),
		collectionID,
		ownerID,
		[]repo.CollectionShareItem{
			{ToUserID: shareeID, EncryptedKey: "share-key", Role: ente.VIEWER},
			{ToUserID: shareeID + 1000, EncryptedKey: "missing-user-key", Role: ente.VIEWER},
		},
		originalCollectionTime+1,
	)
	if err == nil {
		t.Fatal("BatchShare() error = nil, want foreign-key error")
	}

	shareCount := collectionShareCount(t, db, collectionID)
	collectionTime := collectionUpdationTime(t, db, collectionID)
	if shareCount != 0 || collectionTime != originalCollectionTime {
		t.Fatalf("after rollback: shares = %d, collection time = %d, want %d", shareCount, collectionTime, originalCollectionTime)
	}
}

func TestBatchShareRejectsDeletedCollection(t *testing.T) {
	db, collectionRepo, ownerID, shareeID := setupCollectionShareTest(t)
	collectionID := createShareTestCollection(t, collectionRepo, ownerID)
	if _, err := db.Exec(
		`UPDATE collections SET is_deleted = TRUE WHERE collection_id = $1`,
		collectionID,
	); err != nil {
		t.Fatal(err)
	}

	controller := newBatchShareTestController(db, collectionRepo)
	_, err := controller.BatchShare(newBatchShareTestContext(ownerID), []ente.AlterShareRequest{
		{
			CollectionID: collectionID,
			Email:        "sharee@example.com",
			EncryptedKey: b64OfLen(sealedCollectionKeyLen),
		},
	})
	if !errors.Is(err, ente.ErrCollectionDeleted) {
		t.Fatalf("BatchShare() error = %v, want %v", err, ente.ErrCollectionDeleted)
	}
	_, err = controller.BatchShare(newBatchShareTestContext(shareeID), []ente.AlterShareRequest{
		{CollectionID: collectionID, Email: "owner@example.com"},
	})
	if !errors.Is(err, ente.ErrPermissionDenied) {
		t.Fatalf("unauthorized BatchShare() error = %v, want %v", err, ente.ErrPermissionDenied)
	}

	err = collectionRepo.BatchShare(
		context.Background(),
		collectionID,
		ownerID,
		[]repo.CollectionShareItem{{
			ToUserID:     shareeID,
			EncryptedKey: "share-key",
			Role:         ente.VIEWER,
		}},
		2,
	)
	if !errors.Is(err, ente.ErrCollectionDeleted) {
		t.Fatalf("CollectionRepository.BatchShare() error = %v, want %v", err, ente.ErrCollectionDeleted)
	}
	if count := collectionShareCount(t, db, collectionID); count != 0 {
		t.Fatalf("collection shares = %d, want 0", count)
	}
}

func TestBulkUnShareStillSucceedsOnDeletedCollection(t *testing.T) {
	db, collectionRepo, ownerID, shareeID := setupCollectionShareTest(t)
	collectionID := createShareTestCollection(t, collectionRepo, ownerID)
	addShareTestShare(t, collectionRepo, collectionID, ownerID, shareeID, ente.VIEWER)
	for _, query := range []string{
		`UPDATE collection_shares SET is_deleted = TRUE WHERE collection_id = $1`,
		`UPDATE collections SET is_deleted = TRUE WHERE collection_id = $1`,
	} {
		if _, err := db.Exec(query, collectionID); err != nil {
			t.Fatal(err)
		}
	}
	controller := &CollectionController{
		CollectionRepo: collectionRepo,
		CastRepo:       &castRepo.Repository{DB: db},
		UserLookup:     panicUserLookup{},
	}

	results, err := controller.BulkUnShare(newBatchShareTestContext(ownerID), ente.BulkCollectionUnshareRequest{
		RecipientUserID: shareeID,
		Source:          ente.ManualShare,
		CollectionIDs:   []int64{collectionID},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(results) != 1 || results[0].Status != ente.CollectionAlreadyUnshared {
		t.Fatalf("bulk unshare results = %+v, want %q", results, ente.CollectionAlreadyUnshared)
	}
}

func TestBatchShareRejectsInvalidInputAsBadRequest(t *testing.T) {
	db, collectionRepo, ownerID, _ := setupCollectionShareTest(t)
	collectionID := createShareTestCollection(t, collectionRepo, ownerID)
	invalidRole := ente.CollectionParticipantRole("INVALID")
	controller := newBatchShareTestController(db, collectionRepo)

	_, err := controller.BatchShare(newBatchShareTestContext(ownerID), []ente.AlterShareRequest{
		{
			CollectionID: collectionID,
			Email:        "sharee@example.com",
			EncryptedKey: b64OfLen(sealedCollectionKeyLen),
			Role:         &invalidRole,
		},
	})
	requireBadRequestError(t, err)

	_, err = controller.BatchShare(newBatchShareTestContext(ownerID), []ente.AlterShareRequest{
		{
			CollectionID: collectionID,
			Email:        "sharee@example.com",
			EncryptedKey: "invalid",
		},
	})
	requireBadRequestError(t, err)
}

func TestBatchShareRejectsNormalizedDuplicates(t *testing.T) {
	err := validateBatchShares([]ente.AlterShareRequest{
		{CollectionID: 1, Email: "sharee@example.com"},
		{CollectionID: 1, Email: " SHAREE@EXAMPLE.COM "},
	})
	if !errors.Is(err, ente.ErrBadRequest) {
		t.Fatalf("duplicate share email error = %v, want %v", err, ente.ErrBadRequest)
	}
}

func TestBatchShareRejectsDifferentCollectionsBeforeWrites(t *testing.T) {
	controller := &CollectionController{}
	_, err := controller.BatchShare(&gin.Context{}, []ente.AlterShareRequest{
		{CollectionID: 1, Email: "first@example.com", EncryptedKey: b64OfLen(sealedCollectionKeyLen)},
		{CollectionID: 2, Email: "second@example.com", EncryptedKey: b64OfLen(sealedCollectionKeyLen)},
	})
	if !errors.Is(err, ente.ErrBadRequest) {
		t.Fatalf("different collection IDs error = %v, want %v", err, ente.ErrBadRequest)
	}
}

func TestBatchShareRejectsOversizedBatch(t *testing.T) {
	shares := make([]ente.AlterShareRequest, ente.MaxBatchShareSize+1)
	for index := range shares {
		shares[index] = ente.AlterShareRequest{
			CollectionID: 1,
			Email:        "sharee" + strconv.Itoa(index) + "@example.com",
			EncryptedKey: b64OfLen(sealedCollectionKeyLen),
		}
	}
	controller := &CollectionController{}
	_, err := controller.BatchShare(&gin.Context{}, shares)
	if !errors.Is(err, ente.ErrBatchSizeTooLarge) {
		t.Fatalf("oversized share batch error = %v, want %v", err, ente.ErrBatchSizeTooLarge)
	}
}

type albumSharePushFunc func(context.Context, []int64)

func (f albumSharePushFunc) NotifyAlbumShare(ctx context.Context, recipients []int64) {
	f(ctx, recipients)
}

func TestAlbumShareNotifiesAfterEverySuccessfulShare(t *testing.T) {
	db, r, owner, recipient := setupCollectionShareTest(t)
	c := newBatchShareTestController(db, r)
	id := createShareTestCollection(t, r, owner)
	notifications := make(chan []int64, 4)
	c.PushCtrl = albumSharePushFunc(func(ctx context.Context, users []int64) {
		_, pooledContext := ctx.(*gin.Context)
		assert.False(t, pooledContext)
		var active bool
		assert.NoError(t, db.QueryRow(`SELECT NOT is_deleted FROM collection_shares WHERE collection_id=$1 AND to_user_id=$2`, id, recipient).Scan(&active))
		assert.True(t, active, "notification must run after commit")
		notifications <- users
	})
	request := ente.AlterShareRequest{CollectionID: id, Email: "sharee@example.com", EncryptedKey: b64OfLen(sealedCollectionKeyLen)}
	_, err := c.Share(newBatchShareTestContext(owner), request)
	require.NoError(t, err)
	require.Eventually(t, func() bool { return len(notifications) == 1 }, time.Second, time.Millisecond)
	require.Equal(t, []int64{recipient}, <-notifications)
	_, err = c.BatchShare(newBatchShareTestContext(owner), []ente.AlterShareRequest{request})
	require.NoError(t, err)
	role := ente.COLLABORATOR
	request.Role = &role
	_, err = c.Share(newBatchShareTestContext(owner), request)
	require.NoError(t, err)
	require.Eventually(t, func() bool { return len(notifications) == 2 }, time.Second, time.Millisecond, "retry and role change must notify")
	require.Equal(t, []int64{recipient}, <-notifications)
	require.Equal(t, []int64{recipient}, <-notifications)
	require.NoError(t, r.UnShare(id, recipient))
	_, err = c.BatchShare(newBatchShareTestContext(owner), []ente.AlterShareRequest{request})
	require.NoError(t, err)
	require.Eventually(t, func() bool { return len(notifications) == 1 }, time.Second, time.Millisecond)
	require.Equal(t, []int64{recipient}, <-notifications, "restored access should notify")
	require.NoError(t, r.UnShare(id, recipient))
	_, err = db.Exec(`UPDATE collections SET is_deleted = TRUE WHERE collection_id = $1`, id)
	require.NoError(t, err)
	_, err = c.Share(newBatchShareTestContext(owner), request)
	require.ErrorIs(t, err, ente.ErrCollectionDeleted)
	require.Never(t, func() bool { return len(notifications) > 0 }, 50*time.Millisecond, time.Millisecond)
	var deleted bool
	require.NoError(t, db.QueryRow(`SELECT is_deleted FROM collection_shares WHERE collection_id=$1 AND to_user_id=$2`, id, recipient).Scan(&deleted))
	require.True(t, deleted, "failed share must roll back restored access")
}

func TestBatchShareNotifiesAllRecipients(t *testing.T) {
	db, r, owner, existingRecipient := setupCollectionShareTest(t)
	newRecipient := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID: 3, Email: "new-sharee@example.com", CreationTime: 1,
	})
	id := createShareTestCollection(t, r, owner)
	addShareTestShare(t, r, id, owner, existingRecipient, ente.VIEWER)
	c := newBatchShareTestController(db, r)
	notifications := make(chan []int64, 1)
	c.PushCtrl = albumSharePushFunc(func(_ context.Context, recipients []int64) {
		notifications <- recipients
	})
	admin, collaborator := ente.ADMIN, ente.COLLABORATOR
	_, err := c.BatchShare(newBatchShareTestContext(owner), []ente.AlterShareRequest{
		{CollectionID: id, Email: "sharee@example.com", EncryptedKey: b64OfLen(sealedCollectionKeyLen), Role: &admin},
		{CollectionID: id, Email: "new-sharee@example.com", EncryptedKey: b64OfLen(sealedCollectionKeyLen), Role: &collaborator},
	})
	require.NoError(t, err)
	select {
	case recipients := <-notifications:
		require.ElementsMatch(t, []int64{existingRecipient, newRecipient}, recipients)
	case <-time.After(time.Second):
		t.Fatal("new recipient was not notified")
	}
}

func TestBulkAlbumShareNotifiesOnceAfterAllMutations(t *testing.T) {
	db, r, owner, recipient := setupCollectionShareTest(t)
	c := newBatchShareTestController(db, r)
	request := ente.BulkCollectionShareRequest{RecipientUserID: recipient, RecipientEmail: "sharee@example.com", Source: ente.ManualShare}
	for range 2 {
		request.Collections = append(request.Collections, ente.BulkCollectionShareItem{CollectionID: createShareTestCollection(t, r, owner), EncryptedKey: b64OfLen(sealedCollectionKeyLen), Role: ente.VIEWER})
	}
	var calls atomic.Int32
	c.PushCtrl = albumSharePushFunc(func(_ context.Context, _ []int64) {
		for _, item := range request.Collections {
			var count int
			assert.NoError(t, db.QueryRow(`SELECT COUNT(*) FROM collection_shares WHERE collection_id=$1`, item.CollectionID).Scan(&count))
			assert.Equal(t, 1, count)
		}
		calls.Add(1)
	})
	for range 2 {
		_, err := c.BulkShare(newBatchShareTestContext(owner), request)
		require.NoError(t, err)
	}
	require.Eventually(t, func() bool { return calls.Load() == 2 }, time.Second, time.Millisecond)
}

func TestAlbumSharePushEligibility(t *testing.T) {
	db, r, owner, recipient := setupCollectionShareTest(t)
	c := newBatchShareTestController(db, r)
	var calls atomic.Int32
	var expected int32
	c.PushCtrl = albumSharePushFunc(func(context.Context, []int64) { calls.Add(1) })
	for _, collection := range []ente.Collection{
		{Type: "album", App: string(ente.Photos)},
		{Type: "album", App: string(ente.Locker)},
		{Type: "folder", App: string(ente.Photos)},
		{Type: "favorites", App: string(ente.Photos)},
		{Type: "uncategorized", App: string(ente.Photos)},
	} {
		id := createShareTestCollection(t, r, owner)
		_, err := db.Exec(`UPDATE collections SET type=$2, app=$3 WHERE collection_id=$1`, id, collection.Type, collection.App)
		require.NoError(t, err)
		for _, flow := range []string{"single", "batch", "bulk"} {
			request := ente.AlterShareRequest{CollectionID: id, Email: "sharee@example.com", EncryptedKey: b64OfLen(sealedCollectionKeyLen)}
			switch flow {
			case "single":
				_, err = c.Share(newBatchShareTestContext(owner), request)
			case "batch":
				_, err = c.BatchShare(newBatchShareTestContext(owner), []ente.AlterShareRequest{request})
			case "bulk":
				_, err = c.BulkShare(newBatchShareTestContext(owner), ente.BulkCollectionShareRequest{
					RecipientUserID: recipient, RecipientEmail: request.Email, Source: ente.ManualShare,
					Collections: []ente.BulkCollectionShareItem{{CollectionID: id, EncryptedKey: request.EncryptedKey, Role: ente.VIEWER}},
				})
			}
			require.NoError(t, err)
			require.Equal(t, 1, collectionShareCount(t, db, id))
			require.NoError(t, r.UnShare(id, recipient))
		}
		if collection.App == string(ente.Photos) {
			expected += 3
			require.Eventually(t, func() bool { return calls.Load() == expected }, time.Second, time.Millisecond)
		}
	}
	require.Never(t, func() bool { return calls.Load() > expected }, 50*time.Millisecond, time.Millisecond)
}

func TestAlbumShareDoesNotWaitForPush(t *testing.T) {
	for _, flow := range []string{"single", "batch", "bulk"} {
		t.Run(flow, func(t *testing.T) {
			db, r, owner, recipient := setupCollectionShareTest(t)
			c := newBatchShareTestController(db, r)
			id := createShareTestCollection(t, r, owner)
			request := ente.AlterShareRequest{CollectionID: id, Email: "sharee@example.com", EncryptedKey: b64OfLen(sealedCollectionKeyLen)}
			started := make(chan struct{})
			release := make(chan struct{})
			returned := make(chan struct{})
			c.PushCtrl = albumSharePushFunc(func(context.Context, []int64) {
				close(started)
				<-release
			})
			t.Cleanup(func() { close(release); <-returned })
			var err error
			go func() {
				switch flow {
				case "single":
					_, err = c.Share(newBatchShareTestContext(owner), request)
				case "batch":
					_, err = c.BatchShare(newBatchShareTestContext(owner), []ente.AlterShareRequest{request})
				case "bulk":
					_, err = c.BulkShare(newBatchShareTestContext(owner), ente.BulkCollectionShareRequest{
						RecipientUserID: recipient, RecipientEmail: request.Email, Source: ente.ManualShare,
						Collections: []ente.BulkCollectionShareItem{{CollectionID: id, EncryptedKey: request.EncryptedKey, Role: ente.VIEWER}},
					})
				}
				close(returned)
			}()
			select {
			case <-returned:
				require.NoError(t, err)
			case <-time.After(5 * time.Second):
				t.Fatal("sharing must return while push delivery is blocked")
			}
			select {
			case <-started:
			case <-time.After(time.Second):
				t.Fatal("push delivery was not started")
			}
		})
	}
}
