package usercache

import (
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/ente/cache"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
)

func TestGetUserFileCountUsesStoredCountOrQueuesInitialization(t *testing.T) {
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	userID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "count@ente.io", CreationTime: 1})
	testutil.InsertUsage(t, db, userID, 0)
	if _, err := db.Exec(`UPDATE usage SET photos_file_count = 9, locker_file_count = 0 WHERE user_id = $1`, userID); err != nil {
		t.Fatal(err)
	}

	queued := 0
	userCache := cache.NewUserCache()
	userCache.SetFileCount(userID, &cache.FileCountCache{Count: 41}, ente.Photos)
	controller := &Controller{
		FileRepo:  &repo.FileRepository{DB: db},
		UsageRepo: &repo.UsageRepository{DB: db, QueueFileCountInitialization: func(int64) { queued++ }},
		TrashRepo: &repo.TrashRepository{DB: db},
		UserCache: userCache,
	}
	count, err := controller.GetUserFileCountWithCache(userID, ente.Photos)
	if err != nil || count != 9 || queued != 0 {
		t.Fatalf("ready count = (%d, %v), queued %d; want (9, nil), queued 0", count, err, queued)
	}

	if _, err := db.Exec(`UPDATE usage SET photos_file_count = NULL, locker_file_count = NULL WHERE user_id = $1`, userID); err != nil {
		t.Fatal(err)
	}
	controller.UserCache = cache.NewUserCache()
	count, err = controller.GetUserFileCountWithCache(userID, ente.Photos)
	if err != nil || count != 0 || queued != 1 {
		t.Fatalf("legacy count = (%d, %v), queued %d; want (0, nil), queued 1", count, err, queued)
	}
}
