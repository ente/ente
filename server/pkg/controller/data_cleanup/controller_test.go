package data_cleanup

import (
	"testing"

	cleanupentity "github.com/ente/museum/ente/data_cleanup"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	cleanuprepo "github.com/ente/museum/pkg/repo/datacleanup"
)

func TestStartCleanupCancelsRecoveredAccount(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		if _, err := db.Exec(`DELETE FROM data_cleanup`); err != nil {
			t.Errorf("failed to clear data_cleanup: %v", err)
		}
		testutil.ResetTables(t, db)
	})

	tests := []struct {
		name             string
		cleanupRowExists bool
	}{
		{name: "stale fetched row"},
		{name: "legacy cleanup row", cleanupRowExists: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if _, err := db.Exec(`DELETE FROM data_cleanup`); err != nil {
				t.Fatalf("failed to clear data_cleanup: %v", err)
			}
			testutil.ResetTables(t, db)

			userID := testutil.InsertUser(t, db, testutil.UserFixture{
				UserID:       82,
				Email:        "recovered@example.com",
				CreationTime: 1,
			})
			if tt.cleanupRowExists {
				if _, err := db.Exec(`INSERT INTO data_cleanup(user_id) VALUES($1)`, userID); err != nil {
					t.Fatalf("failed to insert cleanup row: %v", err)
				}
			}
			controller := &DeleteUserCleanupController{
				Repo: &cleanuprepo.Repository{DB: db},
				UserRepo: &repo.UserRepository{
					DB:                  db,
					SecretEncryptionKey: testutil.SecretEncryptionKey(),
				},
			}

			if err := controller.startCleanup(t.Context(), &cleanupentity.DataCleanup{
				UserID: userID,
				Stage:  cleanupentity.Scheduled,
			}); err != nil {
				t.Fatalf("startCleanup() error = %v", err)
			}
			var cleanupRows int
			if err := db.QueryRow(`SELECT count(*) FROM data_cleanup WHERE user_id = $1`, userID).Scan(&cleanupRows); err != nil {
				t.Fatalf("failed to count cleanup rows: %v", err)
			}
			if cleanupRows != 0 {
				t.Fatalf("cleanup row count = %d, want 0", cleanupRows)
			}
		})
	}
}
