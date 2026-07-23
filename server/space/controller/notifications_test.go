package controller

import (
	"encoding/base64"
	"io"
	"testing"
	"time"

	"github.com/ente/museum/internal/testutil"
	baserepo "github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/space/models"
	log "github.com/sirupsen/logrus"
	logtest "github.com/sirupsen/logrus/hooks/test"
	"github.com/stretchr/testify/require"
)

type recordedSpaceEmail struct {
	event       string
	actorUserID int64
	actorSlug   string
	recipients  []int64
}

type recordingSpaceEmailNotifier struct {
	events chan recordedSpaceEmail
}

func newRecordingSpaceEmailNotifier() *recordingSpaceEmailNotifier {
	return &recordingSpaceEmailNotifier{events: make(chan recordedSpaceEmail, 8)}
}

func (n *recordingSpaceEmailNotifier) OnSpacePostCreated(actorUserID int64, actorSlug string, recipientUserIDs []int64) {
	n.events <- recordedSpaceEmail{event: "post_created", actorUserID: actorUserID, actorSlug: actorSlug, recipients: append([]int64(nil), recipientUserIDs...)}
}

func (n *recordingSpaceEmailNotifier) OnSpacePostLiked(actorUserID int64, actorSlug string, recipientUserID int64) {
	n.events <- recordedSpaceEmail{event: "post_liked", actorUserID: actorUserID, actorSlug: actorSlug, recipients: []int64{recipientUserID}}
}

func (n *recordingSpaceEmailNotifier) OnSpacePostReplied(actorUserID int64, actorSlug string, recipientUserID int64) {
	n.events <- recordedSpaceEmail{event: "post_replied", actorUserID: actorUserID, actorSlug: actorSlug, recipients: []int64{recipientUserID}}
}

func (n *recordingSpaceEmailNotifier) OnSpaceFriendAdded(actorUserID int64, actorSlug string, recipientUserID int64) {
	n.events <- recordedSpaceEmail{event: "friend_added", actorUserID: actorUserID, actorSlug: actorSlug, recipients: []int64{recipientUserID}}
}

func (n *recordingSpaceEmailNotifier) OnSpaceFriendRequested(actorUserID int64, actorSlug string, recipientUserID int64) {
	n.events <- recordedSpaceEmail{event: "friend_requested", actorUserID: actorUserID, actorSlug: actorSlug, recipients: []int64{recipientUserID}}
}

func requireSpaceEmail(t *testing.T, notifier *recordingSpaceEmailNotifier) recordedSpaceEmail {
	t.Helper()
	select {
	case event := <-notifier.events:
		return event
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for space email")
		return recordedSpaceEmail{}
	}
}

func requireNoSpaceEmail(t *testing.T, notifier *recordingSpaceEmailNotifier) {
	t.Helper()
	select {
	case event := <-notifier.events:
		t.Fatalf("unexpected space email: %+v", event)
	case <-time.After(100 * time.Millisecond):
	}
}

func TestSpaceEmailSubjectPrefixesUsernameWithAt(t *testing.T) {
	require.Equal(t, "@alice liked your post", spaceEmailSubject("alice", "liked your post"))
	require.Equal(t, "@alice posted a new photo", spaceEmailSubject(" alice ", "posted a new photo"))
	require.Equal(t, "A friend liked your post", spaceEmailSubject(" ", "liked your post"))
}

func TestSpaceEmailTemplateData(t *testing.T) {
	require.Equal(t, "@alice", spaceEmailActorLabel(" alice "))
	require.Equal(t, "A friend", spaceEmailActorLabel(" "))
	require.Equal(t, "just posted a new photo", spaceEmailNotificationText(spaceNotificationPostCreated, "posted a new photo"))
	require.Equal(t, "just liked your post", spaceEmailNotificationText(spaceNotificationPostLiked, "liked your post"))
	require.Equal(t, "just replied to your post", spaceEmailNotificationText(spaceNotificationPostReplied, "replied to your post"))
	require.Equal(t, "is now your friend", spaceEmailNotificationText(spaceNotificationFriendAdded, "is now your friend"))
	require.Equal(t, "sent you a friend request", spaceEmailNotificationText(spaceNotificationFriendRequested, "sent you a friend request"))
	require.Equal(t, spaceNewPostIllustrationURL, spaceEmailIllustrationURL(spaceNotificationPostCreated))
	require.Equal(t, spaceNewPostLikeIllustrationURL, spaceEmailIllustrationURL(spaceNotificationPostLiked))
	require.Equal(t, spaceNewPostReplyIllustrationURL, spaceEmailIllustrationURL(spaceNotificationPostReplied))
	require.Equal(t, spaceNewFriendIllustrationURL, spaceEmailIllustrationURL(spaceNotificationFriendAdded))
	require.Equal(t, spaceNewFriendIllustrationURL, spaceEmailIllustrationURL(spaceNotificationFriendRequested))
	require.Equal(t, spaceNewPostIllustrationWidth, spaceEmailIllustrationWidth(spaceNotificationPostCreated))
	require.Equal(t, spaceNewPostLikeIllustrationWidth, spaceEmailIllustrationWidth(spaceNotificationPostLiked))
	require.Equal(t, spaceNewPostReplyIllustrationWidth, spaceEmailIllustrationWidth(spaceNotificationPostReplied))
	require.Equal(t, spaceNewFriendIllustrationWidth, spaceEmailIllustrationWidth(spaceNotificationFriendAdded))
	require.Equal(t, spaceNewFriendIllustrationWidth, spaceEmailIllustrationWidth(spaceNotificationFriendRequested))
}

func TestSpaceEmailSenderLimitsEachSenderToFiftyEmailsPerHour(t *testing.T) {
	_, repos, _ := setupPostsControllerTest(t)
	recipientID := insertSpaceControllerUser(t, repos, "space-email-limit-recipient@example.com", "recipient-public")
	otherRecipientID := insertSpaceControllerUser(t, repos, "space-email-limit-other-recipient@example.com", "other-recipient-public")
	sender := NewSpaceEmailSender(&baserepo.UserRepository{
		DB:                  repos.Spaces.DB,
		SecretEncryptionKey: testutil.SecretEncryptionKey(),
	})
	logger := log.StandardLogger()
	originalHooks := logger.ReplaceHooks(make(log.LevelHooks))
	originalOutput := logger.Out
	logger.SetOutput(io.Discard)
	hook := logtest.NewGlobal()
	t.Cleanup(func() {
		logger.ReplaceHooks(originalHooks)
		logger.SetOutput(originalOutput)
		hook.Reset()
	})

	originalSend := sendSpaceNotificationEmail
	t.Cleanup(func() {
		sendSpaceNotificationEmail = originalSend
	})
	sent := 0
	sendSpaceNotificationEmail = func(_ []string, fromName string, fromEmail string, _ string, _ string, _ map[string]interface{}, _ []map[string]interface{}) error {
		require.Equal(t, "Ente Space", fromName)
		require.Equal(t, "space@ente.com", fromEmail)
		sent++
		return nil
	}

	for range 50 {
		sender.OnSpacePostReplied(1, "alice", recipientID)
	}
	require.Equal(t, 50, sent)

	sender.OnSpacePostLiked(1, "alice", otherRecipientID)
	require.Equal(t, 50, sent)
	require.Len(t, hook.AllEntries(), 1)
	require.Equal(t, log.WarnLevel, hook.LastEntry().Level)
	require.Equal(t, "Space email rate limit reached", hook.LastEntry().Message)
	require.Equal(t, int64(1), hook.LastEntry().Data["actor_user_id"])

	sender.OnSpaceFriendRequested(2, "bob", recipientID)
	require.Equal(t, 51, sent)
}

func TestPostLikeSendsEmailOnce(t *testing.T) {
	_, repos, ctx := setupPostsControllerTest(t)
	notifier := newRecordingSpaceEmailNotifier()
	posts := NewModule(repos, nil, notifier).Posts
	aliceID := insertSpaceControllerUser(t, repos, "alice-post-like-email@example.com", "alice-public")
	bobID := insertSpaceControllerUser(t, repos, "bob-post-like-email@example.com", "bob-public")
	aliceSpace, err := testCreateSpace(ctx, repos, aliceID, "alice_post_like_email", "alice-space-key", "alice-post-like-email-public", "alice-post-like-email-secret", "alice-post-like-email-secret-nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, repos, bobID, "bob_post_like_email", "bob-space-key", "bob-post-like-email-public", "bob-post-like-email-secret", "bob-post-like-email-secret-nonce", "bob-profile")
	require.NoError(t, err)
	require.NoError(t, testAddFriend(ctx, repos, bobID, bobSpace.SpaceID, aliceSpace.SpaceID, "alice-share-key", aliceSpace.CurrentVersion, "bob-share-key", bobSpace.CurrentVersion))
	postID, err := testCreatePost(ctx, repos, aliceID, aliceSpace.SpaceID, "post-key", nil, aliceSpace.CurrentVersion, nil)
	require.NoError(t, err)

	resp, err := posts.SetLike(ctx, bobSpace, postID, true)
	require.NoError(t, err)
	require.True(t, resp.Liked)
	email := requireSpaceEmail(t, notifier)
	require.Equal(t, recordedSpaceEmail{event: "post_liked", actorUserID: bobID, actorSlug: bobSpace.SpaceSlug, recipients: []int64{aliceID}}, email)

	_, err = posts.SetLike(ctx, bobSpace, postID, true)
	require.NoError(t, err)
	requireNoSpaceEmail(t, notifier)
}

func TestPostReplySendsEmail(t *testing.T) {
	_, repos, ctx := setupMessagesControllerTest(t)
	notifier := newRecordingSpaceEmailNotifier()
	messages := NewModule(repos, nil, notifier).Messages
	aliceID, aliceSpace := createMessageControllerUserAndSpace(t, repos, "alice-post-reply-email", "alice-public")
	bobID, bobSpace := createMessageControllerUserAndSpace(t, repos, "bob-post-reply-email", "bob-public")
	require.NoError(t, testAddFriend(ctx, repos, bobID, bobSpace.SpaceID, aliceSpace.SpaceID, "alice-share-key", aliceSpace.CurrentVersion, "bob-share-key", bobSpace.CurrentVersion))
	postID, err := testCreatePost(ctx, repos, aliceID, aliceSpace.SpaceID, "post-key", nil, aliceSpace.CurrentVersion, nil)
	require.NoError(t, err)

	_, err = messages.ReplyToPost(ctx, bobSpace, postID, models.CreateMessageRequest{
		MessageCipher:                spaceTestB64("reply-cipher"),
		SenderEncryptedMessageKey:    spaceTestB64("reply-sender-key"),
		RecipientEncryptedMessageKey: spaceTestB64("reply-recipient-key"),
	})
	require.NoError(t, err)
	email := requireSpaceEmail(t, notifier)
	require.Equal(t, recordedSpaceEmail{event: "post_replied", actorUserID: bobID, actorSlug: bobSpace.SpaceSlug, recipients: []int64{aliceID}}, email)
}

func TestAddFriendSendsEmailOnce(t *testing.T) {
	_, repos, ctx := setupFriendsControllerTest(t)
	notifier := newRecordingSpaceEmailNotifier()
	friends := NewModule(repos, nil, notifier).Friends
	aliceID := insertSpaceControllerUser(t, repos, "alice-friend-email@example.com", "alice-public")
	bobID := insertSpaceControllerUser(t, repos, "bob-friend-email@example.com", "bob-public")
	aliceSpace, err := testCreateSpace(ctx, repos, aliceID, "alice_friend_email", "alice-space-key", "alice-friend-email-public", "alice-friend-email-secret", "alice-friend-email-secret-nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, repos, bobID, "bob_friend_email", "bob-space-key", "bob-friend-email-public", "bob-friend-email-secret", "bob-friend-email-secret-nonce", "bob-profile")
	require.NoError(t, err)
	req := models.AddFriendPayload{
		TargetSpaceID:                 aliceSpace.SpaceID,
		RequesterFriendSealedSpaceKey: base64.StdEncoding.EncodeToString([]byte("bob-requester-key")),
		RequesterKeyVersion:           bobSpace.CurrentVersion,
	}

	resp, err := friends.Add(ctx, bobSpace, req)
	require.NoError(t, err)
	require.Equal(t, "requested", resp.Status)
	email := requireSpaceEmail(t, notifier)
	require.Equal(t, recordedSpaceEmail{event: "friend_requested", actorUserID: bobID, actorSlug: bobSpace.SpaceSlug, recipients: []int64{aliceID}}, email)

	_, err = friends.Add(ctx, bobSpace, req)
	require.NoError(t, err)
	requireNoSpaceEmail(t, notifier)

	requests, err := friends.ListRequests(ctx, aliceSpace)
	require.NoError(t, err)
	require.Len(t, requests, 1)
	require.Equal(t, bobSpace.SpaceSlug, requests[0].Requester.SpaceSlug)

	resp, err = friends.ConfirmRequest(ctx, aliceSpace, requests[0].RequestID, models.ConfirmFriendRequestPayload{
		TargetFriendSealedSpaceKey: base64.StdEncoding.EncodeToString([]byte("alice-target-key")),
		TargetKeyVersion:           aliceSpace.CurrentVersion,
	})
	require.NoError(t, err)
	require.Equal(t, "friend", resp.Status)
	email = requireSpaceEmail(t, notifier)
	require.Equal(t, recordedSpaceEmail{event: "friend_added", actorUserID: aliceID, actorSlug: aliceSpace.SpaceSlug, recipients: []int64{bobID}}, email)
}
