package repo

import (
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/space/models"
	"github.com/lib/pq"
	"github.com/stretchr/testify/require"
)

func TestCommentCreationRetriesPreserveTheOriginal(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := t.Context()
	owner, friend := notificationTestSpaces(t, module)
	postID, err := testCreatePost(ctx, module, owner.OwnerID, owner.SpaceID, "post-key", nil, 1, nil)
	require.NoError(t, err)
	otherPostID, err := testCreatePost(ctx, module, owner.OwnerID, owner.SpaceID, "other-key", nil, 1, nil)
	require.NoError(t, err)
	require.NoError(t, module.Comments.Create(ctx, owner.SpaceID, postID, models.CreateCommentRequest{CommentID: "parent"}, []byte("parent")))
	request := models.CreateCommentRequest{CommentID: "retry", ReplyToID: "parent"}
	created, err := module.Comments.CreateWithCreated(ctx, friend.SpaceID, postID, request, []byte("original"))
	require.NoError(t, err)
	require.True(t, created)
	created, err = module.Comments.CreateWithCreated(ctx, friend.SpaceID, postID, request, []byte("reencrypted"))
	require.NoError(t, err)
	require.False(t, created)
	var cipher []byte
	require.NoError(t, module.Comments.DB.QueryRowContext(ctx, `SELECT cipher FROM space_comments WHERE comment_id = 'retry'`).Scan(&cipher))
	require.Equal(t, []byte("original"), cipher)
	require.EqualValues(t, 1, countSpaceRows(t, module, `SELECT count(*) FROM space_notifications WHERE comment_id = 'retry'`))
	for _, test := range []struct {
		name, actor, replyTo string
		postID               int64
	}{
		{"different-author", owner.SpaceID, "parent", postID},
		{"different-post", friend.SpaceID, "parent", otherPostID},
		{"different-target", friend.SpaceID, "", postID},
	} {
		t.Run(test.name, func(t *testing.T) {
			created, err := module.Comments.CreateWithCreated(ctx, test.actor, test.postID, models.CreateCommentRequest{CommentID: "retry", ReplyToID: test.replyTo}, []byte("other"))
			require.False(t, created)
			var apiError *ente.ApiError
			require.ErrorAs(t, err, &apiError)
			require.Equal(t, http.StatusConflict, apiError.HttpStatusCode)
		})
	}
	require.NoError(t, module.Comments.Delete(ctx, owner.SpaceID, postID, "parent"))
	created, err = module.Comments.CreateWithCreated(ctx, friend.SpaceID, postID, request, []byte("retry-after-deletion"))
	require.NoError(t, err)
	require.False(t, created)
	require.NoError(t, module.Comments.DB.QueryRowContext(ctx, `SELECT cipher FROM space_comments WHERE comment_id = 'retry'`).Scan(&cipher))
	require.Empty(t, cipher)
	require.Zero(t, countSpaceRows(t, module, `SELECT count(*) FROM space_notifications WHERE comment_id = 'retry'`))
}

func TestCommentRecipientWorkScalesWithReplyChainLength(t *testing.T) {
	for _, hidden := range []string{"visible", "deleted-comment", "deleted-author"} {
		t.Run(hidden, func(t *testing.T) {
			module := newSpaceTestModule(t)
			ctx := t.Context()
			owner, friend := notificationTestSpaces(t, module)
			var previousBlocks int64
			for _, length := range []int{128, 512} {
				postID, err := testCreatePost(ctx, module, owner.OwnerID, owner.SpaceID, "post-key", nil, 1, nil)
				require.NoError(t, err)
				_, err = module.Posts.DB.ExecContext(ctx, `INSERT INTO space_comments
                    (comment_id, post_id, author_space_id, parent_id, reply_to_id, cipher)
                    SELECT $1::text || ':' || i, $1::bigint, CASE WHEN i = 1 THEN $2 ELSE $3 END,
                        CASE WHEN i > 1 THEN $1::text || ':1' END,
                        CASE WHEN i > 1 THEN $1::text || ':' || (i - 1) END,
                        CASE WHEN i = 1 AND $5 = 'deleted-comment' THEN NULL ELSE '\x01'::bytea END
                    FROM generate_series(1, $4::int) i`, postID, owner.SpaceID, friend.SpaceID, length, hidden)
				require.NoError(t, err)
				if hidden == "deleted-author" {
					_, err = module.Posts.DB.ExecContext(ctx, `UPDATE users SET encrypted_email = NULL WHERE user_id = $1`, owner.OwnerID)
					require.NoError(t, err)
				}
				_, err = module.Posts.DB.ExecContext(ctx, `ANALYZE space_comments`)
				require.NoError(t, err)
				var recipients pq.StringArray
				require.NoError(t, module.Posts.DB.QueryRowContext(ctx, commentRecipientsSQL, owner.SpaceID, postID, owner.SpaceID).Scan(&recipients))
				if hidden == "visible" {
					require.Equal(t, pq.StringArray{friend.SpaceID}, recipients)
				} else {
					require.Empty(t, recipients)
				}
				var planJSON []byte
				require.NoError(t, module.Posts.DB.QueryRowContext(ctx, `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) `+commentRecipientsSQL, owner.SpaceID, postID, owner.SpaceID).Scan(&planJSON))
				var plans []struct {
					Plan struct {
						Hits  int64 `json:"Shared Hit Blocks"`
						Reads int64 `json:"Shared Read Blocks"`
					}
				}
				require.NoError(t, json.Unmarshal(planJSON, &plans))
				require.Len(t, plans, 1)
				blocks := plans[0].Plan.Hits + plans[0].Plan.Reads
				t.Logf("%d comments: %d buffer accesses", length, blocks)
				if previousBlocks > 0 {
					require.Less(t, blocks, previousBlocks*8)
				}
				previousBlocks = blocks
				_, err = module.Posts.DB.ExecContext(ctx, `UPDATE users SET encrypted_email = '\x00'::bytea WHERE user_id = $1`, owner.OwnerID)
				require.NoError(t, err)
			}
		})
	}
}

func TestPostCommentCountWorkScalesWithReplyChainLength(t *testing.T) {
	for _, hidden := range []bool{false, true} {
		name := "visible"
		if hidden {
			name = "hidden-author"
		}
		t.Run(name, func(t *testing.T) {
			module := newSpaceTestModule(t)
			ctx := t.Context()
			owner, friend := notificationTestSpaces(t, module)
			if hidden {
				_, err := module.Posts.DB.ExecContext(ctx, `UPDATE users SET encrypted_email = NULL WHERE user_id = $1`, friend.OwnerID)
				require.NoError(t, err)
			}
			var previousBlocks int64
			for _, length := range []int{128, 512} {
				postID, err := testCreatePost(ctx, module, owner.OwnerID, owner.SpaceID, "post-key", nil, 1, nil)
				require.NoError(t, err)
				_, err = module.Posts.DB.ExecContext(ctx, `INSERT INTO space_comments
				    (comment_id, post_id, author_space_id, parent_id, reply_to_id, cipher)
				    SELECT $1::text || ':' || i, $1::bigint, CASE WHEN i = 1 THEN $4 ELSE $2 END,
				        CASE WHEN i > 1 THEN $1::text || ':1' END,
				        CASE WHEN i > 1 THEN $1::text || ':' || (i - 1) END,
				        '\x01'::bytea
				    FROM generate_series(1, $3::int) i`, postID, owner.SpaceID, length, friend.SpaceID)
				require.NoError(t, err)
				_, err = module.Posts.DB.ExecContext(ctx, `ANALYZE space_comments`)
				require.NoError(t, err)
				post, err := module.Posts.GetPost(ctx, postID, owner.SpaceID)
				require.NoError(t, err)
				if hidden {
					require.Zero(t, post.CommentCount)
				} else {
					require.EqualValues(t, length, post.CommentCount)
				}
				var planJSON []byte
				err = module.Posts.DB.QueryRowContext(ctx, `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) `+
					postRecordSelectSQL("FALSE", "$2")+`
				    FROM space_posts p JOIN spaces w ON w.space_id = p.space_id
				    `+spaceActorAvatarJoin("w", "w_avatar")+`
				    WHERE p.post_id = $1`, postID, owner.SpaceID).Scan(&planJSON)
				require.NoError(t, err)
				var plans []struct {
					Plan struct {
						Hits  int64 `json:"Shared Hit Blocks"`
						Reads int64 `json:"Shared Read Blocks"`
					}
				}
				require.NoError(t, json.Unmarshal(planJSON, &plans))
				require.Len(t, plans, 1)
				blocks := plans[0].Plan.Hits + plans[0].Plan.Reads
				t.Logf("%d comments: %d buffer accesses", length, blocks)
				if previousBlocks > 0 {
					require.Less(t, blocks, previousBlocks*8)
				}
				previousBlocks = blocks
			}
		})
	}
}

func TestDiscussionParentDeletionRemovesWholeThread(t *testing.T) {
	for _, deleteAsOwner := range []bool{false, true} {
		name := "author"
		if deleteAsOwner {
			name = "post-owner"
		}
		t.Run(name, func(t *testing.T) {
			module := newSpaceTestModule(t)
			ctx := t.Context()
			owner, friend := notificationTestSpaces(t, module)
			postID, err := testCreatePost(ctx, module, owner.OwnerID, owner.SpaceID, "post-key", nil, 1, nil)
			require.NoError(t, err)
			for _, item := range []struct{ id, actor, replyTo string }{
				{"parent", friend.SpaceID, ""},
				{"reply", owner.SpaceID, "parent"},
				{"reply-to-reply", friend.SpaceID, "reply"},
				{"separate", owner.SpaceID, ""},
			} {
				require.NoError(t, module.Comments.Create(ctx, item.actor, postID, models.CreateCommentRequest{CommentID: item.id, ReplyToID: item.replyTo}, []byte(item.id)))
			}
			for _, id := range []string{"parent", "reply", "reply-to-reply", "separate"} {
				_, err := module.Comments.React(ctx, owner.SpaceID, postID, id, []byte("heart"), "")
				require.NoError(t, err)
			}
			actor := friend.SpaceID
			if deleteAsOwner {
				actor = owner.SpaceID
			}
			require.NoError(t, module.Comments.Delete(ctx, actor, postID, "parent"))
			items, _, err := module.Comments.List(ctx, owner.SpaceID, postID, "")
			require.NoError(t, err)
			for _, item := range items {
				if item.ID == "separate" {
					require.Equal(t, []byte("separate"), item.Cipher)
					require.Len(t, item.Reactions, 1)
				} else {
					require.Empty(t, item.Cipher)
					require.Empty(t, item.Reactions)
					require.Empty(t, item.UnreadNotificationIDs)
				}
			}
			require.EqualValues(t, 0, countSpaceRows(t, module, `SELECT count(*) FROM space_notifications WHERE comment_id IN ('parent', 'reply', 'reply-to-reply')`))
			require.EqualValues(t, 0, countSpaceRows(t, module, `SELECT count(*) FROM space_comment_reactions WHERE comment_id IN ('parent', 'reply', 'reply-to-reply')`))
			require.ErrorIs(t, module.Comments.Create(ctx, owner.SpaceID, postID, models.CreateCommentRequest{CommentID: "late-reply", ReplyToID: "reply"}, []byte("late")), sql.ErrNoRows)
			_, err = module.Comments.React(ctx, owner.SpaceID, postID, "reply", []byte("heart"), "")
			require.ErrorIs(t, err, sql.ErrNoRows)
		})
	}
}

func TestDiscussionReplyDeletionRemovesDescendantsAndPreservesSiblings(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := t.Context()
	owner, friend := notificationTestSpaces(t, module)
	postID, err := testCreatePost(ctx, module, owner.OwnerID, owner.SpaceID, "post-key", nil, 1, nil)
	require.NoError(t, err)
	for _, item := range []struct{ id, actor, replyTo string }{
		{"parent", owner.SpaceID, ""},
		{"reply", friend.SpaceID, "parent"},
		{"reply-to-reply", owner.SpaceID, "reply"},
		{"deep-reply", friend.SpaceID, "reply-to-reply"},
		{"sibling", friend.SpaceID, "parent"},
		{"sibling-child", owner.SpaceID, "sibling"},
	} {
		require.NoError(t, module.Comments.Create(ctx, item.actor, postID, models.CreateCommentRequest{CommentID: item.id, ReplyToID: item.replyTo}, []byte(item.id)))
	}
	for _, id := range []string{"reply", "reply-to-reply", "deep-reply", "sibling", "sibling-child"} {
		_, err = module.Comments.React(ctx, owner.SpaceID, postID, id, []byte("heart"), "")
		require.NoError(t, err)
	}
	require.ErrorIs(t, module.Comments.Delete(ctx, friend.SpaceID, postID, "parent"), ente.ErrPermissionDenied)
	require.NoError(t, module.Comments.Delete(ctx, friend.SpaceID, postID, "reply"))
	items, _, err := module.Comments.List(ctx, owner.SpaceID, postID, "")
	require.NoError(t, err)
	require.Len(t, items, 6)
	for _, item := range items {
		if item.ID == "reply" || item.ID == "reply-to-reply" || item.ID == "deep-reply" {
			require.Empty(t, item.Cipher)
			require.Empty(t, item.Reactions)
			require.Empty(t, item.UnreadNotificationIDs)
		} else {
			require.Equal(t, []byte(item.ID), item.Cipher)
			if item.ID != "parent" {
				require.Equal(t, "parent", item.ParentID)
				require.Len(t, item.Reactions, 1)
			}
		}
	}
	require.EqualValues(t, 0, countSpaceRows(t, module, `SELECT count(*) FROM space_notifications WHERE comment_id IN ('reply', 'reply-to-reply', 'deep-reply')`))
	require.EqualValues(t, 0, countSpaceRows(t, module, `SELECT count(*) FROM space_comment_reactions WHERE comment_id IN ('reply', 'reply-to-reply', 'deep-reply')`))
	require.Greater(t, countSpaceRows(t, module, `SELECT count(*) FROM space_notifications WHERE comment_id IN ('sibling', 'sibling-child')`), int64(0))
	post, err := module.Posts.GetPost(ctx, postID, owner.SpaceID)
	require.NoError(t, err)
	require.EqualValues(t, 3, post.CommentCount)
	require.ErrorIs(t, module.Comments.Create(ctx, friend.SpaceID, postID, models.CreateCommentRequest{CommentID: "deleted-target", ReplyToID: "deep-reply"}, []byte("new")), sql.ErrNoRows)
	require.NoError(t, module.Comments.Create(ctx, friend.SpaceID, postID, models.CreateCommentRequest{CommentID: "new-reply", ReplyToID: "sibling-child"}, []byte("new")))
}

func TestDiscussionAudienceAndAccess(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := t.Context()
	owner, friend := notificationTestSpaces(t, module)
	outsiderID := insertSpaceUser(t, module, "comment-outsider@example.com", "outsider")
	outsider, err := testCreateSpace(ctx, module, outsiderID, "comment_outsider", "root", "public", "secret", "nonce", "private")
	require.NoError(t, err)
	postID, err := testCreatePost(ctx, module, owner.OwnerID, owner.SpaceID, "post-key", nil, 1, nil)
	require.NoError(t, err)
	_, _, err = module.Comments.List(ctx, outsider.SpaceID, postID, "")
	require.ErrorIs(t, err, sql.ErrNoRows)
	require.ErrorIs(t, module.Comments.Create(ctx, outsider.SpaceID, postID, models.CreateCommentRequest{CommentID: "outsider"}, []byte("cipher")), sql.ErrNoRows)
	require.NoError(t, module.Comments.Create(ctx, friend.SpaceID, postID, models.CreateCommentRequest{CommentID: "root"}, []byte("cipher")))
	_, _, _, err = module.Friends.CreateFriendRequest(ctx, owner.OwnerID, owner.SpaceID, outsider.SpaceID, []byte("share"), 1)
	require.NoError(t, err)
	_, _, err = module.Comments.List(ctx, outsider.SpaceID, postID, "")
	require.ErrorIs(t, err, sql.ErrNoRows)
	require.NoError(t, module.Friends.DeleteFriendship(ctx, owner.SpaceID, friend.SpaceID))
	_, _, err = module.Comments.List(ctx, friend.SpaceID, postID, "")
	require.ErrorIs(t, err, sql.ErrNoRows)
	require.ErrorIs(t, module.Comments.Create(ctx, friend.SpaceID, postID, models.CreateCommentRequest{CommentID: "removed"}, []byte("cipher")), sql.ErrNoRows)
	_, err = module.Comments.React(ctx, friend.SpaceID, postID, "root", []byte("reaction"), "")
	require.ErrorIs(t, err, sql.ErrNoRows)
	require.ErrorIs(t, module.Comments.Delete(ctx, friend.SpaceID, postID, "root"), sql.ErrNoRows)
	require.NoError(t, module.Comments.Create(ctx, owner.SpaceID, postID, models.CreateCommentRequest{CommentID: "after-removal"}, []byte("cipher")))
	items, _, err := module.Comments.List(ctx, owner.SpaceID, postID, "")
	require.NoError(t, err)
	require.Len(t, items, 2)
	require.True(t, items[0].CanDelete)
	require.True(t, items[1].CanDelete)
}

func TestCommentNotificationsGroupUniquePeopleByPost(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := t.Context()
	owner, friend := notificationTestSpaces(t, module)
	otherID := insertSpaceUser(t, module, "group-commenter@example.com", "other-public")
	other, err := testCreateSpace(ctx, module, otherID, "group_commenter", "root", "public", "secret", "nonce", "profile")
	require.NoError(t, err)
	require.NoError(t, testAddFriend(ctx, module, otherID, other.SpaceID, owner.SpaceID, "owner-share", 1, "other-share", 1))
	postID, err := testCreatePost(ctx, module, owner.OwnerID, owner.SpaceID, "post-key", nil, 1, nil)
	require.NoError(t, err)
	otherPostID, err := testCreatePost(ctx, module, owner.OwnerID, owner.SpaceID, "other-key", nil, 1, nil)
	require.NoError(t, err)
	require.NoError(t, module.Comments.Create(ctx, friend.SpaceID, otherPostID, models.CreateCommentRequest{CommentID: "older-post"}, []byte("cipher")))
	for _, item := range []struct{ id, actor string }{{"first", friend.SpaceID}, {"second", other.SpaceID}, {"latest", friend.SpaceID}} {
		require.NoError(t, module.Comments.Create(ctx, item.actor, postID, models.CreateCommentRequest{CommentID: item.id}, []byte("cipher")))
	}
	page, cursor, err := module.Notifications.List(ctx, owner.SpaceID, "", 1)
	require.NoError(t, err)
	require.Len(t, page, 1)
	require.Equal(t, "latest", page[0].CommentID)
	require.Equal(t, int64(2), page[0].ActorCount)
	require.Len(t, page[0].Actors, 2)
	require.Equal(t, friend.SpaceID, page[0].Actors[0].SpaceID)
	require.Equal(t, other.SpaceID, page[0].Actors[1].SpaceID)
	require.Len(t, page[0].NotificationIDs, 3)
	require.True(t, page[0].Unread)
	older, _, err := module.Notifications.List(ctx, owner.SpaceID, cursor, 1)
	require.NoError(t, err)
	require.Len(t, older, 1)
	require.Equal(t, "older-post", older[0].CommentID)
	require.NoError(t, module.Notifications.MarkRead(ctx, owner.SpaceID, page[0].NotificationIDs[:1]))
	page, _, err = module.Notifications.List(ctx, owner.SpaceID, "", 1)
	require.NoError(t, err)
	require.True(t, page[0].Unread)
	require.NoError(t, module.Notifications.MarkRead(ctx, owner.SpaceID, page[0].NotificationIDs))
	page, _, err = module.Notifications.List(ctx, owner.SpaceID, "", 1)
	require.NoError(t, err)
	require.False(t, page[0].Unread)
	require.NoError(t, module.Comments.Create(ctx, other.SpaceID, postID, models.CreateCommentRequest{CommentID: "newest"}, []byte("cipher")))
	page, _, err = module.Notifications.List(ctx, owner.SpaceID, "", 1)
	require.NoError(t, err)
	require.Equal(t, "newest", page[0].CommentID)
	require.True(t, page[0].Unread)
	require.Equal(t, int64(2), page[0].ActorCount)
	require.Len(t, page[0].NotificationIDs, 4)
	require.NoError(t, module.Comments.Delete(ctx, other.SpaceID, postID, "newest"))
	page, _, err = module.Notifications.List(ctx, owner.SpaceID, "", 1)
	require.NoError(t, err)
	require.Equal(t, "latest", page[0].CommentID)
	require.False(t, page[0].Unread)
	require.NoError(t, module.Friends.DeleteFriendship(ctx, owner.SpaceID, other.SpaceID))
	page, _, err = module.Notifications.List(ctx, owner.SpaceID, "", 1)
	require.NoError(t, err)
	require.Equal(t, int64(1), page[0].ActorCount)
	require.Len(t, page[0].Actors, 1)
	require.Len(t, page[0].NotificationIDs, 2)
}

func TestCommentActivityNotificationsGroupByExactTarget(t *testing.T) {
	for _, kind := range []string{"comment_reply", "comment_reaction"} {
		t.Run(kind, func(t *testing.T) {
			module := newSpaceTestModule(t)
			ctx := t.Context()
			owner, friend := notificationTestSpaces(t, module)
			actors := []*SpaceRecord{friend}
			for _, name := range []string{"second", "third"} {
				id := insertSpaceUser(t, module, name+"-group@example.com", name+"-public")
				actor, err := testCreateSpace(ctx, module, id, name+"_group", "root", "public", "secret", "nonce", "profile")
				require.NoError(t, err)
				require.NoError(t, testAddFriend(ctx, module, id, actor.SpaceID, owner.SpaceID, "owner-share", 1, "actor-share", 1))
				actors = append(actors, actor)
			}
			postID, err := testCreatePost(ctx, module, owner.OwnerID, owner.SpaceID, "post-key", nil, 1, nil)
			require.NoError(t, err)
			for _, item := range []struct{ id, replyTo string }{{"root", ""}, {"nested", "root"}, {"separate", ""}} {
				require.NoError(t, module.Comments.Create(ctx, owner.SpaceID, postID, models.CreateCommentRequest{CommentID: item.id, ReplyToID: item.replyTo}, []byte("cipher")))
			}
			addActivity := func(id, actor, target string) string {
				if kind == "comment_reaction" {
					_, err := module.Comments.React(ctx, actor, postID, target, []byte(id), "")
					require.NoError(t, err)
					return target
				}
				require.NoError(t, module.Comments.Create(ctx, actor, postID, models.CreateCommentRequest{CommentID: id, ReplyToID: target}, []byte("cipher")))
				return id
			}
			separateID := addActivity("separate-friend", friend.SpaceID, "separate")
			addActivity("nested-friend", friend.SpaceID, "nested")
			nestedID := addActivity("nested-other", actors[1].SpaceID, "nested")
			addActivity("root-first", friend.SpaceID, "root")
			addActivity("root-second", actors[1].SpaceID, "root")
			latestID := addActivity("root-latest", friend.SpaceID, "root")
			page, cursor, err := module.Notifications.List(ctx, owner.SpaceID, "", 1)
			require.NoError(t, err)
			require.Len(t, page, 1)
			group := page[0]
			require.Equal(t, kind, group.Kind)
			require.Equal(t, latestID, group.CommentID)
			if kind == "comment_reply" {
				require.Equal(t, "root", group.ReplyToID)
				require.Len(t, group.NotificationIDs, 3)
				require.Equal(t, friend.SpaceID, group.Actors[0].SpaceID)
			} else {
				require.Len(t, group.NotificationIDs, 2)
				require.Equal(t, actors[1].SpaceID, group.Actors[0].SpaceID)
			}
			require.EqualValues(t, 2, group.ActorCount)
			require.Len(t, group.Actors, 2)
			require.True(t, group.Unread)
			require.NotEmpty(t, cursor)
			older, nextCursor, err := module.Notifications.List(ctx, owner.SpaceID, cursor, 1)
			require.NoError(t, err)
			require.Len(t, older, 1)
			require.Equal(t, nestedID, older[0].CommentID)
			require.EqualValues(t, 2, older[0].ActorCount)
			if kind == "comment_reply" {
				require.Equal(t, "nested", older[0].ReplyToID)
			}
			oldest, _, err := module.Notifications.List(ctx, owner.SpaceID, nextCursor, 1)
			require.NoError(t, err)
			require.Len(t, oldest, 1)
			require.Equal(t, separateID, oldest[0].CommentID)
			require.NoError(t, module.Notifications.MarkRead(ctx, owner.SpaceID, group.NotificationIDs[:1]))
			page, _, err = module.Notifications.List(ctx, owner.SpaceID, "", 1)
			require.NoError(t, err)
			require.True(t, page[0].Unread)
			require.NoError(t, module.Notifications.MarkRead(ctx, owner.SpaceID, group.NotificationIDs))
			page, _, err = module.Notifications.List(ctx, owner.SpaceID, "", 2)
			require.NoError(t, err)
			require.False(t, page[0].Unread)
			require.True(t, page[1].Unread)
			newestID := addActivity("root-newest", actors[2].SpaceID, "root")
			page, _, err = module.Notifications.List(ctx, owner.SpaceID, "", 1)
			require.NoError(t, err)
			require.Equal(t, newestID, page[0].CommentID)
			require.EqualValues(t, 3, page[0].ActorCount)
			require.Len(t, page[0].Actors, 2)
			require.Equal(t, actors[2].SpaceID, page[0].Actors[0].SpaceID)
			require.Len(t, page[0].NotificationIDs, len(group.NotificationIDs)+1)
			require.True(t, page[0].Unread)
			if kind == "comment_reaction" {
				_, err = module.Comments.React(ctx, actors[2].SpaceID, postID, "root", nil, "")
				require.NoError(t, err)
			} else {
				require.NoError(t, module.Comments.Delete(ctx, actors[2].SpaceID, postID, newestID))
			}
			page, _, err = module.Notifications.List(ctx, owner.SpaceID, "", 1)
			require.NoError(t, err)
			require.Equal(t, latestID, page[0].CommentID)
			require.EqualValues(t, 2, page[0].ActorCount)
			require.False(t, page[0].Unread)
			require.NoError(t, module.Comments.Delete(ctx, owner.SpaceID, postID, "root"))
			page, _, err = module.Notifications.List(ctx, owner.SpaceID, "", 50)
			require.NoError(t, err)
			var remaining []string
			for _, item := range page {
				if item.Kind == kind {
					remaining = append(remaining, item.CommentID)
				}
			}
			require.Equal(t, []string{separateID}, remaining)
		})
	}
}

func TestNonFriendCommentNotificationsKeepOnlyDirectActivity(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := t.Context()
	owner, viewer := notificationTestSpaces(t, module)
	actorID := insertSpaceUser(t, module, "nonfriend-commenter@example.com", "actor-public")
	actor, err := testCreateSpace(ctx, module, actorID, "nonfriend_commenter", "root", "public", "secret", "nonce", "profile")
	require.NoError(t, err)
	require.NoError(t, testAddFriend(ctx, module, actorID, actor.SpaceID, owner.SpaceID, "owner-share", 1, "actor-share", 1))
	postID, err := testCreatePost(ctx, module, owner.OwnerID, owner.SpaceID, "post-key", nil, 1, nil)
	require.NoError(t, err)
	_, err = module.Notifications.DB.ExecContext(ctx, `UPDATE space_notifications SET read_at = 1 WHERE recipient_space_id = $1`, viewer.SpaceID)
	require.NoError(t, err)
	require.NoError(t, module.Comments.Create(ctx, viewer.SpaceID, postID, models.CreateCommentRequest{CommentID: "root"}, []byte("cipher")))
	require.NoError(t, module.Comments.Create(ctx, actor.SpaceID, postID, models.CreateCommentRequest{CommentID: "ambient"}, []byte("cipher")))
	recipients, _, err := module.Comments.NotificationRecipients(ctx, actor.SpaceID, postID, "ambient", false)
	require.NoError(t, err)
	require.Len(t, recipients, 1)
	require.Equal(t, owner.OwnerID, recipients[0].UserID)
	_, err = module.Notifications.DB.ExecContext(ctx, `INSERT INTO space_notifications (notification_id, recipient_space_id, actor_space_id, kind, comment_id) VALUES ('legacy-ambient', $1, $2, 'comment', 'ambient')`, viewer.SpaceID, actor.SpaceID)
	require.NoError(t, err)
	unread, err := module.Notifications.HasUnread(ctx, viewer.SpaceID)
	require.NoError(t, err)
	require.False(t, unread)
	require.NoError(t, module.Comments.Create(ctx, actor.SpaceID, postID, models.CreateCommentRequest{CommentID: "direct-reply", ReplyToID: "root"}, []byte("cipher")))
	_, err = module.Comments.React(ctx, actor.SpaceID, postID, "root", []byte("heart"), "")
	require.NoError(t, err)
	page, _, err := module.Notifications.List(ctx, viewer.SpaceID, "", 50)
	require.NoError(t, err)
	var directIDs []string
	var kinds []string
	for _, item := range page {
		if item.CommentID != "" {
			kinds = append(kinds, item.Kind)
			directIDs = append(directIDs, item.NotificationIDs...)
			require.Empty(t, item.Actors[0].EncryptedProfile)
		}
	}
	require.ElementsMatch(t, []string{"comment_reply", "comment_reaction"}, kinds)
	require.NoError(t, module.Notifications.MarkRead(ctx, viewer.SpaceID, append(directIDs, "legacy-ambient")))
	unread, err = module.Notifications.HasUnread(ctx, viewer.SpaceID)
	require.NoError(t, err)
	require.False(t, unread)
	var readAt sql.NullInt64
	require.NoError(t, module.Notifications.DB.QueryRowContext(ctx, `SELECT read_at FROM space_notifications WHERE notification_id = 'legacy-ambient'`).Scan(&readAt))
	require.False(t, readAt.Valid)
}

func TestDiscussionAccessRecheckedAfterConcurrentRemoval(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := t.Context()
	owner, friend := notificationTestSpaces(t, module)
	postID, err := testCreatePost(ctx, module, owner.OwnerID, owner.SpaceID, "post-key", nil, 1, nil)
	require.NoError(t, err)
	tx, err := module.Comments.DB.BeginTx(ctx, nil)
	require.NoError(t, err)
	defer tx.Rollback()
	var backend int
	require.NoError(t, tx.QueryRowContext(ctx, `SELECT pg_backend_pid()`).Scan(&backend))
	_, err = tx.ExecContext(ctx, `DELETE FROM space_friend_shares WHERE space_id = $1 AND friend_space_id = $2`, owner.SpaceID, friend.SpaceID)
	require.NoError(t, err)
	result := make(chan error, 1)
	go func() {
		_, _, err := module.Comments.List(ctx, friend.SpaceID, postID, "")
		result <- err
	}()
	require.Eventually(t, func() bool {
		var blocked bool
		err := module.Comments.DB.QueryRowContext(ctx, `SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE $1 = ANY(pg_blocking_pids(pid)))`, backend).Scan(&blocked)
		return err == nil && blocked
	}, 3*time.Second, 10*time.Millisecond)
	require.NoError(t, tx.Commit())
	require.ErrorIs(t, <-result, sql.ErrNoRows)
}

func TestDiscussionReadsDoNotBlockOtherReadsOrPosts(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := t.Context()
	owner, friend := notificationTestSpaces(t, module)
	postID, err := testCreatePost(ctx, module, owner.OwnerID, owner.SpaceID, "post-key", nil, 1, nil)
	require.NoError(t, err)
	otherPostID, err := testCreatePost(ctx, module, owner.OwnerID, owner.SpaceID, "other-key", nil, 1, nil)
	require.NoError(t, err)
	require.NoError(t, module.Comments.Create(ctx, friend.SpaceID, postID, models.CreateCommentRequest{CommentID: "root"}, []byte("cipher")))
	tx, err := module.Comments.DB.BeginTx(ctx, nil)
	require.NoError(t, err)
	defer tx.Rollback()
	_, err = discussionPostTx(ctx, tx, friend.SpaceID, postID, false)
	require.NoError(t, err)

	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	items, _, err := module.Comments.List(ctx, owner.SpaceID, postID, "")
	require.NoError(t, err)
	require.Len(t, items, 1)
	_, _, err = module.Comments.List(ctx, friend.SpaceID, otherPostID, "")
	require.NoError(t, err)
	require.NoError(t, module.Comments.Create(ctx, friend.SpaceID, otherPostID, models.CreateCommentRequest{CommentID: "other"}, []byte("cipher")))
}

func TestDiscussionAcknowledgementOnlyReadsVisibleCommentNotifications(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := t.Context()
	owner, friend := notificationTestSpaces(t, module)
	postID, err := testCreatePost(ctx, module, owner.OwnerID, owner.SpaceID, "post-key", nil, 1, nil)
	require.NoError(t, err)
	otherPostID, err := testCreatePost(ctx, module, owner.OwnerID, owner.SpaceID, "other-key", nil, 1, nil)
	require.NoError(t, err)
	require.NoError(t, module.Comments.Create(ctx, friend.SpaceID, postID, models.CreateCommentRequest{CommentID: "visible"}, []byte("visible")))
	require.NoError(t, module.Comments.Create(ctx, owner.SpaceID, postID, models.CreateCommentRequest{CommentID: "reply", ReplyToID: "visible"}, []byte("reply")))
	require.NoError(t, module.Comments.Create(ctx, friend.SpaceID, postID, models.CreateCommentRequest{CommentID: "offscreen"}, []byte("offscreen")))
	require.NoError(t, module.Comments.Create(ctx, friend.SpaceID, otherPostID, models.CreateCommentRequest{CommentID: "other-post"}, []byte("other-post")))
	items, _, err := module.Comments.List(ctx, owner.SpaceID, postID, "")
	require.NoError(t, err)
	require.Len(t, items[0].UnreadNotificationIDs, 1)
	require.Empty(t, items[1].UnreadNotificationIDs)
	require.Len(t, items[2].UnreadNotificationIDs, 1)
	friendItems, _, err := module.Comments.List(ctx, friend.SpaceID, postID, "")
	require.NoError(t, err)
	require.Empty(t, friendItems[0].UnreadNotificationIDs)
	require.Len(t, friendItems[1].UnreadNotificationIDs, 1)
	_, err = module.Comments.React(ctx, friend.SpaceID, postID, "reply", []byte("heart"), "")
	require.NoError(t, err)
	require.NoError(t, module.Notifications.MarkRead(ctx, owner.SpaceID, append(items[0].UnreadNotificationIDs, friendItems[1].UnreadNotificationIDs...)))
	updated, _, err := module.Comments.List(ctx, owner.SpaceID, postID, "")
	require.NoError(t, err)
	require.Empty(t, updated[0].UnreadNotificationIDs)
	require.Len(t, updated[1].UnreadNotificationIDs, 1)
	require.Equal(t, items[2].UnreadNotificationIDs, updated[2].UnreadNotificationIDs)
	other, _, err := module.Comments.List(ctx, owner.SpaceID, otherPostID, "")
	require.NoError(t, err)
	require.Len(t, other[0].UnreadNotificationIDs, 1)
	friendUpdated, _, err := module.Comments.List(ctx, friend.SpaceID, postID, "")
	require.NoError(t, err)
	require.Equal(t, friendItems[1].UnreadNotificationIDs, friendUpdated[1].UnreadNotificationIDs)
	require.NoError(t, module.Friends.DeleteFriendship(ctx, owner.SpaceID, friend.SpaceID))
	updated, _, err = module.Comments.List(ctx, owner.SpaceID, postID, "")
	require.NoError(t, err)
	for _, item := range updated {
		require.Empty(t, item.UnreadNotificationIDs)
	}
}

func TestDiscussionReactionsStayWithTheirCommentAndPage(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := t.Context()
	owner, friend := notificationTestSpaces(t, module)
	postID, err := testCreatePost(ctx, module, owner.OwnerID, owner.SpaceID, "post-key", nil, 1, nil)
	require.NoError(t, err)
	otherPostID, err := testCreatePost(ctx, module, owner.OwnerID, owner.SpaceID, "other-key", nil, 1, nil)
	require.NoError(t, err)
	_, err = module.Comments.DB.ExecContext(ctx, `INSERT INTO space_comments (comment_id, post_id, author_space_id, cipher, created_at)
        SELECT 'comment-' || lpad(n::text, 3, '0'), $1, $2, '\x00'::bytea, n FROM generate_series(1, 102) n`, postID, owner.SpaceID)
	require.NoError(t, err)
	require.NoError(t, module.Comments.Create(ctx, owner.SpaceID, otherPostID, models.CreateCommentRequest{CommentID: "other-post"}, []byte("other")))
	for _, id := range []string{"comment-001", "comment-002", "comment-100", "comment-101"} {
		_, err := module.Comments.React(ctx, friend.SpaceID, postID, id, []byte(id), "")
		require.NoError(t, err)
	}
	_, err = module.Comments.React(ctx, owner.SpaceID, postID, "comment-001", []byte("owner-reaction"), "")
	require.NoError(t, err)
	_, err = module.Comments.React(ctx, friend.SpaceID, otherPostID, "other-post", []byte("other-reaction"), "")
	require.NoError(t, err)
	_, err = module.Comments.DB.ExecContext(ctx, `UPDATE space_comments SET cipher = NULL WHERE comment_id = 'comment-002'`)
	require.NoError(t, err)
	items, cursor, err := module.Comments.List(ctx, friend.SpaceID, postID, "")
	require.NoError(t, err)
	require.Len(t, items, 100)
	require.NotEmpty(t, cursor)
	require.Len(t, items[0].Reactions, 2)
	require.Empty(t, items[1].Reactions)
	require.Empty(t, items[2].Reactions)
	require.Len(t, items[99].Reactions, 1)
	require.Equal(t, []byte("comment-100"), items[99].Reactions[0].Cipher)
	items, cursor, err = module.Comments.List(ctx, friend.SpaceID, postID, cursor)
	require.NoError(t, err)
	require.Len(t, items, 2)
	require.Empty(t, cursor)
	require.Equal(t, "comment-101", items[0].ID)
	require.Len(t, items[0].Reactions, 1)
	require.Equal(t, []byte("comment-101"), items[0].Reactions[0].Cipher)
	require.Empty(t, items[1].Reactions)
}

func TestDiscussionAccountDeletionHidesAndRemovesBranches(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := t.Context()
	owner, alice := notificationTestSpaces(t, module)
	carolID := insertSpaceUser(t, module, "carol-deletion@example.com", "carol-public")
	carol, err := testCreateSpace(ctx, module, carolID, "carol_deletion", "root", "public", "secret", "nonce", "profile")
	require.NoError(t, err)
	for _, friend := range []*SpaceRecord{owner, alice} {
		require.NoError(t, testAddFriend(ctx, module, carolID, carol.SpaceID, friend.SpaceID, "share", 1, "share", 1))
	}
	postID, err := testCreatePost(ctx, module, owner.OwnerID, owner.SpaceID, "post-key", nil, 1, nil)
	require.NoError(t, err)
	alicePostID, err := testCreatePost(ctx, module, alice.OwnerID, alice.SpaceID, "alice-post-key", nil, 1, nil)
	require.NoError(t, err)
	require.NoError(t, module.Comments.Create(ctx, carol.SpaceID, alicePostID, models.CreateCommentRequest{CommentID: "alice-post-comment"}, []byte("comment")))
	allIDs := []string{}
	for _, item := range []struct{ id, author, reply string }{
		{"owner-root", owner.SpaceID, ""},
		{"alice-reply", alice.SpaceID, "owner-root"},
		{"carol-nested", carol.SpaceID, "alice-reply"},
		{"owner-deep", owner.SpaceID, "carol-nested"},
		{"alice-deep", alice.SpaceID, "owner-deep"},
		{"owner-sibling", owner.SpaceID, "owner-root"},
		{"carol-sibling", carol.SpaceID, "owner-sibling"},
		{"alice-root", alice.SpaceID, ""},
		{"carol-child", carol.SpaceID, "alice-root"},
		{"owner-child", owner.SpaceID, "carol-child"},
		{"separate", carol.SpaceID, ""},
		{"delete-during-recovery", carol.SpaceID, "alice-root"},
	} {
		require.NoError(t, module.Comments.Create(ctx, item.author, postID, models.CreateCommentRequest{CommentID: item.id, ReplyToID: item.reply}, []byte(item.id)))
		allIDs = append(allIDs, item.id)
	}
	for _, item := range []struct{ actor, comment string }{
		{alice.SpaceID, "owner-root"},
		{carol.SpaceID, "owner-root"},
		{owner.SpaceID, "carol-nested"},
		{carol.SpaceID, "alice-root"},
		{owner.SpaceID, "separate"},
		{owner.SpaceID, "alice-post-comment"},
	} {
		targetPostID := postID
		if item.comment == "alice-post-comment" {
			targetPostID = alicePostID
		}
		_, err = module.Comments.React(ctx, item.actor, targetPostID, item.comment, []byte("reaction"), "")
		require.NoError(t, err)
	}
	assertVisible := func(expected []string) {
		t.Helper()
		items, _, err := module.Comments.List(ctx, owner.SpaceID, postID, "")
		require.NoError(t, err)
		visible := []string{}
		for _, item := range items {
			if len(item.Cipher) > 0 {
				visible = append(visible, item.ID)
			} else {
				require.Empty(t, item.Reactions, item.ID)
				require.Empty(t, item.UnreadNotificationIDs, item.ID)
				require.False(t, item.CanDelete, item.ID)
			}
		}
		require.ElementsMatch(t, expected, visible)
		post, err := module.Posts.GetPost(ctx, postID, owner.SpaceID)
		require.NoError(t, err)
		require.EqualValues(t, len(expected), post.CommentCount)
		feed, _, err := module.Posts.ListFeed(ctx, owner.SpaceID, "", 25)
		require.NoError(t, err)
		for _, post := range feed {
			if post.PostID == postID {
				require.EqualValues(t, len(expected), post.CommentCount)
			}
		}
	}
	assertVisible(allIDs)
	hiddenIDs := []string{"alice-reply", "carol-nested", "owner-deep", "alice-deep", "alice-root", "carol-child", "owner-child", "delete-during-recovery"}
	remainingIDs := []string{"owner-root", "owner-sibling", "carol-sibling", "separate"}
	require.NoError(t, module.ResetAccountDeletionAccess(ctx, alice.OwnerID))
	_, err = module.Spaces.DB.ExecContext(ctx, `UPDATE users SET encrypted_email = NULL WHERE user_id = $1`, alice.OwnerID)
	require.NoError(t, err)
	assertVisible(remainingIDs)
	_, _, err = module.Comments.List(ctx, alice.SpaceID, postID, "")
	require.ErrorIs(t, err, sql.ErrNoRows)
	_, _, err = module.Comments.List(ctx, owner.SpaceID, alicePostID, "")
	require.ErrorIs(t, err, sql.ErrNoRows)
	items, _, err := module.Comments.List(ctx, owner.SpaceID, postID, "")
	require.NoError(t, err)
	require.Len(t, items[0].Reactions, 1)
	require.Equal(t, carol.SpaceID, items[0].Reactions[0].Actor.SpaceID)
	for _, id := range hiddenIDs {
		require.ErrorIs(t, module.Comments.Create(ctx, owner.SpaceID, postID, models.CreateCommentRequest{CommentID: "blocked-" + id, ReplyToID: id}, []byte("reply")), sql.ErrNoRows)
		_, err = module.Comments.React(ctx, owner.SpaceID, postID, id, []byte("reaction"), "")
		require.ErrorIs(t, err, sql.ErrNoRows)
		for _, actor := range []*SpaceRecord{owner, alice, carol} {
			for _, reaction := range []bool{false, true} {
				recipients, _, err := module.Comments.NotificationRecipients(ctx, actor.SpaceID, postID, id, reaction)
				require.NoError(t, err)
				require.Empty(t, recipients, id)
			}
		}
	}
	for _, viewer := range []*SpaceRecord{owner, carol} {
		notifications, _, err := module.Notifications.List(ctx, viewer.SpaceID, "", 50)
		require.NoError(t, err)
		for _, notification := range notifications {
			require.NotContains(t, hiddenIDs, notification.CommentID)
			require.NotEqual(t, alicePostID, notification.PostID.Int64)
		}
	}
	require.EqualValues(t, len(allIDs), countSpaceRows(t, module, `SELECT count(*) FROM space_comments WHERE post_id = $1 AND cipher IS NOT NULL`, postID))
	require.NoError(t, module.Comments.Delete(ctx, carol.SpaceID, postID, "delete-during-recovery"))
	require.NoError(t, module.Comments.Create(ctx, owner.SpaceID, postID, models.CreateCommentRequest{CommentID: "new-sibling", ReplyToID: "owner-sibling"}, []byte("new-sibling")))
	remainingIDs = append(remainingIDs, "new-sibling")
	assertVisible(remainingIDs)
	_, err = module.Spaces.DB.ExecContext(ctx, `UPDATE users SET encrypted_email = '\x00'::bytea WHERE user_id = $1`, alice.OwnerID)
	require.NoError(t, err)
	assertVisible(append(allIDs[:len(allIDs)-1], "new-sibling"))
	items, _, err = module.Comments.List(ctx, owner.SpaceID, postID, "")
	require.NoError(t, err)
	require.Len(t, items[0].Reactions, 2)
	recipients, _, err := module.Comments.NotificationRecipients(ctx, owner.SpaceID, postID, "carol-nested", true)
	require.NoError(t, err)
	require.Len(t, recipients, 1)
	require.Equal(t, carolID, recipients[0].UserID)
	_, _, err = module.Comments.List(ctx, owner.SpaceID, alicePostID, "")
	require.NoError(t, err)
	_, err = module.Spaces.DB.ExecContext(ctx, `UPDATE users SET encrypted_email = NULL WHERE user_id = $1`, alice.OwnerID)
	require.NoError(t, err)
	require.NoError(t, module.DeleteUserData(ctx, alice.OwnerID))
	assertVisible(remainingIDs)
	require.EqualValues(t, len(remainingIDs), countSpaceRows(t, module, `SELECT count(*) FROM space_comments WHERE post_id = $1`, postID))
	for _, id := range hiddenIDs {
		require.Zero(t, countSpaceRows(t, module, `SELECT count(*) FROM space_comments WHERE comment_id = $1`, id))
		require.Zero(t, countSpaceRows(t, module, `SELECT count(*) FROM space_comment_reactions WHERE comment_id = $1`, id))
		require.Zero(t, countSpaceRows(t, module, `SELECT count(*) FROM space_notifications WHERE comment_id = $1`, id))
	}
	require.Zero(t, countSpaceRows(t, module, `SELECT count(*) FROM space_comments WHERE post_id = $1`, alicePostID))
	require.Zero(t, countSpaceRows(t, module, `SELECT count(*) FROM space_comment_reactions WHERE comment_id = 'alice-post-comment' OR actor_space_id = $1`, alice.SpaceID))
	require.Zero(t, countSpaceRows(t, module, `SELECT count(*) FROM space_notifications WHERE comment_id = 'alice-post-comment' OR actor_space_id = $1 OR recipient_space_id = $1`, alice.SpaceID))
	require.EqualValues(t, 1, countSpaceRows(t, module, `SELECT count(*) FROM space_comment_reactions WHERE comment_id = 'owner-root'`))
	require.EqualValues(t, 1, countSpaceRows(t, module, `SELECT count(*) FROM space_comment_reactions WHERE comment_id = 'separate'`))
	require.NoError(t, module.DeleteUserData(ctx, alice.OwnerID))
	require.NoError(t, module.DeleteUserData(ctx, owner.OwnerID))
	require.Zero(t, countSpaceRows(t, module, `SELECT count(*) FROM space_comments WHERE post_id = $1`, postID))
}

func TestDiscussionAccountDeletionHidesUnreadActivityUntilRecovery(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := t.Context()
	owner, alice := notificationTestSpaces(t, module)
	postID, err := testCreatePost(ctx, module, owner.OwnerID, owner.SpaceID, "post-key", nil, 1, nil)
	require.NoError(t, err)
	require.NoError(t, module.Comments.Create(ctx, alice.SpaceID, postID, models.CreateCommentRequest{CommentID: "root"}, []byte("root")))
	require.NoError(t, module.Comments.Create(ctx, owner.SpaceID, postID, models.CreateCommentRequest{CommentID: "reply", ReplyToID: "root"}, []byte("reply")))
	carolID := insertSpaceUser(t, module, "carol-unread@example.com", "carol-public")
	carol, err := testCreateSpace(ctx, module, carolID, "carol_unread", "root", "public", "secret", "nonce", "profile")
	require.NoError(t, err)
	require.NoError(t, testAddFriend(ctx, module, carolID, carol.SpaceID, owner.SpaceID, "share", 1, "share", 1))
	_, err = module.Comments.React(ctx, carol.SpaceID, postID, "reply", []byte("reaction"), "")
	require.NoError(t, err)
	require.NoError(t, module.Comments.Create(ctx, carol.SpaceID, postID, models.CreateCommentRequest{CommentID: "nested", ReplyToID: "reply"}, []byte("nested")))
	_, err = module.Spaces.DB.ExecContext(ctx, `UPDATE space_notifications SET read_at = 1 WHERE kind NOT IN ('comment_reaction', 'comment_reply')`)
	require.NoError(t, err)
	items, _, err := module.Notifications.List(ctx, owner.SpaceID, "", 50)
	require.NoError(t, err)
	var targetIDs []string
	for _, item := range items {
		if item.Kind == "comment_reaction" || item.Kind == "comment_reply" {
			require.True(t, item.Unread)
			targetIDs = append(targetIDs, item.NotificationIDs...)
		}
	}
	require.Len(t, targetIDs, 2)
	unread, err := module.Notifications.HasUnread(ctx, owner.SpaceID)
	require.NoError(t, err)
	require.True(t, unread)
	_, err = module.Spaces.DB.ExecContext(ctx, `UPDATE users SET encrypted_email = NULL WHERE user_id = $1`, alice.OwnerID)
	require.NoError(t, err)
	unread, err = module.Notifications.HasUnread(ctx, owner.SpaceID)
	require.NoError(t, err)
	require.False(t, unread)
	require.NoError(t, module.Notifications.MarkRead(ctx, owner.SpaceID, targetIDs))
	for _, id := range targetIDs {
		require.EqualValues(t, 1, countSpaceRows(t, module, `SELECT count(*) FROM space_notifications WHERE notification_id = $1 AND read_at IS NULL`, id))
	}
	_, err = module.Spaces.DB.ExecContext(ctx, `UPDATE users SET encrypted_email = '\x00'::bytea WHERE user_id = $1`, alice.OwnerID)
	require.NoError(t, err)
	unread, err = module.Notifications.HasUnread(ctx, owner.SpaceID)
	require.NoError(t, err)
	require.True(t, unread)
	require.NoError(t, module.DeleteUserData(ctx, alice.OwnerID))
	unread, err = module.Notifications.HasUnread(ctx, owner.SpaceID)
	require.NoError(t, err)
	require.False(t, unread)
	for _, id := range targetIDs {
		require.Zero(t, countSpaceRows(t, module, `SELECT count(*) FROM space_notifications WHERE notification_id = $1`, id))
	}
}

func TestDiscussionAccountCleanupWaitsForPendingReplies(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := t.Context()
	owner, alice := notificationTestSpaces(t, module)
	postID, err := testCreatePost(ctx, module, owner.OwnerID, owner.SpaceID, "post-key", nil, 1, nil)
	require.NoError(t, err)
	require.NoError(t, module.Comments.Create(ctx, alice.SpaceID, postID, models.CreateCommentRequest{CommentID: "root"}, []byte("root")))
	tx, err := module.Comments.DB.BeginTx(ctx, nil)
	require.NoError(t, err)
	defer tx.Rollback()
	_, err = discussionPostTx(ctx, tx, owner.SpaceID, postID, true)
	require.NoError(t, err)
	var backend int
	require.NoError(t, tx.QueryRowContext(ctx, `SELECT pg_backend_pid()`).Scan(&backend))
	cleanupCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	result := make(chan error, 1)
	go func() {
		result <- module.DeleteUserData(cleanupCtx, alice.OwnerID)
	}()
	require.Eventually(t, func() bool {
		var blocked bool
		err := module.Comments.DB.QueryRowContext(ctx, `SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE $1 = ANY(pg_blocking_pids(pid)))`, backend).Scan(&blocked)
		return err == nil && blocked
	}, 3*time.Second, 10*time.Millisecond)
	_, err = tx.ExecContext(ctx, `INSERT INTO space_comments (comment_id, post_id, author_space_id, parent_id, reply_to_id, cipher)
        VALUES ('pending-reply', $1, $2, 'root', 'root', $3)`, postID, owner.SpaceID, []byte("reply"))
	require.NoError(t, err)
	require.NoError(t, tx.Commit())
	require.NoError(t, <-result)
	require.Zero(t, countSpaceRows(t, module, `SELECT count(*) FROM space_comments WHERE post_id = $1`, postID))
}
