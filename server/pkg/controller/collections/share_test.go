package collections

import (
	"database/sql"
	"errors"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	castRepo "github.com/ente/museum/pkg/repo/cast"
	publicRepo "github.com/ente/museum/pkg/repo/public"
	"github.com/gin-gonic/gin"
)

type panicUserLookup struct{}

func (panicUserLookup) LookupUserID(int64, string) (int64, error) {
	panic("user lookup must not be called while revoking collection access")
}

type fixedUserLookup struct {
	userID int64
}

func (l fixedUserLookup) LookupUserID(int64, string) (int64, error) {
	return l.userID, nil
}

func newShareTestCollectionRepo(db *sql.DB) *repo.CollectionRepository {
	return &repo.CollectionRepository{
		DB:                  db,
		CollectionLinkRepo:  publicRepo.NewCollectionLinkRepository(db, ""),
		SecretEncryptionKey: testutil.SecretEncryptionKey(),
	}
}

func createShareTestCollection(t *testing.T, collectionRepo *repo.CollectionRepository, ownerID int64) int64 {
	t.Helper()
	collection, err := collectionRepo.Create(ente.Collection{
		Owner:              ente.CollectionUser{ID: ownerID},
		EncryptedKey:       "encrypted-key",
		KeyDecryptionNonce: "key-nonce",
		Name:               "Test collection",
		Type:               "album",
		Attributes:         ente.CollectionAttributes{},
		UpdationTime:       1,
		App:                string(ente.Photos),
	})
	if err != nil {
		t.Fatal(err)
	}
	return collection.ID
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

func TestShareeIndexForEmail(t *testing.T) {
	sharees := []ente.CollectionUser{
		{ID: 1, Email: "one@example.com"},
		{ID: 2, Email: "Person@Example.COM"},
	}

	if got := shareeIndexForEmail(sharees, "  person@example.com "); got != 1 {
		t.Fatalf("sharee index = %d, want 1", got)
	}
	if got := shareeIndexForEmail(sharees, "missing@example.com"); got != -1 {
		t.Fatalf("missing sharee index = %d, want -1", got)
	}
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
