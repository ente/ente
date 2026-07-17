package controller

import (
	"context"
	"errors"
	"testing"

	"github.com/ente/museum/internal/testutil"
	lockctrl "github.com/ente/museum/pkg/controller/lock"
	baserepo "github.com/ente/museum/pkg/repo"
	timeutil "github.com/ente/museum/pkg/utils/time"
	spacerepo "github.com/ente/museum/space/repo"
	"github.com/stretchr/testify/require"
)

func TestProcessSpaceDripsReleasesLock(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	repos := spacerepo.NewModule(db, nil)
	controller := &SpaceDripController{
		DripsRepo: repos.Drips,
		UserRepo: &baserepo.UserRepository{
			DB:                  db,
			SecretEncryptionKey: testutil.SecretEncryptionKey(),
			HashingKey:          testutil.HashingKey(),
		},
		NotificationHistoryRepo: &baserepo.NotificationHistoryRepository{DB: db},
		LockController: &lockctrl.LockController{
			TaskLockingRepo: &baserepo.TaskLockRepository{DB: db},
			HostName:        "space-drip-test",
		},
	}

	controller.ProcessSpaceDrips()

	var lockCount int
	require.NoError(t, db.QueryRow(`SELECT COUNT(*) FROM task_lock WHERE task_name = $1`, spaceDripMailLock).Scan(&lockCount))
	require.Zero(t, lockCount)
}

func TestSpaceDripsSendMatureProfileNudgeOnly(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	ctx := context.Background()
	repos := spacerepo.NewModule(db, nil)
	now := timeutil.Microseconds()
	userID := insertSpaceControllerUser(t, repos, "profile-drip@example.com", "profile-drip-public")
	require.NoError(t, repos.Sessions.CreateBrowserSession(ctx, []byte("profile-drip-token-hash"), userID, "wrap-key", now+timeutil.MicroSecondsInOneHour))
	_, err := repos.Sessions.DB.Exec(`
		UPDATE space_browser_sessions
		SET created_at = $1, updated_at = $1, last_used_at = $1
		WHERE user_id = $2
	`, now-5*24*timeutil.MicroSecondsInOneHour, userID)
	require.NoError(t, err)

	originalSend := sendSpaceDripEmail
	t.Cleanup(func() {
		sendSpaceDripEmail = originalSend
	})
	var subjects []string
	var fromName, fromEmail string
	sendSpaceDripEmail = func(_ []string, name string, email string, subject string, _ string, _ map[string]interface{}, _ []map[string]interface{}) error {
		fromName = name
		fromEmail = email
		subjects = append(subjects, subject)
		return nil
	}

	controller := &SpaceDripController{
		DripsRepo: repos.Drips,
		UserRepo: &baserepo.UserRepository{
			DB:                  db,
			SecretEncryptionKey: testutil.SecretEncryptionKey(),
			HashingKey:          testutil.HashingKey(),
		},
		NotificationHistoryRepo: &baserepo.NotificationHistoryRepository{DB: db},
		BatchSize:               10,
	}
	stats, err := controller.processSpaceDrips(ctx, now)
	require.NoError(t, err)
	require.Equal(t, "Ente Space", fromName)
	require.Equal(t, "space@ente.com", fromEmail)
	require.Equal(t, []string{"Your Space setup is incomplete"}, subjects)
	require.Equal(t, 1, stats.SentByTemplate[SpaceDripProfileMissing4dTemplateID])

	history, err := controller.NotificationHistoryRepo.GetLastNotificationTimes(userID, []string{
		SpaceDripProfileMissing24hTemplateID,
		SpaceDripProfileMissing4dTemplateID,
	})
	require.NoError(t, err)
	require.Zero(t, history[SpaceDripProfileMissing24hTemplateID])
	require.NotZero(t, history[SpaceDripProfileMissing4dTemplateID])

	stats, err = controller.processSpaceDrips(ctx, now+timeutil.MicroSecondsInOneHour)
	require.NoError(t, err)
	require.Empty(t, stats.SentByTemplate)
	require.Len(t, subjects, 1)
}

func TestSpaceDripsDoNotFallBackToEarlierStageAfterSendFailure(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	ctx := context.Background()
	repos := spacerepo.NewModule(db, nil)
	now := timeutil.Microseconds()
	userID := insertSpaceControllerUser(t, repos, "profile-drip-failure@example.com", "profile-drip-failure-public")
	require.NoError(t, repos.Sessions.CreateBrowserSession(ctx, []byte("profile-drip-failure-token-hash"), userID, "wrap-key", now+timeutil.MicroSecondsInOneHour))
	_, err := repos.Sessions.DB.Exec(`
		UPDATE space_browser_sessions
		SET created_at = $1, updated_at = $1, last_used_at = $1
		WHERE user_id = $2
	`, now-5*24*timeutil.MicroSecondsInOneHour, userID)
	require.NoError(t, err)

	originalSend := sendSpaceDripEmail
	t.Cleanup(func() {
		sendSpaceDripEmail = originalSend
	})
	var subjects []string
	sendSpaceDripEmail = func(_ []string, _ string, _ string, subject string, _ string, _ map[string]interface{}, _ []map[string]interface{}) error {
		subjects = append(subjects, subject)
		return errors.New("send failed")
	}

	controller := &SpaceDripController{
		DripsRepo: repos.Drips,
		UserRepo: &baserepo.UserRepository{
			DB:                  db,
			SecretEncryptionKey: testutil.SecretEncryptionKey(),
			HashingKey:          testutil.HashingKey(),
		},
		NotificationHistoryRepo: &baserepo.NotificationHistoryRepository{DB: db},
		BatchSize:               10,
	}
	stats, err := controller.processSpaceDrips(ctx, now)
	require.NoError(t, err)
	require.Empty(t, stats.SentByTemplate)
	require.Equal(t, []string{"Your Space setup is incomplete"}, subjects)
}
