package repo

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/lib/pq"
	"github.com/stretchr/testify/require"
)

func notificationTestSpaces(t *testing.T, module *Module) (*SpaceRecord, *SpaceRecord) {
	t.Helper()
	ctx := t.Context()
	aliceID := insertSpaceUser(t, module, "alice-notifications@example.com", "alice-public")
	bobID := insertSpaceUser(t, module, "bob-notifications@example.com", "bob-public")
	alice, err := testCreateSpace(ctx, module, aliceID, "alice_notifications", "root", "alice-public", "secret", "nonce", "profile")
	require.NoError(t, err)
	bob, err := testCreateSpace(ctx, module, bobID, "bob_notifications", "root", "bob-public", "secret", "nonce", "profile")
	require.NoError(t, err)
	require.NoError(t, testAddFriend(ctx, module, bobID, bob.SpaceID, alice.SpaceID, "alice-share", 1, "bob-share", 1))
	return alice, bob
}

func TestPostLikeNotificationLifecycle(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := t.Context()
	alice, bob := notificationTestSpaces(t, module)
	postID, err := testCreatePost(ctx, module, alice.OwnerID, alice.SpaceID, "post-key", nil, 1, nil)
	require.NoError(t, err)
	var workers sync.WaitGroup
	results := make(chan bool, 8)
	errors := make(chan error, 8)
	for range 8 {
		workers.Add(1)
		go func() {
			defer workers.Done()
			created, err := module.Posts.SetLikeWithCreated(ctx, postID, bob.SpaceID, true)
			results <- created
			errors <- err
		}()
	}
	workers.Wait()
	close(results)
	close(errors)
	createdCount := 0
	for created := range results {
		if created {
			createdCount++
		}
	}
	for err := range errors {
		require.NoError(t, err)
	}
	require.Equal(t, 1, createdCount)
	items, cursor, err := module.Notifications.List(ctx, alice.SpaceID, "", 20)
	require.NoError(t, err)
	require.Empty(t, cursor)
	require.Len(t, items, 1)
	require.Equal(t, bob.SpaceID, items[0].Actors[0].SpaceID)
	require.Equal(t, postID, items[0].PostID.Int64)
	require.True(t, items[0].Unread)
	originalID := items[0].NotificationID
	unread, err := module.Notifications.HasUnread(ctx, alice.SpaceID)
	require.NoError(t, err)
	require.True(t, unread)
	messagesUnread, err := module.Read.HasUnreadNotifications(ctx, alice.SpaceID)
	require.NoError(t, err)
	require.False(t, messagesUnread)
	require.Equal(t, int64(0), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_messages WHERE kind = 'post_like'`))
	post, err := module.Posts.GetPost(ctx, postID, bob.SpaceID)
	require.NoError(t, err)
	require.True(t, post.ViewerLiked)

	require.NoError(t, module.Notifications.MarkRead(ctx, bob.SpaceID, []string{originalID}))
	unread, err = module.Notifications.HasUnread(ctx, alice.SpaceID)
	require.NoError(t, err)
	require.True(t, unread)
	require.NoError(t, module.Notifications.MarkRead(ctx, alice.SpaceID, []string{originalID}))
	require.NoError(t, module.Notifications.MarkRead(ctx, alice.SpaceID, []string{originalID}))
	unread, err = module.Notifications.HasUnread(ctx, alice.SpaceID)
	require.NoError(t, err)
	require.False(t, unread)
	var marker int64
	require.NoError(t, module.Read.DB.QueryRow(`SELECT read_at FROM space_notification_read_markers WHERE viewer_space_id = $1 AND friend_space_id = $2`, alice.SpaceID, bob.SpaceID).Scan(&marker))
	require.Equal(t, int64(1), marker)

	_, err = module.Posts.SetLikeWithCreated(ctx, postID, bob.SpaceID, false)
	require.NoError(t, err)
	require.Equal(t, int64(0), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_notifications`))
	post, err = module.Posts.GetPost(ctx, postID, bob.SpaceID)
	require.NoError(t, err)
	require.False(t, post.ViewerLiked)
	_, err = module.Posts.SetLikeWithCreated(ctx, postID, bob.SpaceID, true)
	require.NoError(t, err)
	items, _, err = module.Notifications.List(ctx, alice.SpaceID, "", 20)
	require.NoError(t, err)
	require.Len(t, items, 1)
	require.NotEqual(t, originalID, items[0].NotificationID)
	require.True(t, items[0].Unread)
	require.NoError(t, module.Posts.DeletePost(ctx, postID, alice.SpaceID))
	require.Equal(t, int64(0), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_notifications`))
	_, err = module.Posts.SetLikeWithCreated(ctx, postID, bob.SpaceID, true)
	require.ErrorIs(t, err, sql.ErrNoRows)
}

func TestPostLikeAndReplyDoNotDeadlock(t *testing.T) {
	module := newSpaceTestModule(t)
	alice, bob := notificationTestSpaces(t, module)
	ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
	defer cancel()
	postID, err := testCreatePost(ctx, module, alice.OwnerID, alice.SpaceID, "post-key", nil, 1, nil)
	require.NoError(t, err)
	tx, err := module.Messages.DB.BeginTx(ctx, nil)
	require.NoError(t, err)
	defer tx.Rollback()
	var pid int
	require.NoError(t, tx.QueryRowContext(ctx, `
		SELECT pg_backend_pid() FROM spaces WHERE space_id = $1 FOR UPDATE
	`, bob.SpaceID).Scan(&pid))
	result := make(chan error, 1)
	go func() {
		defer close(result)
		_, err := module.Posts.SetLikeWithCreated(ctx, postID, bob.SpaceID, true)
		result <- err
	}()
	t.Cleanup(func() {
		cancel()
		for range result {
		}
	})
	for {
		var waiting bool
		require.NoError(t, module.Messages.DB.QueryRowContext(ctx, `
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
	_, err = tx.ExecContext(ctx, `
		INSERT INTO space_messages (
			message_id, sender_space_id, recipient_space_id, kind, reply_post_id,
			message_cipher, sender_encrypted_message_key, recipient_encrypted_message_key
		)
		VALUES ('concurrent-reply', $1, $2, 'post_reply', $3, $4, $5, $6)
	`, bob.SpaceID, alice.SpaceID, postID, testSpaceBytes("reply"), testSpaceBytes("sender-key"), testSpaceBytes("recipient-key"))
	require.NoError(t, err)
	require.NoError(t, tx.Commit())
	require.NoError(t, <-result)
	require.Equal(t, int64(1), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_messages WHERE kind = 'post_reply'`))
	require.Equal(t, int64(1), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_post_likes`))
	require.Equal(t, int64(1), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_notifications WHERE kind = 'post_like'`))
}

func TestNotificationsPaginationAndReadIsolation(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := t.Context()
	alice, bob := notificationTestSpaces(t, module)
	for range 3 {
		postID, err := testCreatePost(ctx, module, alice.OwnerID, alice.SpaceID, "post-key", nil, 1, nil)
		require.NoError(t, err)
		require.NoError(t, testSetPostLike(ctx, module, postID, bob.SpaceID, true))
	}
	_, err := module.Notifications.DB.Exec(`UPDATE space_notifications SET created_at = 1000`)
	require.NoError(t, err)
	first, cursor, err := module.Notifications.List(ctx, alice.SpaceID, "", 2)
	require.NoError(t, err)
	require.Len(t, first, 2)
	require.NotEmpty(t, cursor)
	second, next, err := module.Notifications.List(ctx, alice.SpaceID, cursor, 2)
	require.NoError(t, err)
	require.Len(t, second, 1)
	require.Empty(t, next)
	require.NotEqual(t, first[0].NotificationID, second[0].NotificationID)
	require.NotEqual(t, first[1].NotificationID, second[0].NotificationID)
	require.NoError(t, module.Notifications.MarkRead(ctx, alice.SpaceID, []string{first[0].NotificationID, first[1].NotificationID}))
	second, _, err = module.Notifications.List(ctx, alice.SpaceID, cursor, 2)
	require.NoError(t, err)
	require.True(t, second[0].Unread)
	require.NoError(t, module.Read.UpsertNotificationReadMarker(ctx, alice.SpaceID, bob.SpaceID, 10000))
	unread, err := module.Notifications.HasUnread(ctx, alice.SpaceID)
	require.NoError(t, err)
	require.True(t, unread)
	other, _, err := module.Notifications.List(ctx, bob.SpaceID, "", 20)
	require.NoError(t, err)
	require.Empty(t, other)
	require.NoError(t, module.Friends.DeleteFriendship(ctx, alice.SpaceID, bob.SpaceID))
	hidden, _, err := module.Notifications.List(ctx, alice.SpaceID, "", 20)
	require.NoError(t, err)
	require.Empty(t, hidden)
	unread, err = module.Notifications.HasUnread(ctx, alice.SpaceID)
	require.NoError(t, err)
	require.False(t, unread)
}

func TestNotificationsPaginateCompletePostGroups(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := t.Context()
	alice, bob := notificationTestSpaces(t, module)
	actors := []*SpaceRecord{bob}
	for i := 1; i < 25; i++ {
		ownerID := insertSpaceUser(t, module, fmt.Sprintf("liker-%d@example.com", i), "public")
		actor, err := testCreateSpace(ctx, module, ownerID, fmt.Sprintf("liker_%d", i), "root", "public", "secret", "nonce", "profile")
		require.NoError(t, err)
		require.NoError(t, testAddFriend(ctx, module, ownerID, actor.SpaceID, alice.SpaceID, "share", 1, "share", 1))
		actors = append(actors, actor)
	}
	posts := make([]int64, 3)
	for i, count := range []int{25, 2, 1} {
		postID, err := testCreatePost(ctx, module, alice.OwnerID, alice.SpaceID, "key", nil, 1, nil)
		require.NoError(t, err)
		posts[i] = postID
		for j, actor := range actors[:count] {
			require.NoError(t, testSetPostLike(ctx, module, postID, actor.SpaceID, true))
			_, err = module.Notifications.DB.ExecContext(ctx, `
				UPDATE space_notifications n SET created_at = $1
				FROM space_post_likes l WHERE l.like_id = n.post_like_id AND l.post_id = $2 AND l.actor_space_id = $3
			`, (3-i)*1000+j, postID, actor.SpaceID)
			require.NoError(t, err)
		}
	}
	first, cursor, err := module.Notifications.List(ctx, alice.SpaceID, "", 2)
	require.NoError(t, err)
	require.Len(t, first, 2)
	require.Equal(t, posts[0], first[0].PostID.Int64)
	require.Equal(t, int64(25), first[0].ActorCount)
	require.Len(t, first[0].NotificationIDs, 25)
	require.Contains(t, first[0].NotificationIDs, first[0].NotificationID)
	require.Len(t, first[0].Actors, 2)
	require.Equal(t, actors[24].SpaceID, first[0].Actors[0].SpaceID)
	require.Equal(t, actors[23].SpaceID, first[0].Actors[1].SpaceID)
	require.Equal(t, posts[1], first[1].PostID.Int64)
	require.Equal(t, int64(2), first[1].ActorCount)
	require.NotEmpty(t, cursor)
	second, next, err := module.Notifications.List(ctx, alice.SpaceID, cursor, 2)
	require.NoError(t, err)
	require.Len(t, second, 1)
	require.Equal(t, posts[2], second[0].PostID.Int64)
	require.Equal(t, int64(1), second[0].ActorCount)
	require.Len(t, second[0].Actors, 1)
	require.Empty(t, next)
	_, err = module.Notifications.DB.ExecContext(ctx, `UPDATE space_notifications SET read_at = 4000 WHERE notification_id = $1`, first[0].NotificationID)
	require.NoError(t, err)
	partlyRead, _, err := module.Notifications.List(ctx, alice.SpaceID, "", 2)
	require.NoError(t, err)
	require.True(t, partlyRead[0].Unread)

	require.NoError(t, testSetPostLike(ctx, module, posts[0], bob.SpaceID, false))
	require.NoError(t, testSetPostLike(ctx, module, posts[0], bob.SpaceID, true))
	require.NoError(t, module.Notifications.MarkRead(ctx, alice.SpaceID, first[0].NotificationIDs))
	updated, _, err := module.Notifications.List(ctx, alice.SpaceID, "", 2)
	require.NoError(t, err)
	require.True(t, updated[0].Unread)
	require.True(t, updated[1].Unread)
	require.Equal(t, int64(25), updated[0].ActorCount)
	require.Equal(t, bob.SpaceID, updated[0].Actors[0].SpaceID)
	require.Equal(t, actors[24].SpaceID, updated[0].Actors[1].SpaceID)
	require.Equal(t, int64(1), countSpaceRows(t, module, `
		SELECT COUNT(*) FROM space_notifications n JOIN space_post_likes l ON l.like_id = n.post_like_id
		WHERE l.post_id = $1 AND n.read_at IS NULL
	`, posts[0]))
	require.NoError(t, module.Notifications.MarkRead(ctx, alice.SpaceID, updated[0].NotificationIDs))
	updated, _, err = module.Notifications.List(ctx, alice.SpaceID, "", 2)
	require.NoError(t, err)
	require.False(t, updated[0].Unread)
	require.True(t, updated[1].Unread)

	require.NoError(t, testSetPostLike(ctx, module, posts[0], bob.SpaceID, false))
	updated, _, err = module.Notifications.List(ctx, alice.SpaceID, "", 2)
	require.NoError(t, err)
	require.Equal(t, int64(24), updated[0].ActorCount)
	require.Equal(t, actors[24].SpaceID, updated[0].Actors[0].SpaceID)
	require.False(t, updated[0].Unread)
	_, err = module.Notifications.DB.ExecContext(ctx, `UPDATE space_notifications SET read_at = NULL WHERE actor_space_id = ANY($1)`, pq.Array([]string{actors[24].SpaceID, actors[23].SpaceID}))
	require.NoError(t, err)
	require.NoError(t, module.Friends.DeleteFriendship(ctx, alice.SpaceID, actors[24].SpaceID))
	_, err = module.Notifications.DB.ExecContext(ctx, `UPDATE users SET encrypted_email = NULL WHERE user_id = $1`, actors[23].OwnerID)
	require.NoError(t, err)
	updated, _, err = module.Notifications.List(ctx, alice.SpaceID, "", 2)
	require.NoError(t, err)
	require.Equal(t, int64(22), updated[0].ActorCount)
	require.Equal(t, actors[22].SpaceID, updated[0].Actors[0].SpaceID)
	require.False(t, updated[0].Unread)
	require.NoError(t, module.Notifications.MarkRead(ctx, alice.SpaceID, updated[0].NotificationIDs))
	require.Equal(t, int64(2), countSpaceRows(t, module, `
		SELECT COUNT(*) FROM space_notifications n JOIN space_post_likes l ON l.like_id = n.post_like_id
		WHERE l.post_id = $1 AND n.read_at IS NULL
	`, posts[0]))
	require.NoError(t, module.Posts.DeletePost(ctx, posts[0], alice.SpaceID))
	updated, next, err = module.Notifications.List(ctx, alice.SpaceID, "", 2)
	require.NoError(t, err)
	require.Len(t, updated, 2)
	require.Equal(t, posts[1], updated[0].PostID.Int64)
	require.Equal(t, posts[2], updated[1].PostID.Int64)
	require.Empty(t, next)
	require.NoError(t, module.Posts.DeletePost(ctx, posts[1], alice.SpaceID))
	remaining, next, err := module.Notifications.List(ctx, alice.SpaceID, cursor, 2)
	require.NoError(t, err)
	require.Len(t, remaining, 1)
	require.Equal(t, posts[2], remaining[0].PostID.Int64)
	require.Empty(t, next)
}

func TestNotificationsLargeLikeGroup(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := t.Context()
	alice, bob := notificationTestSpaces(t, module)
	postID, err := testCreatePost(ctx, module, alice.OwnerID, alice.SpaceID, "key", nil, 1, nil)
	require.NoError(t, err)
	_, err = module.Pokes.Create(ctx, bob.SpaceID, alice.SpaceID, "older")
	require.NoError(t, err)
	_, err = module.Spaces.DB.ExecContext(ctx, `
		INSERT INTO spaces (space_id, owner_id, space_slug, root_wrapped_space_key, public_key, encrypted_secret_key)
		SELECT 'large-group-' || i, $1, 'large_group_' || i, '\x00'::bytea, '\x00'::bytea, '\x00'::bytea
		FROM generate_series(1, 2000) i
	`, bob.OwnerID)
	require.NoError(t, err)
	_, err = module.Friends.DB.ExecContext(ctx, `
		INSERT INTO space_friend_shares (space_id, friend_space_id, friend_sealed_space_key, key_version)
		SELECT $1, 'large-group-' || i, '\x00'::bytea, 1 FROM generate_series(1, 2000) i
	`, alice.SpaceID)
	require.NoError(t, err)
	_, err = module.Posts.DB.ExecContext(ctx, `
		INSERT INTO space_post_likes (like_id, post_id, actor_space_id)
		SELECT 'large-like-' || i, $1, 'large-group-' || i FROM generate_series(1, 2000) i
	`, postID)
	require.NoError(t, err)
	_, err = module.Notifications.DB.ExecContext(ctx, `
		INSERT INTO space_notifications (notification_id, recipient_space_id, actor_space_id, kind, post_like_id, read_at)
		SELECT 'large-notification-' || i, $1, 'large-group-' || i, 'post_like', 'large-like-' || i,
			CASE WHEN i = 1 THEN NULL ELSE now_utc_micro_seconds() END
		FROM generate_series(1, 2000) i
	`, alice.SpaceID)
	require.NoError(t, err)
	page, cursor, err := module.Notifications.List(ctx, alice.SpaceID, "", 1)
	require.NoError(t, err)
	require.Len(t, page, 1)
	require.Equal(t, postID, page[0].PostID.Int64)
	require.Equal(t, int64(2000), page[0].ActorCount)
	require.Len(t, page[0].NotificationIDs, 2000)
	require.Len(t, page[0].Actors, 2)
	require.True(t, page[0].Unread)
	require.NotEmpty(t, cursor)
	require.NoError(t, module.Notifications.MarkRead(ctx, alice.SpaceID, page[0].NotificationIDs))
	page, _, err = module.Notifications.List(ctx, alice.SpaceID, "", 1)
	require.NoError(t, err)
	require.False(t, page[0].Unread)
	older, cursor, err := module.Notifications.List(ctx, alice.SpaceID, cursor, 1)
	require.NoError(t, err)
	require.Len(t, older, 1)
	require.Equal(t, "poke", older[0].Kind)
	require.Len(t, older[0].NotificationIDs, 1)
	require.Empty(t, cursor)
}

func TestNotificationReadAfterLatestLikeRemoved(t *testing.T) {
	for _, newLike := range []bool{false, true} {
		t.Run(fmt.Sprintf("newLike=%t", newLike), func(t *testing.T) {
			module := newSpaceTestModule(t)
			ctx := t.Context()
			alice, bob := notificationTestSpaces(t, module)
			charlieID := insertSpaceUser(t, module, "charlie-notifications@example.com", "public")
			charlie, err := testCreateSpace(ctx, module, charlieID, "charlie_notifications", "root", "public", "secret", "nonce", "profile")
			require.NoError(t, err)
			require.NoError(t, testAddFriend(ctx, module, charlieID, charlie.SpaceID, alice.SpaceID, "share", 1, "share", 1))
			postID, err := testCreatePost(ctx, module, alice.OwnerID, alice.SpaceID, "key", nil, 1, nil)
			require.NoError(t, err)
			require.NoError(t, testSetPostLike(ctx, module, postID, bob.SpaceID, true))
			_, err = module.Notifications.DB.ExecContext(ctx, `UPDATE space_notifications SET created_at = 1000`)
			require.NoError(t, err)
			require.NoError(t, testSetPostLike(ctx, module, postID, charlie.SpaceID, true))
			page, _, err := module.Notifications.List(ctx, alice.SpaceID, "", 20)
			require.NoError(t, err)
			require.Len(t, page, 1)
			require.Len(t, page[0].NotificationIDs, 2)
			require.Equal(t, charlie.SpaceID, page[0].Actors[0].SpaceID)
			require.NoError(t, testSetPostLike(ctx, module, postID, charlie.SpaceID, false))
			require.Equal(t, int64(0), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_notifications WHERE notification_id = $1`, page[0].NotificationID))
			if newLike {
				require.NoError(t, testSetPostLike(ctx, module, postID, charlie.SpaceID, true))
			}

			require.NoError(t, module.Notifications.MarkRead(ctx, alice.SpaceID, page[0].NotificationIDs))
			require.NoError(t, module.Notifications.MarkRead(ctx, alice.SpaceID, page[0].NotificationIDs))
			require.Equal(t, int64(0), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_notifications WHERE actor_space_id = $1 AND read_at IS NULL`, bob.SpaceID))
			unread, err := module.Notifications.HasUnread(ctx, alice.SpaceID)
			require.NoError(t, err)
			require.Equal(t, newLike, unread)
			if newLike {
				require.Equal(t, int64(1), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_notifications WHERE read_at IS NULL`))
			}
		})
	}
}

func TestNotificationsMigrationPreservesLikesAndReadState(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := t.Context()
	alice, bob := notificationTestSpaces(t, module)
	up, err := os.ReadFile("migrations/150_space_notifications.up.sql")
	require.NoError(t, err)
	down, err := os.ReadFile("migrations/150_space_notifications.down.sql")
	require.NoError(t, err)
	tx, err := module.Posts.DB.BeginTx(ctx, nil)
	require.NoError(t, err)
	defer tx.Rollback()
	_, err = tx.ExecContext(ctx, string(down))
	require.NoError(t, err)
	for index, timestamp := range []int64{1000, 3000, 5000} {
		var postID int64
		require.NoError(t, tx.QueryRowContext(ctx, `INSERT INTO space_posts (space_id, encrypted_post_key, is_deleted) VALUES ($1, $2, $3) RETURNING post_id`, alice.SpaceID, []byte("key"), index == 2).Scan(&postID))
		_, err = tx.ExecContext(ctx, `INSERT INTO space_messages (message_id, sender_space_id, recipient_space_id, kind, reply_post_id, created_at) VALUES ($1, $2, $3, 'post_like', $4, $5)`, []string{"read-like", "unread-like", "deleted-post-like"}[index], bob.SpaceID, alice.SpaceID, postID, timestamp)
		require.NoError(t, err)
	}
	_, err = tx.ExecContext(ctx, `UPDATE space_notification_read_markers SET read_at = 2000 WHERE viewer_space_id = $1 AND friend_space_id = $2`, alice.SpaceID, bob.SpaceID)
	require.NoError(t, err)
	_, err = tx.ExecContext(ctx, string(up))
	require.NoError(t, err)
	var readAt sql.NullInt64
	require.NoError(t, tx.QueryRowContext(ctx, `SELECT read_at FROM space_notifications WHERE post_like_id = 'read-like'`).Scan(&readAt))
	require.True(t, readAt.Valid)
	require.Equal(t, int64(2000), readAt.Int64)
	require.NoError(t, tx.QueryRowContext(ctx, `SELECT read_at FROM space_notifications WHERE post_like_id = 'unread-like'`).Scan(&readAt))
	require.False(t, readAt.Valid)
	var count int
	require.NoError(t, tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM space_post_likes`).Scan(&count))
	require.Equal(t, 2, count)
	require.NoError(t, tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM space_messages WHERE kind = 'post_like'`).Scan(&count))
	require.Zero(t, count)
	_, err = tx.ExecContext(ctx, string(down))
	require.NoError(t, err)
	require.NoError(t, tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM space_messages WHERE kind = 'post_like'`).Scan(&count))
	require.Equal(t, 2, count)
}
