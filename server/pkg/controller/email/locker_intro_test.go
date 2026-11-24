package email

import (
	"io"
	"net/http"
	"strings"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/controller/lock"
	"github.com/ente/museum/pkg/external/postmark"
	"github.com/ente/museum/pkg/repo"
	emailutil "github.com/ente/museum/pkg/utils/email"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/spf13/viper"
)

type lockerIntroTestTransport struct{}

func (lockerIntroTestTransport) RoundTrip(*http.Request) (*http.Response, error) {
	return &http.Response{
		StatusCode: http.StatusOK,
		Body:       io.NopCloser(strings.NewReader(`[{"ErrorCode":0}]`)),
	}, nil
}

func TestSilentMuseumSkipsLockerIntro(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	oldTransport := http.DefaultTransport
	http.DefaultTransport = lockerIntroTestTransport{}
	t.Cleanup(func() { http.DefaultTransport = oldTransport })
	oldSilent := viper.GetBool("internal.silent")
	t.Cleanup(func() { viper.Set("internal.silent", oldSilent) })

	links, err := emailutil.NewUnsubscribeLinks("https://museum.example.test", []string{strings.Repeat("a", 32)})
	if err != nil {
		t.Fatal(err)
	}
	taskLocks := &repo.TaskLockRepository{DB: db}
	history := &repo.NotificationHistoryRepository{DB: db}
	sender := &SubscriptionSender{
		Subscriptions:       &repo.EmailSubscriptionRepository{DB: db},
		Users:               &repo.UserRepository{DB: db, SecretEncryptionKey: testutil.SecretEncryptionKey()},
		NotificationHistory: history,
		Links:               links,
		Postmark:            postmark.Client{ServerToken: "test-token"},
		From:                "team@example.test",
		Streams:             map[ente.EmailType]string{ente.ProductMailsEmailType: "product-mails"},
	}
	job := &EmailNotificationController{
		LockController:          &lock.LockController{TaskLockingRepo: taskLocks, HostName: "museum-test"},
		NotificationHistoryRepo: history,
		SubscriptionSender:      sender,
	}
	id := testutil.InsertUser(t, db, testutil.UserFixture{Email: "eligible@example.test", CreationTime: lockerIntroRolloutTime})
	if _, err := db.Exec(`
		INSERT INTO usage (user_id, storage_consumed, photos_file_count, locker_file_count)
		VALUES ($1, 0, 1, 0)`, id); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`
		INSERT INTO email_subscriptions (user_id, email_type, subscribed) VALUES ($1, $2, TRUE)`,
		id, ente.ProductMailsEmailType); err != nil {
		t.Fatal(err)
	}
	assertAttempts := func(want int) {
		t.Helper()
		var got int
		if err := db.QueryRow(`SELECT count(*) FROM notification_history WHERE template_id = $1`,
			LockerIntroTemplateID).Scan(&got); err != nil || got != want {
			t.Fatalf("Locker intro attempts = %d, err = %v, want %d", got, err, want)
		}
	}
	now := lockerIntroRolloutTime + 4*24*time.MicroSecondsInOneHour
	viper.Set("internal.silent", true)
	job.SendLockerIntroMails(now)
	assertAttempts(0)

	viper.Set("internal.silent", false)
	job.SendLockerIntroMails(now)
	assertAttempts(1)
}
