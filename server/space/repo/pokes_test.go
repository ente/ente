package repo

import (
	"sync"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestPokesCreateNotificationsOnceAndGroupReadState(t *testing.T) {
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
	require.NoError(t, module.Notifications.MarkRead(ctx, bob.SpaceID, []string{page[0].NotificationID}))
	unread, err = module.Notifications.HasUnread(ctx, alice.SpaceID)
	require.NoError(t, err)
	require.True(t, unread)
	_, err = module.Pokes.Create(ctx, bob.SpaceID, alice.SpaceID, "third")
	require.NoError(t, err)
	require.NoError(t, module.Notifications.MarkRead(ctx, alice.SpaceID, []string{page[0].NotificationID}))
	require.Equal(t, int64(1), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_notifications WHERE read_at IS NULL`))
	page, _, err = module.Notifications.List(ctx, alice.SpaceID, "", 20)
	require.NoError(t, err)
	require.NoError(t, module.Notifications.MarkRead(ctx, alice.SpaceID, []string{page[0].NotificationID}))
	unread, err = module.Notifications.HasUnread(ctx, alice.SpaceID)
	require.NoError(t, err)
	require.False(t, unread)
	_, err = module.Pokes.DB.ExecContext(ctx, `DELETE FROM space_pokes WHERE client_request_id = 'third'`)
	require.NoError(t, err)
	require.Equal(t, int64(2), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_notifications`))
	require.NoError(t, module.Friends.DeleteFriendship(ctx, alice.SpaceID, bob.SpaceID))
	_, err = module.Pokes.Create(ctx, bob.SpaceID, alice.SpaceID, "not-friends")
	require.Error(t, err)
	page, _, err = module.Notifications.List(ctx, alice.SpaceID, "", 20)
	require.NoError(t, err)
	require.Empty(t, page)
	require.Equal(t, int64(0), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_notifications`))
}
