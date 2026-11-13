package repo

import (
	"testing"

	"github.com/ente/museum/internal/testutil"
	"github.com/stretchr/testify/require"
)

func TestGetUploadUsage(t *testing.T) {
	db := setupFileUsageTest(t)
	for _, user := range []testutil.UserFixture{
		{UserID: 10, Email: "upload-owner@ente.com", CreationTime: 1},
		{UserID: 20, Email: "upload-member@ente.com", CreationTime: 1},
		{UserID: 30, Email: "uninitialized@ente.com", CreationTime: 1},
	} {
		testutil.InsertUser(t, db, user)
	}
	_, err := db.Exec(`INSERT INTO usage(user_id, storage_consumed, photos_file_count, locker_file_count)
		VALUES (10, 40, 50000, 0), (20, 60, 0, 0), (30, 100, NULL, NULL)`)
	require.NoError(t, err)
	repository := &UsageRepository{DB: db}
	for _, tc := range []struct {
		name                string
		userID              int64
		subscriptionUserIDs []int64
		want                UploadUsage
	}{
		{"individual", 10, []int64{10}, UploadUsage{TotalStorage: 40, UserStorage: 40, PhotosFileCount: new(int64(50_000))}},
		{"family member", 20, []int64{10, 20}, UploadUsage{TotalStorage: 100, UserStorage: 60, PhotosFileCount: new(int64(0))}},
		{"uninitialized", 30, []int64{10, 20, 30}, UploadUsage{TotalStorage: 200, UserStorage: 100}},
		{"missing usage", 40, []int64{40}, UploadUsage{}},
		{"outside active family", 20, []int64{10}, UploadUsage{TotalStorage: 40, UserStorage: 60, PhotosFileCount: new(int64(0))}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			usage, err := repository.GetUploadUsage(t.Context(), tc.userID, tc.subscriptionUserIDs)
			require.NoError(t, err)
			require.Equal(t, tc.want, usage)
		})
	}
}
