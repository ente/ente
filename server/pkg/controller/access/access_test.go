package access

import (
	"database/sql"
	"errors"
	"net/http/httptest"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	publicRepo "github.com/ente/museum/pkg/repo/public"
	"github.com/gin-gonic/gin"
)

func setupAccessControllerTest(t *testing.T) (Controller, *sql.DB, *gin.Context) {
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

	return NewAccessController(
		&repo.CollectionRepository{
			DB:                 db,
			CollectionLinkRepo: publicRepo.NewCollectionLinkRepository(db, ""),
		},
		&repo.FileRepository{DB: db},
	), db, ctx
}

func insertAccessTestCollection(t *testing.T, db *sql.DB, ownerID int64, isDeleted bool) int64 {
	t.Helper()

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
		isDeleted,
		string(ente.Photos),
	).Scan(&collectionID)
	if err != nil {
		t.Fatalf("failed to insert collection for owner %d: %v", ownerID, err)
	}
	return collectionID
}

func insertAccessTestCollectionShare(t *testing.T, db *sql.DB, collectionID, fromUserID, toUserID int64, role ente.CollectionParticipantRole) {
	t.Helper()

	_, err := db.Exec(
		`INSERT INTO collection_shares(collection_id, from_user_id, to_user_id, encrypted_key, updation_time, role_type, shared_at)
		 VALUES($1, $2, $3, $4, $5, $6, $7)`,
		collectionID,
		fromUserID,
		toUserID,
		"share-key",
		int64(1),
		string(role),
		int64(1),
	)
	if err != nil {
		t.Fatalf("failed to insert collection share for collection %d: %v", collectionID, err)
	}
}

func insertAccessTestFile(t *testing.T, db *sql.DB, ownerID int64) int64 {
	t.Helper()

	var fileID int64
	err := db.QueryRow(
		`INSERT INTO files(owner_id, file_decryption_header, thumbnail_decryption_header, metadata_decryption_header, encrypted_metadata, updation_time, info)
		 VALUES($1, $2, $3, $4, $5, $6, $7::jsonb)
		 RETURNING file_id`,
		ownerID,
		"file-header",
		"thumbnail-header",
		"metadata-header",
		"encrypted-metadata",
		int64(1),
		"{}",
	).Scan(&fileID)
	if err != nil {
		t.Fatalf("failed to insert file for owner %d: %v", ownerID, err)
	}
	return fileID
}

func linkAccessTestFileToCollection(t *testing.T, db *sql.DB, collectionID, fileID, ownerID int64) {
	t.Helper()

	_, err := db.Exec(
		`INSERT INTO collection_files(collection_id, file_id, encrypted_key, key_decryption_nonce, updation_time, c_owner_id, f_owner_id)
		 VALUES($1, $2, $3, $4, $5, $6, $7)`,
		collectionID,
		fileID,
		"collection-file-key",
		"collection-file-nonce",
		int64(1),
		ownerID,
		ownerID,
	)
	if err != nil {
		t.Fatalf("failed to link file %d to collection %d: %v", fileID, collectionID, err)
	}
}

func TestGetCollectionReturnsOwnerRole(t *testing.T) {
	controller, db, ctx := setupAccessControllerTest(t)

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "owner@ente.com",
		CreationTime: 1,
	})
	collectionID := insertAccessTestCollection(t, db, ownerID, false)

	resp, err := controller.GetCollection(ctx, &GetCollectionParams{
		CollectionID: collectionID,
		ActorUserID:  ownerID,
	})
	if err != nil {
		t.Fatalf("GetCollection() error = %v", err)
	}
	if resp.Collection.ID != collectionID {
		t.Fatalf("unexpected collection id: got %d want %d", resp.Collection.ID, collectionID)
	}
	if resp.Role == nil || *resp.Role != ente.OWNER {
		t.Fatalf("unexpected role: got %v want %v", resp.Role, ente.OWNER)
	}
}

func TestGetCollectionReturnsShareeRole(t *testing.T) {
	controller, db, ctx := setupAccessControllerTest(t)

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "owner@ente.com",
		CreationTime: 1,
	})
	shareeID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       2,
		Email:        "sharee@ente.com",
		CreationTime: 1,
	})
	collectionID := insertAccessTestCollection(t, db, ownerID, false)
	insertAccessTestCollectionShare(t, db, collectionID, ownerID, shareeID, ente.COLLABORATOR)

	resp, err := controller.GetCollection(ctx, &GetCollectionParams{
		CollectionID: collectionID,
		ActorUserID:  shareeID,
	})
	if err != nil {
		t.Fatalf("GetCollection() error = %v", err)
	}
	if resp.Role == nil || *resp.Role != ente.COLLABORATOR {
		t.Fatalf("unexpected role: got %v want %v", resp.Role, ente.COLLABORATOR)
	}
}

func TestGetCollectionVerifyOwnerRejectsSharee(t *testing.T) {
	controller, db, ctx := setupAccessControllerTest(t)

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "owner@ente.com",
		CreationTime: 1,
	})
	shareeID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       2,
		Email:        "sharee@ente.com",
		CreationTime: 1,
	})
	collectionID := insertAccessTestCollection(t, db, ownerID, false)
	insertAccessTestCollectionShare(t, db, collectionID, ownerID, shareeID, ente.VIEWER)

	_, err := controller.GetCollection(ctx, &GetCollectionParams{
		CollectionID: collectionID,
		ActorUserID:  shareeID,
		VerifyOwner:  true,
	})
	if !errors.Is(err, ente.ErrPermissionDenied) {
		t.Fatalf("expected permission denied, got %v", err)
	}
}

func TestGetCollectionRejectsDeletedCollectionByDefault(t *testing.T) {
	controller, db, ctx := setupAccessControllerTest(t)

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "owner@ente.com",
		CreationTime: 1,
	})
	collectionID := insertAccessTestCollection(t, db, ownerID, true)

	_, err := controller.GetCollection(ctx, &GetCollectionParams{
		CollectionID: collectionID,
		ActorUserID:  ownerID,
	})
	if !errors.Is(err, ente.ErrNotFound) {
		t.Fatalf("expected not found, got %v", err)
	}
}

func TestGetCollectionIncludesDeletedWhenRequested(t *testing.T) {
	controller, db, ctx := setupAccessControllerTest(t)

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "owner@ente.com",
		CreationTime: 1,
	})
	collectionID := insertAccessTestCollection(t, db, ownerID, true)

	resp, err := controller.GetCollection(ctx, &GetCollectionParams{
		CollectionID:   collectionID,
		ActorUserID:    ownerID,
		IncludeDeleted: true,
	})
	if err != nil {
		t.Fatalf("GetCollection() error = %v", err)
	}
	if !resp.Collection.IsDeleted {
		t.Fatal("expected deleted collection to be returned")
	}
}

func TestVerifyFileOwnershipRejectsDuplicateFileIDs(t *testing.T) {
	controller, _, ctx := setupAccessControllerTest(t)

	err := controller.VerifyFileOwnership(ctx, &VerifyFileOwnershipParams{
		ActorUserId: 1,
		FileIDs:     []int64{10, 10},
	})
	if !errors.Is(err, ente.ErrBadRequest) {
		t.Fatalf("expected bad request, got %v", err)
	}
}

func TestVerifyFileOwnershipSucceedsForOwner(t *testing.T) {
	controller, db, ctx := setupAccessControllerTest(t)

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "owner@ente.com",
		CreationTime: 1,
	})
	fileIDOne := insertAccessTestFile(t, db, ownerID)
	fileIDTwo := insertAccessTestFile(t, db, ownerID)

	err := controller.VerifyFileOwnership(ctx, &VerifyFileOwnershipParams{
		ActorUserId: ownerID,
		FileIDs:     []int64{fileIDOne, fileIDTwo},
	})
	if err != nil {
		t.Fatalf("VerifyFileOwnership() error = %v", err)
	}
}

func TestVerifyFileOwnershipRejectsNonOwner(t *testing.T) {
	controller, db, ctx := setupAccessControllerTest(t)

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "owner@ente.com",
		CreationTime: 1,
	})
	otherUserID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       2,
		Email:        "other@ente.com",
		CreationTime: 1,
	})
	fileID := insertAccessTestFile(t, db, ownerID)

	err := controller.VerifyFileOwnership(ctx, &VerifyFileOwnershipParams{
		ActorUserId: otherUserID,
		FileIDs:     []int64{fileID},
	})
	if !errors.Is(err, ente.ErrPermissionDenied) {
		t.Fatalf("expected permission denied, got %v", err)
	}
}

func TestVerifyFileOwnershipRejectsInvalidFileIDs(t *testing.T) {
	controller, db, ctx := setupAccessControllerTest(t)

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "owner@ente.com",
		CreationTime: 1,
	})
	fileID := insertAccessTestFile(t, db, ownerID)

	err := controller.VerifyFileOwnership(ctx, &VerifyFileOwnershipParams{
		ActorUserId: ownerID,
		FileIDs:     []int64{fileID, 9999},
	})
	if !errors.Is(err, ente.ErrBadRequest) {
		t.Fatalf("expected bad request, got %v", err)
	}
}

func TestVerifyFileOwnershipRejectsMixedOwners(t *testing.T) {
	controller, db, ctx := setupAccessControllerTest(t)

	ownerOneID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "owner-one@ente.com",
		CreationTime: 1,
	})
	ownerTwoID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       2,
		Email:        "owner-two@ente.com",
		CreationTime: 1,
	})
	fileIDOne := insertAccessTestFile(t, db, ownerOneID)
	fileIDTwo := insertAccessTestFile(t, db, ownerTwoID)

	err := controller.VerifyFileOwnership(ctx, &VerifyFileOwnershipParams{
		ActorUserId: ownerOneID,
		FileIDs:     []int64{fileIDOne, fileIDTwo},
	})
	if !errors.Is(err, ente.ErrPermissionDenied) {
		t.Fatalf("expected permission denied, got %v", err)
	}
}

func TestCanAccessFileRejectsDuplicateFileIDs(t *testing.T) {
	controller, _, ctx := setupAccessControllerTest(t)

	err := controller.CanAccessFile(ctx, &CanAccessFileParams{
		ActorUserID: 1,
		FileIDs:     []int64{10, 10},
	})
	if !errors.Is(err, ente.ErrBadRequest) {
		t.Fatalf("expected bad request, got %v", err)
	}
}

func TestCanAccessFileAllowsOwnerFiles(t *testing.T) {
	controller, db, ctx := setupAccessControllerTest(t)

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "owner@ente.com",
		CreationTime: 1,
	})
	fileIDOne := insertAccessTestFile(t, db, ownerID)
	fileIDTwo := insertAccessTestFile(t, db, ownerID)

	err := controller.CanAccessFile(ctx, &CanAccessFileParams{
		ActorUserID: ownerID,
		FileIDs:     []int64{fileIDOne, fileIDTwo},
	})
	if err != nil {
		t.Fatalf("CanAccessFile() error = %v", err)
	}
}

func TestCanAccessFileAllowsSharedFiles(t *testing.T) {
	controller, db, ctx := setupAccessControllerTest(t)

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "owner@ente.com",
		CreationTime: 1,
	})
	actorID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       2,
		Email:        "actor@ente.com",
		CreationTime: 1,
	})
	collectionID := insertAccessTestCollection(t, db, ownerID, false)
	insertAccessTestCollectionShare(t, db, collectionID, ownerID, actorID, ente.VIEWER)
	fileID := insertAccessTestFile(t, db, ownerID)
	linkAccessTestFileToCollection(t, db, collectionID, fileID, ownerID)

	err := controller.CanAccessFile(ctx, &CanAccessFileParams{
		ActorUserID: actorID,
		FileIDs:     []int64{fileID},
	})
	if err != nil {
		t.Fatalf("CanAccessFile() error = %v", err)
	}
}

func TestCanAccessFileAllowsOwnedAndSharedFilesTogether(t *testing.T) {
	controller, db, ctx := setupAccessControllerTest(t)

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "owner@ente.com",
		CreationTime: 1,
	})
	actorID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       2,
		Email:        "actor@ente.com",
		CreationTime: 1,
	})
	ownedFileID := insertAccessTestFile(t, db, actorID)
	sharedCollectionID := insertAccessTestCollection(t, db, ownerID, false)
	insertAccessTestCollectionShare(t, db, sharedCollectionID, ownerID, actorID, ente.VIEWER)
	sharedFileID := insertAccessTestFile(t, db, ownerID)
	linkAccessTestFileToCollection(t, db, sharedCollectionID, sharedFileID, ownerID)

	err := controller.CanAccessFile(ctx, &CanAccessFileParams{
		ActorUserID: actorID,
		FileIDs:     []int64{ownedFileID, sharedFileID},
	})
	if err != nil {
		t.Fatalf("CanAccessFile() error = %v", err)
	}
}

func TestCanAccessFileRejectsUnsharedForeignFiles(t *testing.T) {
	controller, db, ctx := setupAccessControllerTest(t)

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "owner@ente.com",
		CreationTime: 1,
	})
	actorID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       2,
		Email:        "actor@ente.com",
		CreationTime: 1,
	})
	fileID := insertAccessTestFile(t, db, ownerID)

	err := controller.CanAccessFile(ctx, &CanAccessFileParams{
		ActorUserID: actorID,
		FileIDs:     []int64{fileID},
	})
	if !errors.Is(err, ente.ErrPermissionDenied) {
		t.Fatalf("expected permission denied, got %v", err)
	}
}
