package repo

import (
	"context"
	"database/sql"
	"strconv"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestPokesCreateDuringShareChanges(t *testing.T) {
	for _, operation := range []string{"update-recipient-shares", "reset-sender-access", "reset-recipient-access"} {
		t.Run(operation, func(t *testing.T) {
			module := newSpaceTestModule(t)
			alice, bob := notificationTestSpaces(t, module)
			ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
			defer cancel()
			for _, requestID := range []string{"first", "second"} {
				_, err := module.Pokes.Create(ctx, bob.SpaceID, alice.SpaceID, requestID)
				require.NoError(t, err)
				_, err = module.Pokes.Create(ctx, alice.SpaceID, bob.SpaceID, requestID)
				require.NoError(t, err)
			}
			space := alice
			if operation == "reset-sender-access" {
				space = bob
			}
			tx, err := module.Spaces.DB.BeginTx(ctx, nil)
			require.NoError(t, err)
			defer tx.Rollback()
			var pid int
			require.NoError(t, tx.QueryRowContext(ctx, `
				SELECT pg_backend_pid() FROM spaces WHERE space_id = $1 FOR UPDATE
			`, space.SpaceID).Scan(&pid))
			result := make(chan error, 1)
			go func() {
				defer close(result)
				_, err := module.Pokes.Create(ctx, bob.SpaceID, alice.SpaceID, "concurrent")
				result <- err
			}()
			t.Cleanup(func() {
				cancel()
				for range result {
				}
			})
			for {
				var waiting bool
				require.NoError(t, module.Spaces.DB.QueryRowContext(ctx, `
					SELECT EXISTS (
						SELECT 1 FROM pg_stat_activity WHERE datname = current_database()
						AND $1 = ANY(pg_blocking_pids(pid))
					)
				`, pid).Scan(&waiting))
				if waiting {
					break
				}
				time.Sleep(10 * time.Millisecond)
			}
			if operation == "update-recipient-shares" {
				_, err = tx.ExecContext(ctx, `
					UPDATE space_friend_shares SET friend_sealed_space_key = $3, key_version = $4
					WHERE space_id = $1 AND friend_space_id = $2
				`, alice.SpaceID, bob.SpaceID, testSpaceBytes("updated-share"), 1)
			} else {
				err = resetSpaceAccessTx(ctx, tx, space.OwnerID, []string{space.SpaceID})
			}
			require.NoError(t, err)
			require.NoError(t, tx.Commit())
			err = <-result
			if operation == "update-recipient-shares" {
				require.NoError(t, err)
				require.Equal(t, int64(5), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_pokes`))
				require.Equal(t, int64(2), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_notifications WHERE kind = 'poke'`))
			} else {
				require.ErrorIs(t, err, sql.ErrNoRows)
				require.Equal(t, int64(0), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_pokes`))
				require.Equal(t, int64(0), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_notifications WHERE kind = 'poke'`))
			}
		})
	}
}

func TestPokesKeepLatestNotificationAndReadState(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := t.Context()
	alice, bob := notificationTestSpaces(t, module)
	results := make(chan bool, 8)
	failures := make(chan error, 8)
	var workers sync.WaitGroup
	for range 8 {
		workers.Add(1)
		go func() {
			defer workers.Done()
			created, err := module.Pokes.Create(ctx, bob.SpaceID, alice.SpaceID, "first")
			results <- created
			failures <- err
		}()
	}
	workers.Wait()
	close(results)
	close(failures)
	createdCount := 0
	for created := range results {
		if created {
			createdCount++
		}
	}
	for err := range failures {
		require.NoError(t, err)
	}
	require.Equal(t, 1, createdCount)
	require.Equal(t, int64(1), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_pokes`))
	require.Equal(t, int64(1), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_notifications WHERE kind = 'poke'`))
	require.Equal(t, int64(0), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_messages`))
	unread, err := module.Read.HasUnreadNotifications(ctx, alice.SpaceID)
	require.NoError(t, err)
	require.False(t, unread)
	first, _, err := module.Notifications.List(ctx, alice.SpaceID, "", 20)
	require.NoError(t, err)
	require.Len(t, first, 1)
	require.NoError(t, module.Notifications.MarkRead(ctx, alice.SpaceID, first[0].NotificationIDs))
	_, err = module.Pokes.Create(ctx, bob.SpaceID, alice.SpaceID, "second")
	require.NoError(t, err)
	page, cursor, err := module.Notifications.List(ctx, alice.SpaceID, "", 1)
	require.NoError(t, err)
	require.Len(t, page, 1)
	require.Empty(t, cursor)
	require.Equal(t, "poke", page[0].Kind)
	require.Equal(t, bob.SpaceID, page[0].Actors[0].SpaceID)
	require.Equal(t, int64(1), page[0].ActorCount)
	require.True(t, page[0].Unread)
	require.Len(t, page[0].NotificationIDs, 1)
	require.NotEqual(t, first[0].NotificationID, page[0].NotificationID)
	require.Greater(t, page[0].CreatedAt, first[0].CreatedAt)
	require.Equal(t, int64(2), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_pokes`))
	require.Equal(t, int64(1), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_notifications WHERE kind = 'poke'`))
	require.NoError(t, module.Notifications.MarkRead(ctx, bob.SpaceID, page[0].NotificationIDs))
	unread, err = module.Notifications.HasUnread(ctx, alice.SpaceID)
	require.NoError(t, err)
	require.True(t, unread)
	_, err = module.Pokes.Create(ctx, bob.SpaceID, alice.SpaceID, "third")
	require.NoError(t, err)
	require.NoError(t, module.Notifications.MarkRead(ctx, alice.SpaceID, page[0].NotificationIDs))
	require.Equal(t, int64(1), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_notifications WHERE read_at IS NULL`))
	page, _, err = module.Notifications.List(ctx, alice.SpaceID, "", 20)
	require.NoError(t, err)
	require.Len(t, page, 1)
	require.True(t, page[0].Unread)
	require.Equal(t, []string{page[0].NotificationID}, page[0].NotificationIDs)
	latest := page[0]
	require.NoError(t, module.Notifications.MarkRead(ctx, alice.SpaceID, page[0].NotificationIDs))
	unread, err = module.Notifications.HasUnread(ctx, alice.SpaceID)
	require.NoError(t, err)
	require.False(t, unread)
	page, _, err = module.Notifications.List(ctx, alice.SpaceID, "", 20)
	require.NoError(t, err)
	require.Len(t, page, 1)
	require.False(t, page[0].Unread)
	require.Equal(t, []string{}, page[0].NotificationIDs)
	require.Equal(t, latest.NotificationID, page[0].NotificationID)
	require.Equal(t, latest.CreatedAt, page[0].CreatedAt)
	require.Equal(t, latest.Actors, page[0].Actors)
	for _, requestID := range []string{"third", "first"} {
		created, err := module.Pokes.Create(ctx, bob.SpaceID, alice.SpaceID, requestID)
		require.NoError(t, err)
		require.False(t, created)
		page, _, err = module.Notifications.List(ctx, alice.SpaceID, "", 20)
		require.NoError(t, err)
		require.Len(t, page, 1)
		require.False(t, page[0].Unread)
		require.Equal(t, latest.NotificationID, page[0].NotificationID)
		require.Equal(t, latest.CreatedAt, page[0].CreatedAt)
	}
	require.Equal(t, int64(3), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_pokes`))
	_, err = module.Pokes.Create(ctx, alice.SpaceID, bob.SpaceID, "reverse")
	require.NoError(t, err)
	require.Equal(t, int64(4), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_pokes`))
	require.Equal(t, int64(2), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_notifications WHERE kind = 'poke'`))
	require.NoError(t, module.Friends.DeleteFriendship(ctx, alice.SpaceID, bob.SpaceID))
	_, err = module.Pokes.Create(ctx, bob.SpaceID, alice.SpaceID, "not-friends")
	require.Error(t, err)
	page, _, err = module.Notifications.List(ctx, alice.SpaceID, "", 20)
	require.NoError(t, err)
	require.Empty(t, page)
	require.Equal(t, int64(0), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_notifications`))
	require.Equal(t, int64(0), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_pokes`))
}

func TestPokesConcurrentRequestsKeepOneNotificationPerDirection(t *testing.T) {
	module := newSpaceTestModule(t)
	alice, bob := notificationTestSpaces(t, module)
	ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
	defer cancel()
	_, err := module.Notifications.DB.ExecContext(ctx, `
		INSERT INTO space_notifications (notification_id, recipient_space_id, actor_space_id, kind)
		VALUES ('friend-notification', $1, $2, 'friend_accepted')
	`, alice.SpaceID, bob.SpaceID)
	require.NoError(t, err)
	results := make(chan bool, 32)
	failures := make(chan error, 32)
	var workers sync.WaitGroup
	for i := range 32 {
		workers.Add(1)
		go func() {
			defer workers.Done()
			sender, recipient := alice.SpaceID, bob.SpaceID
			if i%2 == 0 {
				sender, recipient = recipient, sender
			}
			created, err := module.Pokes.Create(ctx, sender, recipient, strconv.Itoa(i))
			results <- created
			failures <- err
		}()
	}
	workers.Wait()
	close(results)
	close(failures)
	for err := range failures {
		require.NoError(t, err)
	}
	for created := range results {
		require.True(t, created)
	}
	require.Equal(t, int64(32), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_pokes`))
	require.Equal(t, int64(2), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_notifications WHERE kind = 'poke'`))
	require.Equal(t, int64(1), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_notifications WHERE notification_id = 'friend-notification'`))
	require.Equal(t, int64(0), countSpaceRows(t, module, `
		SELECT COUNT(*) FROM space_pokes p JOIN space_notifications n ON n.poke_id = p.poke_id
		WHERE n.created_at <> p.created_at OR n.read_at IS NOT NULL
	`))
}
