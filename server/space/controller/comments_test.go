package controller

import (
	"encoding/base64"
	"strings"
	"testing"

	"github.com/ente/museum/space/models"
	"github.com/ente/museum/space/repo"
	"github.com/stretchr/testify/require"
)

func TestCommentIDFormatAcceptsGeneratedAndExistingSafeIDs(t *testing.T) {
	for _, id := range []string{"5249f283-aaf2-4e6d-96c0-091f04b72f90", "comment-y", "wcomment_123", "A0", strings.Repeat("a", 64)} {
		require.True(t, commentIDPattern.MatchString(id), id)
	}
}

func TestDiscussionCountsOnPostsAndFeed(t *testing.T) {
	posts, repos, ctx := setupPostsControllerTest(t)
	ownerID := insertSpaceControllerUser(t, repos, "owner-count@example.com", "owner-public")
	owner, err := testCreateSpace(ctx, repos, ownerID, "owner_count", "root", "owner-public", "secret", "nonce", "profile")
	require.NoError(t, err)
	friendID := insertSpaceControllerUser(t, repos, "friend-count@example.com", "friend-public")
	friend, err := testCreateSpace(ctx, repos, friendID, "friend_count", "root", "friend-public", "secret", "nonce", "profile")
	require.NoError(t, err)
	require.NoError(t, testAddFriend(ctx, repos, friendID, friend.SpaceID, owner.SpaceID, "owner-share", 1, "friend-share", 1))
	postID, err := testCreatePost(ctx, repos, ownerID, owner.SpaceID, "post-key", nil, 1, nil)
	require.NoError(t, err)
	otherPostID, err := testCreatePost(ctx, repos, ownerID, owner.SpaceID, "other-key", nil, 1, nil)
	require.NoError(t, err)
	require.NoError(t, repos.Comments.Create(ctx, owner.SpaceID, otherPostID, models.CreateCommentRequest{CommentID: "other"}, []byte("other")))
	assertCount := func(count int64) {
		t.Helper()
		post, err := repos.Posts.GetPost(ctx, postID, owner.SpaceID)
		require.NoError(t, err)
		response, err := posts.postResponse(ctx, post, true)
		require.NoError(t, err)
		require.Equal(t, count, response.CommentCount)
		feed, err := posts.ListFeed(ctx, owner, models.ListFeedRequest{})
		require.NoError(t, err)
		require.Len(t, feed.Items, 2)
		for _, item := range feed.Items {
			if item.PostID == postID {
				require.Equal(t, count, item.CommentCount)
			} else {
				require.EqualValues(t, 1, item.CommentCount)
			}
		}
	}
	assertCount(0)
	require.NoError(t, repos.Comments.Create(ctx, owner.SpaceID, postID, models.CreateCommentRequest{CommentID: "root"}, []byte("root")))
	require.NoError(t, repos.Comments.Create(ctx, friend.SpaceID, postID, models.CreateCommentRequest{CommentID: "reply", ReplyToID: "root"}, []byte("reply")))
	assertCount(2)
	require.NoError(t, repos.Comments.Delete(ctx, owner.SpaceID, postID, "root"))
	assertCount(0)
	require.NoError(t, repos.Comments.Create(ctx, friend.SpaceID, postID, models.CreateCommentRequest{CommentID: "remaining"}, []byte("remaining")))
	assertCount(1)
	_, err = repos.Comments.DB.ExecContext(ctx, `UPDATE users SET encrypted_email = NULL WHERE user_id = $1`, friendID)
	require.NoError(t, err)
	assertCount(0)
}

func TestDiscussionNotifiesPostOwnerParticipantsAndLikers(t *testing.T) {
	_, repos, ctx := setupPostsControllerTest(t)
	notifier := newRecordingSpaceActivityNotifier()
	comments := NewModule(repos, nil, notifier, nil).Comments
	spaces := make(map[string]*repo.SpaceRecord)
	for _, name := range []string{"owner", "alice", "bob", "observer", "liker"} {
		userID := insertSpaceControllerUser(t, repos, name+"-discussion@example.com", name+"-public")
		space, err := testCreateSpace(ctx, repos, userID, name+"_discussion", "root", name+"-public", "secret", "nonce", "profile")
		require.NoError(t, err)
		spaces[name] = space
		if name != "owner" {
			require.NoError(t, testAddFriend(ctx, repos, userID, space.SpaceID, spaces["owner"].SpaceID, "owner-share", 1, "friend-share", 1))
		}
	}
	owner := spaces["owner"]
	postID, err := testCreatePost(ctx, repos, owner.OwnerID, owner.SpaceID, "post-key", nil, 1, nil)
	require.NoError(t, err)
	otherPostID, err := testCreatePost(ctx, repos, owner.OwnerID, owner.SpaceID, "other-post-key", nil, 1, nil)
	require.NoError(t, err)
	liker := spaces["liker"]
	require.NoError(t, testAddFriend(ctx, repos, liker.OwnerID, liker.SpaceID, spaces["alice"].SpaceID, "alice-share", 1, "liker-share", 1))
	_, err = repos.Posts.SetLikeWithCreated(ctx, otherPostID, liker.SpaceID, true)
	require.NoError(t, err)
	for _, test := range []struct {
		id         string
		actor      string
		postID     int64
		replyTo    string
		recipients map[string]string
	}{
		{"other-post", "observer", otherPostID, "", map[string]string{"owner": "comment"}},
		{"before-like", "alice", postID, "", map[string]string{"owner": "comment"}},
		{"first", "alice", postID, "", map[string]string{"owner": "comment", "liker": "comment"}},
		{"repeat", "alice", postID, "", map[string]string{"owner": "comment", "liker": "comment"}},
		{"second", "bob", postID, "first", map[string]string{"owner": "comment", "alice": "comment_reply"}},
		{"new-comment", "alice", postID, "", map[string]string{"owner": "comment", "liker": "comment"}},
		{"owner-reply", "owner", postID, "first", map[string]string{"alice": "comment_reply", "bob": "comment", "liker": "comment"}},
		{"reply", "alice", postID, "second", map[string]string{"owner": "comment", "bob": "comment_reply", "liker": "comment"}},
		{"reply-to-owner", "bob", postID, "owner-reply", map[string]string{"owner": "comment_reply"}},
		{"after-unlike", "alice", postID, "", map[string]string{"owner": "comment"}},
		{"after-relike", "alice", postID, "", map[string]string{"owner": "comment", "liker": "comment"}},
		{"liker-comment", "liker", postID, "", map[string]string{"owner": "comment", "alice": "comment"}},
		{"reply-to-liker", "alice", postID, "liker-comment", map[string]string{"owner": "comment", "liker": "comment_reply"}},
		{"after-unlike-participant", "alice", postID, "", map[string]string{"owner": "comment", "liker": "comment"}},
		{"after-liker-removal", "alice", postID, "", map[string]string{"owner": "comment"}},
		{"after-friending", "alice", postID, "", map[string]string{"owner": "comment", "bob": "comment"}},
		{"after-unfriending", "alice", postID, "", map[string]string{"owner": "comment"}},
		{"after-removal", "owner", postID, "", map[string]string{"bob": "comment"}},
		{"after-deletion", "owner", postID, "", map[string]string{}},
	} {
		t.Run(test.id, func(t *testing.T) {
			switch test.id {
			case "first", "after-relike", "after-liker-removal":
				_, err := repos.Posts.SetLikeWithCreated(ctx, postID, liker.SpaceID, true)
				require.NoError(t, err)
			case "after-unlike", "after-unlike-participant":
				_, err := repos.Posts.SetLikeWithCreated(ctx, postID, liker.SpaceID, false)
				require.NoError(t, err)
			}
			if test.id == "after-liker-removal" {
				require.NoError(t, repos.Friends.DeleteFriendship(ctx, owner.SpaceID, liker.SpaceID))
			}
			if test.id == "after-friending" {
				require.NoError(t, testAddFriend(ctx, repos, spaces["alice"].OwnerID, spaces["alice"].SpaceID, spaces["bob"].SpaceID, "bob-share", 1, "alice-share", 1))
			}
			if test.id == "after-unfriending" {
				require.NoError(t, repos.Friends.DeleteFriendship(ctx, spaces["alice"].SpaceID, spaces["bob"].SpaceID))
			}
			if test.id == "after-removal" {
				require.NoError(t, repos.Friends.DeleteFriendship(ctx, owner.SpaceID, spaces["alice"].SpaceID))
			}
			if test.id == "after-deletion" {
				_, err := repos.Spaces.DB.ExecContext(ctx, `UPDATE users SET encrypted_email = NULL WHERE user_id = $1`, spaces["bob"].OwnerID)
				require.NoError(t, err)
			}
			request := models.CreateCommentRequest{
				CommentID: test.id,
				ReplyToID: test.replyTo,
				Cipher:    base64.StdEncoding.EncodeToString([]byte(test.id)),
			}
			require.NoError(t, comments.Create(ctx, spaces[test.actor], test.postID, request))
			var expectedRecipients, notifiedRecipients []int64
			expectedKinds := make(map[int64]string)
			for name, kind := range test.recipients {
				expectedRecipients = append(expectedRecipients, spaces[name].OwnerID)
				expectedKinds[spaces[name].OwnerID] = kind
			}
			for range test.recipients {
				activity := requireSpaceActivity(t, notifier)
				require.Equal(t, spaces[test.actor].SpaceID, activity.actorSpaceID)
				require.Equal(t, spaceActivityActor(owner), activity.postOwner)
				require.Equal(t, test.postID, activity.postID)
				require.Equal(t, test.id, activity.commentID)
				require.Len(t, activity.recipientIDs, 1)
				require.Equal(t, expectedKinds[activity.recipientIDs[0]], activity.event)
				notifiedRecipients = append(notifiedRecipients, activity.recipientIDs...)
			}
			require.ElementsMatch(t, expectedRecipients, notifiedRecipients)
			require.NoError(t, comments.Create(ctx, spaces[test.actor], test.postID, request))
			requireNoSpaceActivity(t, notifier)
			for name, space := range spaces {
				items, _, err := repos.Notifications.List(ctx, space.SpaceID, "", 50)
				require.NoError(t, err)
				var kinds []string
				for _, item := range items {
					if item.CommentID == test.id {
						require.Equal(t, owner.SpaceID, item.PostSpaceID)
						require.Equal(t, owner.SpaceSlug, item.PostOwnerSlug)
						require.Equal(t, test.postID, item.PostID.Int64)
						kinds = append(kinds, item.Kind)
						if name == "liker" && test.id == "first" {
							require.Len(t, item.NotificationIDs, 1)
						}
						if name == "liker" && test.id == "owner-reply" {
							require.Len(t, item.NotificationIDs, 4)
							require.EqualValues(t, 2, item.ActorCount)
						}
					}
				}
				if kind, ok := test.recipients[name]; ok {
					require.Equal(t, []string{kind}, kinds, name)
				} else {
					require.Empty(t, kinds, name)
				}
			}
		})
	}
}

func TestCommentReactionChangesDoNotSendAnotherPush(t *testing.T) {
	_, repos, ctx := setupPostsControllerTest(t)
	notifier := newRecordingSpaceActivityNotifier()
	comments := NewModule(repos, nil, notifier, nil).Comments
	ownerID := insertSpaceControllerUser(t, repos, "owner-reaction@example.com", "owner-public")
	owner, err := testCreateSpace(ctx, repos, ownerID, "owner_reaction", "root", "owner-public", "secret", "nonce", "profile")
	require.NoError(t, err)
	friendID := insertSpaceControllerUser(t, repos, "friend-reaction@example.com", "friend-public")
	friend, err := testCreateSpace(ctx, repos, friendID, "friend_reaction", "root", "friend-public", "secret", "nonce", "profile")
	require.NoError(t, err)
	require.NoError(t, testAddFriend(ctx, repos, friendID, friend.SpaceID, owner.SpaceID, "owner-share", 1, "friend-share", 1))
	postID, err := testCreatePost(ctx, repos, ownerID, owner.SpaceID, "post-key", nil, 1, nil)
	require.NoError(t, err)
	require.NoError(t, repos.Comments.Create(ctx, friend.SpaceID, postID, models.CreateCommentRequest{CommentID: "comment"}, []byte("comment")))
	var notificationID string
	for i, reaction := range []string{"heart", "laugh", "laugh"} {
		require.NoError(t, comments.React(ctx, owner, postID, "comment", &models.SetCommentReactionRequest{
			Cipher: base64.StdEncoding.EncodeToString([]byte(reaction)),
		}, ""))
		if i == 0 {
			activity := requireSpaceActivity(t, notifier)
			require.Equal(t, []int64{friendID}, activity.recipientIDs)
			require.Equal(t, "comment_reaction", activity.event)
			require.Equal(t, spaceActivityActor(owner), activity.postOwner)
			require.Equal(t, postID, activity.postID)
		}
		requireNoSpaceActivity(t, notifier)
		items, _, err := repos.Notifications.List(ctx, friend.SpaceID, "", 50)
		require.NoError(t, err)
		require.Len(t, items, 2)
		require.Equal(t, "comment_reaction", items[0].Kind)
		if i == 0 {
			notificationID = items[0].NotificationID
		}
		require.Equal(t, notificationID, items[0].NotificationID)
		require.Equal(t, i == 0, items[0].Unread)
		require.NoError(t, repos.Notifications.MarkRead(ctx, friend.SpaceID, []string{items[0].NotificationID}))
		var cipher []byte
		require.NoError(t, repos.Comments.DB.QueryRowContext(ctx, `SELECT cipher FROM space_comment_reactions WHERE comment_id = 'comment' AND actor_space_id = $1`, owner.SpaceID).Scan(&cipher))
		require.Equal(t, reaction, string(cipher))
	}
	require.NoError(t, comments.React(ctx, owner, postID, "comment", nil, ""))
	requireNoSpaceActivity(t, notifier)
	items, _, err := repos.Notifications.List(ctx, friend.SpaceID, "", 50)
	require.NoError(t, err)
	require.Len(t, items, 1)
	require.Equal(t, "friend_accepted", items[0].Kind)
	require.NoError(t, comments.React(ctx, owner, postID, "comment", &models.SetCommentReactionRequest{
		Cipher: base64.StdEncoding.EncodeToString([]byte("heart")),
	}, ""))
	require.Equal(t, []int64{friendID}, requireSpaceActivity(t, notifier).recipientIDs)
	require.NoError(t, comments.React(ctx, friend, postID, "comment", &models.SetCommentReactionRequest{
		Cipher: base64.StdEncoding.EncodeToString([]byte("self")),
	}, ""))
	requireNoSpaceActivity(t, notifier)
}
