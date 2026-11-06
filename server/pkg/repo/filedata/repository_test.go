package filedata

import (
	"testing"

	"github.com/ente/museum/ente"
	enteFileData "github.com/ente/museum/ente/filedata"
	"github.com/ente/museum/internal/testutil"
	baserepo "github.com/ente/museum/pkg/repo"
	"github.com/stretchr/testify/require"
)

func TestInsertOrUpdatePreviewDataRequiresObjectID(t *testing.T) {
	if err := (&Repository{}).InsertOrUpdatePreviewData(t.Context(), enteFileData.Row{}, ""); err == nil {
		t.Fatal("InsertOrUpdatePreviewData() error = nil")
	}
}

func TestPreviewRegistrationCleanupState(t *testing.T) {
	for _, state := range []ente.TempObjectCleanupState{ente.TempObjectUploading, ente.TempObjectReleaseHold, ente.TempObjectDelete} {
		t.Run(string(state), func(t *testing.T) {
			testutil.WithServerRoot(t)
			db := testutil.RequireTestDB(t)
			testutil.ResetTables(t, db)
			_, err := db.Exec(`DELETE FROM file_data`)
			require.NoError(t, err)
			t.Cleanup(func() {
				testutil.ResetTables(t, db)
				_, err := db.Exec(`DELETE FROM file_data`)
				require.NoError(t, err)
			})
			_, err = db.Exec(`INSERT INTO temp_objects(object_key, expiration_time, bucket_id, cleanup_state)
				VALUES ('1/preview', 0, 'wasabi-eu-central-2-v3', NULLIF($1, ''))`, state)
			require.NoError(t, err)
			objectID := "preview-id"
			row := enteFileData.Row{FileID: 1, UserID: 1, Type: ente.PreviewImage, Size: 10,
				LatestBucket: "wasabi-eu-central-2-v3", ObjectID: &objectID}
			repository := &Repository{DB: db, ObjectCleanupRepo: &baserepo.ObjectCleanupRepository{DB: db}}
			err = repository.InsertOrUpdatePreviewData(t.Context(), row, "1/preview")
			allowed := state == ente.TempObjectUploading
			if allowed {
				require.NoError(t, err)
			} else {
				require.Error(t, err)
			}
			assertFileDataExists(t, repository, row, allowed)
			var staged bool
			require.NoError(t, db.QueryRow(`SELECT EXISTS (SELECT 1 FROM temp_objects WHERE object_key = '1/preview')`).Scan(&staged))
			require.Equal(t, !allowed, staged)
		})
	}
}

func TestDeleteFileData(t *testing.T) {
	testutil.WithServerRoot(t)

	db := testutil.RequireTestDB(t)
	if _, err := db.Exec(`DELETE FROM file_data`); err != nil {
		t.Fatalf("failed to reset file_data: %v", err)
	}
	t.Cleanup(func() {
		if _, err := db.Exec(`DELETE FROM file_data`); err != nil {
			t.Errorf("failed to reset file_data: %v", err)
		}
	})

	repo := &Repository{DB: db}

	t.Run("deletes eligible row", func(t *testing.T) {
		row := enteFileData.Row{
			FileID:       1,
			UserID:       10,
			Type:         ente.MlData,
			LatestBucket: "b2-eu-cen",
		}
		insertFileDataForDeleteTest(t, repo, row, true)

		if err := repo.DeleteFileData(t.Context(), row); err != nil {
			t.Fatalf("DeleteFileData() error = %v", err)
		}
		assertFileDataExists(t, repo, row, false)
	})

	t.Run("succeeds when row is already absent", func(t *testing.T) {
		row := enteFileData.Row{
			FileID:       2,
			UserID:       10,
			Type:         ente.MlData,
			LatestBucket: "b2-eu-cen",
		}

		if err := repo.DeleteFileData(t.Context(), row); err != nil {
			t.Fatalf("DeleteFileData() error = %v", err)
		}
	})

	t.Run("rejects row that is not eligible for deletion", func(t *testing.T) {
		row := enteFileData.Row{
			FileID:       3,
			UserID:       10,
			Type:         ente.MlData,
			LatestBucket: "b2-eu-cen",
		}
		insertFileDataForDeleteTest(t, repo, row, false)

		if err := repo.DeleteFileData(t.Context(), row); err == nil {
			t.Fatal("DeleteFileData() error = nil, want ineligible-row error")
		}
		assertFileDataExists(t, repo, row, true)
	})
}

func insertFileDataForDeleteTest(t *testing.T, repo *Repository, row enteFileData.Row, isDeleted bool) {
	t.Helper()
	_, err := repo.DB.ExecContext(t.Context(), `
		INSERT INTO file_data (file_id, user_id, data_type, size, latest_bucket, is_deleted)
		VALUES ($1, $2, $3, 1, $4, $5)`,
		row.FileID, row.UserID, string(row.Type), row.LatestBucket, isDeleted)
	if err != nil {
		t.Fatalf("failed to insert file_data: %v", err)
	}
}

func assertFileDataExists(t *testing.T, repo *Repository, row enteFileData.Row, want bool) {
	t.Helper()
	var got bool
	err := repo.DB.QueryRowContext(t.Context(), `SELECT EXISTS (
		SELECT 1 FROM file_data WHERE file_id = $1 AND data_type = $2
	)`, row.FileID, string(row.Type)).Scan(&got)
	if err != nil {
		t.Fatalf("failed to check file_data: %v", err)
	}
	if got != want {
		t.Fatalf("file_data existence = %v, want %v", got, want)
	}
}
