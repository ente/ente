package user

import (
	"testing"

	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/repo"
)

func TestCreateUserInitializesFileCounts(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	c := &UserController{
		UserRepo:               &repo.UserRepository{DB: db},
		UsageRepo:              &repo.UsageRepository{DB: db},
		BillingRepo:            &repo.BillingRepository{DB: db},
		MailingListsController: &controller.MailingListsController{},
		SecretEncryptionKey:    testutil.SecretEncryptionKey(),
		HashingKey:             testutil.HashingKey(),
	}
	userID, _, err := c.createUser(t.Context(), "new-user@ente.io", nil)
	if err != nil {
		t.Fatal(err)
	}
	var photos, locker, version int64
	if err := db.QueryRow(`SELECT photos_file_count, locker_file_count, file_count_source_version
		FROM usage WHERE user_id = $1`, userID).Scan(&photos, &locker, &version); err != nil {
		t.Fatal(err)
	}
	if photos != 0 || locker != 0 || version != 0 {
		t.Fatalf("file count state = (%d, %d, %d), want (0, 0, 0)", photos, locker, version)
	}
}

func TestCreateUserRollsBackWhenSubscriptionCreationFails(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })

	controller := &UserController{
		UserRepo:            &repo.UserRepository{DB: db},
		UsageRepo:           &repo.UsageRepository{DB: db},
		BillingRepo:         &repo.BillingRepository{DB: db},
		SecretEncryptionKey: testutil.SecretEncryptionKey(),
		HashingKey:          testutil.HashingKey(),
	}

	_, err := db.Exec(`ALTER TABLE subscriptions
		ADD CONSTRAINT reject_free_subscription_for_atomicity_test
		CHECK (false)`)
	if err != nil {
		t.Fatalf("failed to install subscription failure constraint: %v", err)
	}
	t.Cleanup(func() {
		if _, err := db.Exec(`ALTER TABLE subscriptions
			DROP CONSTRAINT reject_free_subscription_for_atomicity_test`); err != nil {
			t.Errorf("failed to remove subscription failure constraint: %v", err)
		}
	})

	if _, _, err := controller.createUser(t.Context(), "incomplete-user@ente.io", nil); err == nil {
		t.Fatal("createUser() succeeded despite subscription failure")
	}

	var users, usages, subscriptions int64
	err = db.QueryRow(`SELECT
		(SELECT count(*) FROM users),
		(SELECT count(*) FROM usage),
		(SELECT count(*) FROM subscriptions)`).Scan(&users, &usages, &subscriptions)
	if err != nil {
		t.Fatalf("failed to count account rows: %v", err)
	}
	if users != 0 || usages != 0 || subscriptions != 0 {
		t.Fatalf("partial account persisted: users=%d usage=%d subscriptions=%d", users, usages, subscriptions)
	}
}
