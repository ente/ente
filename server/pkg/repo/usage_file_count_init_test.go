package repo

import (
	"errors"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo/public"
)

func TestInitializeFileCountsIncludesLegacyMembershipsInDeletedCollections(t *testing.T) {
	_, db, userID := setupCollectionMembershipTest(t)
	usageRepo := &UsageRepository{DB: db}
	otherUserID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 2, Email: "other@ente.io", CreationTime: 1})
	photosFile := insertObjectTestFile(t, db, userID)
	lockerFile := insertObjectTestFile(t, db, userID)
	foreignFile := insertObjectTestFile(t, db, otherUserID)
	for range 2 {
		collectionID := insertObjectTestCollection(t, db, userID)
		linkObjectTestFileToCollection(t, db, collectionID, photosFile, userID)
		linkObjectTestFileToCollection(t, db, collectionID, foreignFile, otherUserID)
		if _, err := db.Exec(`UPDATE collection_files SET c_owner_id = NULL, f_owner_id = NULL
			WHERE collection_id = $1`, collectionID); err != nil {
			t.Fatal(err)
		}
		if _, err := db.Exec(`UPDATE collections SET is_deleted = TRUE WHERE collection_id = $1`, collectionID); err != nil {
			t.Fatal(err)
		}
	}
	lockerCollection := insertObjectTestCollection(t, db, userID)
	if _, err := db.Exec(`UPDATE collections SET app = 'locker' WHERE collection_id = $1`, lockerCollection); err != nil {
		t.Fatal(err)
	}
	linkObjectTestFileToCollection(t, db, lockerCollection, lockerFile, userID)
	if _, err := db.Exec(`UPDATE usage SET storage_consumed = 17, file_count_source_version = 9 WHERE user_id = $1`, userID); err != nil {
		t.Fatal(err)
	}

	for _, wantInitialized := range []bool{true, false} {
		initialized, err := usageRepo.InitializeFileCounts(t.Context(), userID)
		if err != nil || initialized != wantInitialized {
			t.Fatalf("InitializeFileCounts() = (%t, %v), want %t", initialized, err, wantInitialized)
		}
		assertReadyFileCounts(t, db, userID, 1, 1, 9)
	}
	storage, err := usageRepo.GetUsage(userID)
	if err != nil || storage != 17 {
		t.Fatalf("storage = (%d, %v), want 17", storage, err)
	}
}

func TestInitializeFileCountsRejectsInconsistentHistory(t *testing.T) {
	for _, tt := range []struct {
		name string
		sql  string
	}{
		{"cross_app", `INSERT INTO collection_files(collection_id, file_id, encrypted_key, key_decryption_nonce, updation_time)
			VALUES (102, 201, 'key', 'nonce', 1)`},
		{"cross_app_shared", `UPDATE collections SET owner_id = 2 WHERE collection_id = 102;
			INSERT INTO collection_files(collection_id, file_id, encrypted_key, key_decryption_nonce, updation_time)
			VALUES (102, 201, 'key', 'nonce', 1)`},
		{"active_trash", `INSERT INTO trash(file_id, user_id, collection_id, delete_by) VALUES (201, 1, 101, 1)`},
		{"wrong_trash_owner", `INSERT INTO trash(file_id, user_id, collection_id, delete_by) VALUES (201, 2, 101, 1)`},
		{"locker_null_owner", `UPDATE collection_files SET f_owner_id = NULL WHERE file_id = 201`},
		{"locker_equal_counts_different_files", `UPDATE collection_files
			SET f_owner_id = CASE WHEN file_id = 201 THEN NULL ELSE 1 END WHERE collection_id = 101`},
	} {
		t.Run(tt.name, func(t *testing.T) {
			_, db, userID := setupCollectionMembershipTest(t)
			testutil.InsertUser(t, db, testutil.UserFixture{UserID: 2, Email: "other@ente.io", CreationTime: 1})
			if _, err := db.Exec(`INSERT INTO collections
				(collection_id, owner_id, encrypted_key, key_decryption_nonce, name, type, attributes, updation_time, app)
				OVERRIDING SYSTEM VALUE VALUES
				(101, 1, 'key', 'nonce', 'Locker', 'album', '{}', 1, 'locker'),
				(102, 1, 'key', 'nonce', 'Photos', 'album', '{}', 1, 'photos');
				INSERT INTO files(file_id, owner_id, file_decryption_header, thumbnail_decryption_header,
					metadata_decryption_header, encrypted_metadata, updation_time)
				OVERRIDING SYSTEM VALUE VALUES
				(201, 1, 'header', 'header', 'header', 'metadata', 1),
				(202, 2, 'header', 'header', 'header', 'metadata', 1);
				INSERT INTO collection_files
					(collection_id, file_id, encrypted_key, key_decryption_nonce, updation_time, c_owner_id, f_owner_id)
				VALUES (101, 201, 'key', 'nonce', 1, 1, 1), (101, 202, 'key', 'nonce', 1, 1, 2)`); err != nil {
				t.Fatal(err)
			}
			if _, err := db.Exec(tt.sql); err != nil {
				t.Fatal(err)
			}
			initialized, err := (&UsageRepository{DB: db}).InitializeFileCounts(t.Context(), userID)
			if initialized || !errors.Is(err, ErrFileCountIneligible) {
				t.Fatalf("InitializeFileCounts() = (%t, %v), want ineligible", initialized, err)
			}
			photos, locker, version := readFileCountState(t, db, userID)
			if photos.Valid || locker.Valid || version != 0 {
				t.Fatalf("ineligible user changed: (%v, %v, %d)", photos, locker, version)
			}
		})
	}
}

func TestInitializeFileCountsExcludesInactiveFiles(t *testing.T) {
	for _, name := range []string{"empty", "orphan", "permanently_deleted"} {
		t.Run(name, func(t *testing.T) {
			_, db, userID := setupCollectionMembershipTest(t)
			if name != "empty" {
				collectionID := insertObjectTestCollection(t, db, userID)
				fileID := insertObjectTestFile(t, db, userID)
				linkObjectTestFileToCollection(t, db, collectionID, fileID, userID)
				if _, err := db.Exec(`UPDATE collection_files SET is_deleted = TRUE WHERE file_id = $1`, fileID); err != nil {
					t.Fatal(err)
				}
				if name == "permanently_deleted" {
					if _, err := db.Exec(`INSERT INTO trash(file_id, user_id, collection_id, delete_by, is_deleted)
						VALUES ($1, $2, $3, 1, TRUE)`, fileID, userID, collectionID); err != nil {
						t.Fatal(err)
					}
				}
			}
			if initialized, err := (&UsageRepository{DB: db}).InitializeFileCounts(t.Context(), userID); err != nil || !initialized {
				t.Fatalf("initialization = (%t, %v), want true", initialized, err)
			}
			assertReadyFileCounts(t, db, userID, 0, 0, 0)
		})
	}
}

func TestInitializeFileCountsRejectsStaleSnapshots(t *testing.T) {
	repository, db, userID := setupCollectionMembershipTest(t)
	usageRepo := &UsageRepository{DB: db}
	collectionID := insertObjectTestCollection(t, db, userID)
	fileID := insertObjectTestFile(t, db, userID)
	linkObjectTestFileToCollection(t, db, collectionID, fileID, userID)
	repository.TrashRepo.FileLinkRepo = public.NewFileLinkRepo(db)

	counts, err := usageRepo.readFileCountInitSnapshot(t.Context(), userID)
	if err != nil {
		t.Fatal(err)
	}
	if err := repository.TrashRepo.TrashFiles(t.Context(), userID, ente.TrashRequest{
		TrashItems: []ente.TrashItemRequest{{FileID: fileID, CollectionID: collectionID}},
	}); err != nil {
		t.Fatal(err)
	}
	if initialized, err := usageRepo.publishInitialFileCounts(t.Context(), userID, counts); err != nil || initialized {
		t.Fatalf("stale publish = (%t, %v), want false", initialized, err)
	}
	photos, locker, version := readFileCountState(t, db, userID)
	if photos.Valid || locker.Valid || version != 1 {
		t.Fatalf("stale publish changed counters: (%v, %v, %d)", photos, locker, version)
	}
	if initialized, err := usageRepo.InitializeFileCounts(t.Context(), userID); err != nil || !initialized {
		t.Fatalf("fresh initialization = (%t, %v), want true", initialized, err)
	}
	assertReadyFileCounts(t, db, userID, 0, 0, 1)
	if err := repository.RestoreFiles(t.Context(), userID, collectionID,
		[]ente.CollectionFileItem{collectionMembershipTestItem(fileID)}); err != nil {
		t.Fatal(err)
	}
	assertReadyFileCounts(t, db, userID, 1, 0, 2)
}
