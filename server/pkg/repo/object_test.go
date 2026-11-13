package repo

import (
	"database/sql"
	"errors"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/lib/pq"
)

func TestObjectLookupDBUsesLatencySensitiveDBWhenPresent(t *testing.T) {
	primaryDB := &sql.DB{}
	latencySensitiveDB := &sql.DB{}
	repository := &ObjectRepository{DB: primaryDB, LatencySensitiveDB: latencySensitiveDB}

	if got := repository.objectLookupDB(); got != latencySensitiveDB {
		t.Fatal("expected object lookup DB to use LatencySensitiveDB")
	}
}

func TestObjectLookupDBFallsBackToPrimaryDB(t *testing.T) {
	primaryDB := &sql.DB{}
	repository := &ObjectRepository{DB: primaryDB}

	if got := repository.objectLookupDB(); got != primaryDB {
		t.Fatal("expected object lookup DB to fall back to DB")
	}
}

func TestGetObjectReferenceStatuses(t *testing.T) {
	repository, db := setupAccessibleObjectTest(t)

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "reference-status-owner@ente.com",
		CreationTime: 1,
	})
	fileID := insertObjectTestFile(t, db, ownerID)
	insertObjectTestKey(t, db, fileID, ente.FILE, "in-object-keys", 100, []string{"b2-eu-cen"})
	if _, err := db.Exec(`INSERT INTO temp_objects(object_key, expiration_time) VALUES($1, $2)`, "in-temp-objects", int64(1)); err != nil {
		t.Fatalf("failed to insert temp object: %v", err)
	}

	statuses, err := repository.GetObjectReferenceStatuses(t.Context(), []string{"in-object-keys", "in-temp-objects", "unreferenced"})
	if err != nil {
		t.Fatalf("GetObjectReferenceStatuses() error = %v", err)
	}
	if !statuses["in-object-keys"].InObjectKeys || statuses["in-object-keys"].InTempObjects {
		t.Fatalf("unexpected object_keys status: %+v", statuses["in-object-keys"])
	}
	if statuses["in-temp-objects"].InObjectKeys || !statuses["in-temp-objects"].InTempObjects {
		t.Fatalf("unexpected temp_objects status: %+v", statuses["in-temp-objects"])
	}
	if statuses["unreferenced"].InObjectKeys || statuses["unreferenced"].InTempObjects {
		t.Fatalf("unexpected unreferenced status: %+v", statuses["unreferenced"])
	}
}

func TestGetAccessibleObjectAllowsOwnerFileAndThumbnail(t *testing.T) {
	repository, db := setupAccessibleObjectTest(t)

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "owner-object@ente.com",
		CreationTime: 1,
	})
	fileID := insertObjectTestFile(t, db, ownerID)
	insertObjectTestKey(t, db, fileID, ente.FILE, "owner-file-object", 100, []string{"b2-eu-cen"})
	insertObjectTestKey(t, db, fileID, ente.THUMBNAIL, "owner-thumbnail-object", 10, []string{"b2-eu-cen"})

	fileObject, err := repository.GetAccessibleObject(t.Context(), fileID, ownerID, ente.FILE)
	if err != nil {
		t.Fatalf("GetAccessibleObject(file) error = %v", err)
	}
	if fileObject.ObjectKey != "owner-file-object" || fileObject.FileSize != 100 || fileObject.Type != ente.FILE {
		t.Fatalf("unexpected file object: %+v", fileObject)
	}

	thumbnailObject, err := repository.GetAccessibleObject(t.Context(), fileID, ownerID, ente.THUMBNAIL)
	if err != nil {
		t.Fatalf("GetAccessibleObject(thumbnail) error = %v", err)
	}
	if thumbnailObject.ObjectKey != "owner-thumbnail-object" || thumbnailObject.FileSize != 10 || thumbnailObject.Type != ente.THUMBNAIL {
		t.Fatalf("unexpected thumbnail object: %+v", thumbnailObject)
	}
}

func TestGetAccessibleObjectAllowsSharedFile(t *testing.T) {
	repository, db := setupAccessibleObjectTest(t)

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "shared-owner-object@ente.com",
		CreationTime: 1,
	})
	actorID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       2,
		Email:        "shared-actor-object@ente.com",
		CreationTime: 1,
	})
	collectionID := insertObjectTestCollection(t, db, ownerID)
	insertObjectTestCollectionShare(t, db, collectionID, ownerID, actorID)
	fileID := insertObjectTestFile(t, db, ownerID)
	linkObjectTestFileToCollection(t, db, collectionID, fileID, ownerID)
	insertObjectTestKey(t, db, fileID, ente.FILE, "shared-file-object", 100, []string{"b2-eu-cen"})

	fileObject, err := repository.GetAccessibleObject(t.Context(), fileID, actorID, ente.FILE)
	if err != nil {
		t.Fatalf("GetAccessibleObject(shared file) error = %v", err)
	}
	if fileObject.ObjectKey != "shared-file-object" {
		t.Fatalf("unexpected shared file object: %+v", fileObject)
	}
}

func TestGetAccessibleObjectRejectsUnsharedForeignFile(t *testing.T) {
	repository, db := setupAccessibleObjectTest(t)

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "unshared-owner-object@ente.com",
		CreationTime: 1,
	})
	actorID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       2,
		Email:        "unshared-actor-object@ente.com",
		CreationTime: 1,
	})
	fileID := insertObjectTestFile(t, db, ownerID)
	insertObjectTestKey(t, db, fileID, ente.FILE, "unshared-file-object", 100, []string{"b2-eu-cen"})

	_, err := repository.GetAccessibleObject(t.Context(), fileID, actorID, ente.FILE)
	if !errors.Is(err, ente.ErrPermissionDenied) {
		t.Fatalf("expected permission denied, got %v", err)
	}
}

func TestGetAccessibleObjectReturnsNoRowsForAllowedFileWithMissingObject(t *testing.T) {
	repository, db := setupAccessibleObjectTest(t)

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "missing-object-owner@ente.com",
		CreationTime: 1,
	})
	fileID := insertObjectTestFile(t, db, ownerID)

	_, err := repository.GetAccessibleObject(t.Context(), fileID, ownerID, ente.FILE)
	if !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("expected sql.ErrNoRows, got %v", err)
	}
}

func TestGetAccessibleObjectReturnsNoRowsForMissingFile(t *testing.T) {
	repository, _ := setupAccessibleObjectTest(t)

	_, err := repository.GetAccessibleObject(t.Context(), 404, 1, ente.FILE)
	if !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("expected sql.ErrNoRows, got %v", err)
	}
}

func TestGetAccessibleObjectReturnsNoRowsForDeletedObject(t *testing.T) {
	repository, db := setupAccessibleObjectTest(t)

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "deleted-object-owner@ente.com",
		CreationTime: 1,
	})
	fileID := insertObjectTestFile(t, db, ownerID)
	insertObjectTestKey(t, db, fileID, ente.FILE, "deleted-file-object", 100, []string{"b2-eu-cen"})
	if _, err := db.Exec(`UPDATE object_keys SET is_deleted = TRUE WHERE file_id = $1 AND o_type = $2`, fileID, ente.FILE); err != nil {
		t.Fatalf("failed to mark object deleted: %v", err)
	}

	_, err := repository.GetAccessibleObject(t.Context(), fileID, ownerID, ente.FILE)
	if !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("expected sql.ErrNoRows, got %v", err)
	}
}

func TestGetAccessibleObjectWithDCsReturnsDatacenters(t *testing.T) {
	repository, db := setupAccessibleObjectTest(t)

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "dcs-owner-object@ente.com",
		CreationTime: 1,
	})
	fileID := insertObjectTestFile(t, db, ownerID)
	wantDCs := []string{"b2-eu-cen", "wasabi-eu-central-2-v3"}
	insertObjectTestKey(t, db, fileID, ente.FILE, "dcs-file-object", 100, wantDCs)

	fileObject, gotDCs, err := repository.GetAccessibleObjectWithDCs(t.Context(), fileID, ownerID, ente.FILE)
	if err != nil {
		t.Fatalf("GetAccessibleObjectWithDCs() error = %v", err)
	}
	if fileObject.ObjectKey != "dcs-file-object" {
		t.Fatalf("unexpected object: %+v", fileObject)
	}
	if len(gotDCs) != len(wantDCs) {
		t.Fatalf("unexpected datacenters: got %v want %v", gotDCs, wantDCs)
	}
	for i := range wantDCs {
		if gotDCs[i] != wantDCs[i] {
			t.Fatalf("unexpected datacenters: got %v want %v", gotDCs, wantDCs)
		}
	}
}

func TestGetOwnedObjectAllowsOwner(t *testing.T) {
	repository, db := setupAccessibleObjectTest(t)

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "owned-object-owner@ente.com",
		CreationTime: 1,
	})
	fileID := insertObjectTestFile(t, db, ownerID)
	insertObjectTestKey(t, db, fileID, ente.FILE, "owned-file-object", 100, []string{"b2-eu-cen"})

	fileObject, err := repository.GetOwnedObject(t.Context(), fileID, ownerID, ente.FILE)
	if err != nil {
		t.Fatalf("GetOwnedObject() error = %v", err)
	}
	if fileObject.ObjectKey != "owned-file-object" || fileObject.FileSize != 100 || fileObject.Type != ente.FILE {
		t.Fatalf("unexpected owned file object: %+v", fileObject)
	}
}

func TestGetOwnedObjectRejectsForeignOwner(t *testing.T) {
	repository, db := setupAccessibleObjectTest(t)

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "owned-object-real-owner@ente.com",
		CreationTime: 1,
	})
	actorID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       2,
		Email:        "owned-object-actor@ente.com",
		CreationTime: 1,
	})
	fileID := insertObjectTestFile(t, db, ownerID)
	insertObjectTestKey(t, db, fileID, ente.FILE, "foreign-owned-file-object", 100, []string{"b2-eu-cen"})

	_, err := repository.GetOwnedObject(t.Context(), fileID, actorID, ente.FILE)
	if !errors.Is(err, ente.ErrPermissionDenied) {
		t.Fatalf("expected permission denied, got %v", err)
	}
}

func TestGetOwnedObjectReturnsNoRowsForOwnedFileWithMissingObject(t *testing.T) {
	repository, db := setupAccessibleObjectTest(t)

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "owned-object-missing-owner@ente.com",
		CreationTime: 1,
	})
	fileID := insertObjectTestFile(t, db, ownerID)

	_, err := repository.GetOwnedObject(t.Context(), fileID, ownerID, ente.FILE)
	if !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("expected sql.ErrNoRows, got %v", err)
	}
}

func TestGetCollectionObjectAllowsCollectionFile(t *testing.T) {
	repository, db := setupAccessibleObjectTest(t)

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "collection-object-owner@ente.com",
		CreationTime: 1,
	})
	collectionID := insertObjectTestCollection(t, db, ownerID)
	fileID := insertObjectTestFile(t, db, ownerID)
	linkObjectTestFileToCollection(t, db, collectionID, fileID, ownerID)
	insertObjectTestKey(t, db, fileID, ente.THUMBNAIL, "collection-thumbnail-object", 10, []string{"b2-eu-cen"})

	thumbnailObject, err := repository.GetCollectionObject(t.Context(), collectionID, fileID, ente.THUMBNAIL)
	if err != nil {
		t.Fatalf("GetCollectionObject() error = %v", err)
	}
	if thumbnailObject.ObjectKey != "collection-thumbnail-object" || thumbnailObject.Type != ente.THUMBNAIL {
		t.Fatalf("unexpected collection thumbnail object: %+v", thumbnailObject)
	}
}

func TestGetCollectionObjectRejectsFileOutsideCollection(t *testing.T) {
	repository, db := setupAccessibleObjectTest(t)

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "collection-object-outside-owner@ente.com",
		CreationTime: 1,
	})
	collectionID := insertObjectTestCollection(t, db, ownerID)
	fileID := insertObjectTestFile(t, db, ownerID)
	insertObjectTestKey(t, db, fileID, ente.FILE, "outside-collection-file-object", 100, []string{"b2-eu-cen"})

	_, err := repository.GetCollectionObject(t.Context(), collectionID, fileID, ente.FILE)
	if !errors.Is(err, ente.ErrPermissionDenied) {
		t.Fatalf("expected permission denied, got %v", err)
	}
}

func TestGetCollectionObjectReturnsNoRowsForMissingObject(t *testing.T) {
	repository, db := setupAccessibleObjectTest(t)

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "collection-object-missing-owner@ente.com",
		CreationTime: 1,
	})
	collectionID := insertObjectTestCollection(t, db, ownerID)
	fileID := insertObjectTestFile(t, db, ownerID)
	linkObjectTestFileToCollection(t, db, collectionID, fileID, ownerID)

	_, err := repository.GetCollectionObject(t.Context(), collectionID, fileID, ente.FILE)
	if !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("expected sql.ErrNoRows, got %v", err)
	}
}

func TestGetCollectionObjectRejectsDeletedCollectionFile(t *testing.T) {
	repository, db := setupAccessibleObjectTest(t)

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "collection-object-deleted-owner@ente.com",
		CreationTime: 1,
	})
	collectionID := insertObjectTestCollection(t, db, ownerID)
	fileID := insertObjectTestFile(t, db, ownerID)
	linkObjectTestFileToCollection(t, db, collectionID, fileID, ownerID)
	insertObjectTestKey(t, db, fileID, ente.FILE, "deleted-collection-file-object", 100, []string{"b2-eu-cen"})
	if _, err := db.Exec(`UPDATE collection_files SET is_deleted = TRUE WHERE collection_id = $1 AND file_id = $2`, collectionID, fileID); err != nil {
		t.Fatalf("failed to mark collection file deleted: %v", err)
	}

	_, err := repository.GetCollectionObject(t.Context(), collectionID, fileID, ente.FILE)
	if !errors.Is(err, ente.ErrPermissionDenied) {
		t.Fatalf("expected permission denied, got %v", err)
	}
}

func setupAccessibleObjectTest(t *testing.T) (*ObjectRepository, *sql.DB) {
	t.Helper()

	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	return &ObjectRepository{DB: db, LatencySensitiveDB: db}, db
}

func insertObjectTestFile(t *testing.T, db *sql.DB, ownerID int64) int64 {
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

func insertObjectTestKey(t *testing.T, db *sql.DB, fileID int64, objType ente.ObjectType, objectKey string, size int64, datacenters []string) {
	t.Helper()

	_, err := db.Exec(
		`INSERT INTO object_keys(file_id, o_type, object_key, size, datacenters)
		 VALUES($1, $2, $3, $4, $5)`,
		fileID,
		objType,
		objectKey,
		size,
		pq.StringArray(datacenters),
	)
	if err != nil {
		t.Fatalf("failed to insert object key for file %d: %v", fileID, err)
	}
}

func insertObjectTestCollection(t *testing.T, db *sql.DB, ownerID int64) int64 {
	t.Helper()

	var collectionID int64
	err := db.QueryRow(
		`INSERT INTO collections(owner_id, encrypted_key, key_decryption_nonce, name, type, attributes, updation_time, app)
		 VALUES($1, $2, $3, $4, $5, $6::jsonb, $7, $8)
		 RETURNING collection_id`,
		ownerID,
		"encrypted-key",
		"key-nonce",
		"Test collection",
		"album",
		"{}",
		int64(1),
		string(ente.Photos),
	).Scan(&collectionID)
	if err != nil {
		t.Fatalf("failed to insert collection for owner %d: %v", ownerID, err)
	}
	return collectionID
}

func insertObjectTestCollectionShare(t *testing.T, db *sql.DB, collectionID int64, fromUserID int64, toUserID int64) {
	t.Helper()

	_, err := db.Exec(
		`INSERT INTO collection_shares(collection_id, from_user_id, to_user_id, encrypted_key, updation_time, role_type, shared_at)
		 VALUES($1, $2, $3, $4, $5, $6, $7)`,
		collectionID,
		fromUserID,
		toUserID,
		"share-key",
		int64(1),
		string(ente.VIEWER),
		int64(1),
	)
	if err != nil {
		t.Fatalf("failed to insert collection share for collection %d: %v", collectionID, err)
	}
}

func linkObjectTestFileToCollection(t *testing.T, db *sql.DB, collectionID int64, fileID int64, ownerID int64) {
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
