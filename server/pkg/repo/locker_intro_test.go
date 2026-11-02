package repo

import (
	"fmt"
	"slices"
	"testing"

	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/utils/time"
)

func TestGetLockerIntroCandidates(t *testing.T) {
	const cutoff int64 = 1800000000000000
	const now = cutoff + 6*24*time.MicroSecondsInOneHour
	const eligibleSignup = now - 72*time.MicroSecondsInOneHour
	for _, tt := range []struct {
		name       string
		signup     int64
		now        int64
		photos     any
		locker     any
		adjustment string
		want       bool
	}{
		{name: "at rollout cutoff", signup: cutoff, photos: 1, locker: 0, want: true},
		{name: "before cutoff", signup: cutoff - 1, photos: 1, locker: 0},
		{name: "exactly seven days", signup: cutoff + 3*24*time.MicroSecondsInOneHour, now: cutoff + 10*24*time.MicroSecondsInOneHour, photos: 1, locker: 0, want: true},
		{name: "older than seven days", signup: cutoff + 3*24*time.MicroSecondsInOneHour - 1, now: cutoff + 10*24*time.MicroSecondsInOneHour, photos: 1, locker: 0},
		{name: "exactly 72 hours", signup: eligibleSignup, photos: 1, locker: 0, want: true},
		{name: "younger than 72 hours", signup: eligibleSignup + 1, photos: 1, locker: 0},
		{name: "empty Photos", signup: eligibleSignup, photos: 0, locker: 0},
		{name: "Locker in use", signup: eligibleSignup, photos: 1, locker: 1},
		{name: "unknown counts", signup: eligibleSignup},
		{name: "missing usage", signup: eligibleSignup, photos: 1, locker: 0, adjustment: `DELETE FROM usage WHERE user_id = 1`},
		{name: "deleted account", signup: eligibleSignup, photos: 1, locker: 0, adjustment: `UPDATE users SET encrypted_email = NULL, email_decryption_nonce = NULL, email_hash = 'deleted+1@ente.io' WHERE user_id = 1`},
		{name: "previous attempt", signup: eligibleSignup, photos: 1, locker: 0, adjustment: `INSERT INTO notification_history(user_id, template_id, sent_time) VALUES(1, 'locker_intro', 1)`},
		{name: "other notification", signup: eligibleSignup, photos: 1, locker: 0, adjustment: `INSERT INTO notification_history(user_id, template_id, sent_time) VALUES(1, 'first_upload', 1)`, want: true},
	} {
		t.Run(tt.name, func(t *testing.T) {
			db := getStorageWarningRepoTestDB(t)
			testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1, Email: "locker-intro@example.com", CreationTime: tt.signup})
			if _, err := db.Exec(`INSERT INTO usage(user_id, storage_consumed, photos_file_count, locker_file_count) VALUES(1, 0, $1, $2)`, tt.photos, tt.locker); err != nil {
				t.Fatal(err)
			}
			if tt.adjustment != "" {
				if _, err := db.Exec(tt.adjustment); err != nil {
					t.Fatal(err)
				}
			}
			selectionTime := int64(now)
			if tt.now != 0 {
				selectionTime = tt.now
			}
			got, err := (&NotificationHistoryRepository{DB: db}).GetLockerIntroCandidates(cutoff, selectionTime, "locker_intro")
			if err != nil {
				t.Fatal(err)
			}
			var want []int64
			if tt.want {
				want = []int64{1}
			}
			if !slices.Equal(got, want) {
				t.Fatalf("candidates = %v, want %v", got, want)
			}
		})
	}
}

func TestGetLockerIntroCandidatesOldestFirstLimit(t *testing.T) {
	db := getStorageWarningRepoTestDB(t)
	const cutoff int64 = 1800000000000000
	for id := int64(1); id <= 1001; id++ {
		signup := cutoff + 1
		if id == 1001 {
			signup = cutoff
		}
		testutil.InsertUser(t, db, testutil.UserFixture{UserID: id, Email: fmt.Sprintf("locker-%d@example.com", id), CreationTime: signup})
		if _, err := db.Exec(`INSERT INTO usage(user_id, storage_consumed, photos_file_count, locker_file_count) VALUES($1, 0, 1, 0)`, id); err != nil {
			t.Fatal(err)
		}
	}
	repo := &NotificationHistoryRepository{DB: db}
	got, err := repo.GetLockerIntroCandidates(cutoff, cutoff+4*24*time.MicroSecondsInOneHour, "locker_intro")
	if err != nil {
		t.Fatal(err)
	}
	want := []int64{1001}
	for id := int64(1); id <= 999; id++ {
		want = append(want, id)
	}
	if !slices.Equal(got, want) {
		t.Fatalf("candidates = %v, want %v", got, want)
	}
	for _, userID := range got {
		if err := repo.SetLastNotificationTimeToNow(userID, "locker_intro"); err != nil {
			t.Fatal(err)
		}
	}
	got, err = repo.GetLockerIntroCandidates(cutoff, cutoff+5*24*time.MicroSecondsInOneHour, "locker_intro")
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(got, []int64{1000}) {
		t.Fatalf("next run candidates = %v, want [1000]", got)
	}
}
