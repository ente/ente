package repo

import (
	"testing"

	"github.com/ente/museum/internal/testutil"
)

func TestGetLockerUsageUsesStoredAndLegacyCountsPerUser(t *testing.T) {
	db := setupFileUsageTest(t)
	readyUserID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "ready@ente.io", CreationTime: 1})
	legacyUserID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "legacy@ente.io", CreationTime: 1})
	testutil.InsertUsage(t, db, readyUserID, 0)
	testutil.InsertUsage(t, db, legacyUserID, 0)
	setReadyFileCounts(t, db, readyUserID, 0, 9)

	fileID := insertObjectTestFile(t, db, legacyUserID)
	collectionID := insertObjectTestCollection(t, db, legacyUserID)
	if _, err := db.Exec(`UPDATE collections SET app = 'locker' WHERE collection_id = $1`, collectionID); err != nil {
		t.Fatal(err)
	}
	linkObjectTestFileToCollection(t, db, collectionID, fileID, legacyUserID)

	var queued []int64
	usageRepo := &UsageRepository{
		DB:                           db,
		QueueFileCountInitialization: func(userID int64) { queued = append(queued, userID) },
	}
	usage, err := usageRepo.GetLockerUsage(t.Context(), []int64{readyUserID, legacyUserID})
	if err != nil {
		t.Fatal(err)
	}
	if usage.TotalFileCount != 10 {
		t.Fatalf("family usage = %+v, want 10 files", usage)
	}
	if len(usage.Users) != 2 || usage.Users[0].FileCount != 9 || usage.Users[1].FileCount != 1 {
		t.Fatalf("member usage = %+v, want stored then legacy count", usage.Users)
	}
	if len(queued) != 1 || queued[0] != legacyUserID {
		t.Fatalf("queued users = %v, want [%d]", queued, legacyUserID)
	}

	queued = nil
	usage, err = usageRepo.GetLockerStorageUsage(t.Context(), []int64{readyUserID, legacyUserID})
	if err != nil {
		t.Fatal(err)
	}
	if usage.TotalFileCount != 0 || len(queued) != 0 {
		t.Fatalf("storage-only usage = %+v, queued users = %v", usage, queued)
	}
}
