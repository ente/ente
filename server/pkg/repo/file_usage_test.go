package repo

import (
	"database/sql"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
)

func TestUpdateUsageForFileCreationMaintainsCounterState(t *testing.T) {
	db := setupFileUsageTest(t)
	repo := &FileRepository{DB: db}
	tests := []struct {
		name        string
		app         ente.App
		usageExists bool
		ready       bool
	}{
		{name: "ready_photos", app: ente.Photos, usageExists: true, ready: true},
		{name: "legacy_photos", app: ente.Photos, usageExists: true},
		{name: "missing_locker", app: ente.Locker},
	}

	for i, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			userID := testutil.InsertUser(t, db, testutil.UserFixture{
				UserID:       int64(i + 1),
				Email:        tt.name + "@example.com",
				CreationTime: 1,
			})
			if tt.ready {
				if _, err := db.Exec(`INSERT INTO usage
					(user_id, storage_consumed, photos_file_count, locker_file_count, file_count_source_version)
					VALUES ($1, 10, 2, 3, 7)`, userID); err != nil {
					t.Fatal(err)
				}
			} else if tt.usageExists {
				testutil.InsertUsage(t, db, userID, 10)
			}

			tx, err := db.BeginTx(t.Context(), nil)
			if err != nil {
				t.Fatal(err)
			}
			usage, err := repo.updateUsageForFileCreation(t.Context(), tx, userID, 5, tt.app)
			if err != nil {
				t.Fatal(err)
			}
			if err := tx.Commit(); err != nil {
				t.Fatal(err)
			}

			var storage, version int64
			var photos, locker sql.NullInt64
			if err := db.QueryRow(`SELECT storage_consumed, photos_file_count, locker_file_count, file_count_source_version
				FROM usage WHERE user_id = $1`, userID).Scan(&storage, &photos, &locker, &version); err != nil {
				t.Fatal(err)
			}
			wantStorage := int64(15)
			if !tt.usageExists {
				wantStorage = 5
			}
			if usage != wantStorage || storage != wantStorage {
				t.Fatalf("storage = (%d, %d), want %d", usage, storage, wantStorage)
			}
			if tt.ready {
				if !photos.Valid || photos.Int64 != 3 || !locker.Valid || locker.Int64 != 3 || version != 8 {
					t.Fatalf("counter state = (%v, %v, %d), want (3, 3, 8)", photos, locker, version)
				}
			} else if photos.Valid || locker.Valid || version != 1 {
				t.Fatalf("counter state = (%v, %v, %d), want (NULL, NULL, 1)", photos, locker, version)
			}
		})
	}
}

func TestCreateMetaFileUpdatesReadyLockerCount(t *testing.T) {
	db := setupFileUsageTest(t)
	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "meta-file@example.com",
		CreationTime: 1,
	})
	if _, err := db.Exec(`INSERT INTO usage
		(user_id, storage_consumed, photos_file_count, locker_file_count, file_count_source_version)
		VALUES ($1, 10, 2, 3, 7)`, userID); err != nil {
		t.Fatal(err)
	}
	var collectionID int64
	if err := db.QueryRow(`INSERT INTO collections
		(owner_id, encrypted_key, key_decryption_nonce, name, type, attributes, updation_time, app)
		VALUES ($1, 'key', 'nonce', 'Locker', 'album', '{}', 1, $2)
		RETURNING collection_id`, userID, ente.Locker).Scan(&collectionID); err != nil {
		t.Fatal(err)
	}

	_, err := (&FileRepository{DB: db}).CreateMetaFile(ente.MetaFile{
		OwnerID:            userID,
		CollectionID:       collectionID,
		EncryptedKey:       "file-key",
		KeyDecryptionNonce: "file-nonce",
		Metadata: ente.FileAttributes{
			EncryptedData:    "metadata",
			DecryptionHeader: "header",
		},
		UpdationTime: 1,
	}, userID, ente.Locker)
	if err != nil {
		t.Fatal(err)
	}

	var storage, photos, locker, version int64
	if err := db.QueryRow(`SELECT storage_consumed, photos_file_count, locker_file_count, file_count_source_version
		FROM usage WHERE user_id = $1`, userID).Scan(&storage, &photos, &locker, &version); err != nil {
		t.Fatal(err)
	}
	if storage != 10 || photos != 2 || locker != 4 || version != 8 {
		t.Fatalf("usage state = (%d, %d, %d, %d), want (10, 2, 4, 8)", storage, photos, locker, version)
	}
}

func setupFileUsageTest(t *testing.T) *sql.DB {
	t.Helper()
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	return db
}
