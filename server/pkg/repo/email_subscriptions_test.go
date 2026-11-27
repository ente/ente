package repo

import (
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/utils/crypto"
)

func TestBackfillProductMails(t *testing.T) {
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	repository := &EmailSubscriptionRepository{DB: db}
	const cutoff = 20

	preferences := make(map[string]bool)
	hashingKey := testutil.HashingKey()
	addPreference := func(email string, subscribed bool) {
		t.Helper()
		hash, err := crypto.GetHash(email, hashingKey)
		if err != nil {
			t.Fatal(err)
		}
		preferences[hash] = subscribed
	}
	insertUser := func(email string, creationTime int64, subscribed bool) int64 {
		t.Helper()
		addPreference(email, subscribed)
		return testutil.InsertUser(t, db, testutil.UserFixture{Email: email, CreationTime: creationTime})
	}
	subscribed := insertUser("subscribed@example.test", cutoff-1, true)
	suppressed := insertUser("suppressed@example.test", cutoff-1, false)
	existingOptOut := insertUser("existing-optout@example.test", cutoff-1, true)
	existingOptIn := insertUser("existing-optin@example.test", cutoff-1, false)
	deleted := insertUser("deleted@example.test", cutoff-1, true)
	insertUser("at-cutoff@example.test", cutoff, true)
	insertUser("after-cutoff@example.test", cutoff+1, true)
	addPreference("missing@example.test", true)
	if err := (&UserRepository{DB: db}).Delete(deleted); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`
		INSERT INTO email_subscriptions (user_id, email_type, subscribed)
		VALUES ($1, $3, FALSE), ($2, $3, TRUE)`, existingOptOut, existingOptIn, ente.ProductMailsEmailType); err != nil {
		t.Fatal(err)
	}

	checkBackfill := func(apply bool, want EmailSubscriptionBackfillCounts, wantRows map[int64]bool) {
		t.Helper()
		got, err := repository.BackfillProductMails(t.Context(), preferences, cutoff, apply)
		if err != nil || got != want {
			t.Fatalf("apply=%t: counts=%+v, err=%v, want %+v", apply, got, err, want)
		}
		var rowCount int
		if err := db.QueryRow(`SELECT count(*) FROM email_subscriptions`).Scan(&rowCount); err != nil || rowCount != len(wantRows) {
			t.Fatalf("apply=%t: got %d rows, err=%v, want %d", apply, rowCount, err, len(wantRows))
		}
		for userID, wantSubscribed := range wantRows {
			var subscribed bool
			err := db.QueryRow(`SELECT subscribed FROM email_subscriptions WHERE user_id = $1 AND email_type = $2`,
				userID, ente.ProductMailsEmailType).Scan(&subscribed)
			if err != nil || subscribed != wantSubscribed {
				t.Fatalf("apply=%t: user %d subscription=%t, err=%v, want %t", apply, userID, subscribed, err, wantSubscribed)
			}
		}
	}

	firstRun := EmailSubscriptionBackfillCounts{
		Matched: 6, Unmatched: 2, AfterCutoff: 2, Existing: 2, OptOutConflicts: 1, Subscribed: 1, Suppressed: 1,
	}
	checkBackfill(false, firstRun, map[int64]bool{existingOptOut: false, existingOptIn: true})

	applied := map[int64]bool{existingOptOut: false, existingOptIn: true, subscribed: true, suppressed: false}
	checkBackfill(true, firstRun, applied)
	checkBackfill(true, EmailSubscriptionBackfillCounts{
		Matched: 6, Unmatched: 2, AfterCutoff: 2, Existing: 4, OptOutConflicts: 1,
	}, applied)
}
