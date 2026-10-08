package controller

import (
	"context"
	"encoding/base64"
	"errors"
	"strings"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/space/models"
	spacerepo "github.com/ente/museum/space/repo"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func setupMessagesControllerTest(t *testing.T) (*MessagesController, *spacerepo.Module, context.Context) {
	t.Helper()
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})
	gin.SetMode(gin.TestMode)
	repos := spacerepo.NewModule(db, nil)
	return NewModule(repos, nil, noopSpaceActivityNotifier{}, nil).Messages, repos, context.Background()
}

func TestMessageReplyValidation(t *testing.T) {
	controller, repos, ctx := setupMessagesControllerTest(t)
	aliceID, aliceSpace := createMessageControllerUserAndSpace(t, repos, "alice-reply-validation", "alice-public")
	bobID, bobSpace := createMessageControllerUserAndSpace(t, repos, "bob-reply-validation", "bob-public")
	charlieID, charlieSpace := createMessageControllerUserAndSpace(t, repos, "charlie-reply-validation", "charlie-public")
	require.NoError(t, testAddFriend(ctx, repos, bobID, bobSpace.SpaceID, aliceSpace.SpaceID, "alice-share-key", aliceSpace.CurrentVersion, "bob-share-key", bobSpace.CurrentVersion))
	require.NoError(t, testAddFriend(ctx, repos, charlieID, charlieSpace.SpaceID, aliceSpace.SpaceID, "alice-charlie-share-key", aliceSpace.CurrentVersion, "charlie-share-key", charlieSpace.CurrentVersion))

	bobMessage := createRepoMessage(t, repos, bobID, bobSpace.SpaceID, aliceID, aliceSpace.SpaceID, "")
	charlieMessage := createRepoMessage(t, repos, charlieID, charlieSpace.SpaceID, aliceID, aliceSpace.SpaceID, "")

	_, err := controller.Create(ctx, aliceSpace, bobSpace.SpaceID, models.CreateMessageRequest{
		MessageCipher:                spaceTestB64("reply-cipher"),
		SenderEncryptedMessageKey:    spaceTestB64("reply-sender-key"),
		RecipientEncryptedMessageKey: spaceTestB64("reply-recipient-key"),
		ReplyMessageID:               charlieMessage.MessageID,
	})
	require.Error(t, err)

	reply, err := controller.Create(ctx, aliceSpace, bobSpace.SpaceID, models.CreateMessageRequest{
		MessageCipher:                spaceTestB64("reply-cipher"),
		SenderEncryptedMessageKey:    spaceTestB64("reply-sender-key"),
		RecipientEncryptedMessageKey: spaceTestB64("reply-recipient-key"),
		ReplyMessageID:               bobMessage.MessageID,
	})
	require.NoError(t, err)
	require.NotNil(t, reply.ReplyMessageID)
	require.Equal(t, bobMessage.MessageID, *reply.ReplyMessageID)

	_, err = controller.Create(ctx, aliceSpace, bobSpace.SpaceID, models.CreateMessageRequest{
		MessageCipher:                spaceTestB64("poke-reply-cipher"),
		SenderEncryptedMessageKey:    spaceTestB64("poke-reply-sender-key"),
		RecipientEncryptedMessageKey: spaceTestB64("poke-reply-recipient-key"),
		ReplyMessageID:               bobMessage.MessageID,
		NotificationKind:             spaceMessageNotificationKindPoke,
	})
	require.Error(t, err)
	require.Contains(t, err.Error(), "poke notification is not supported for replies")

	require.NoError(t, repos.Messages.DeleteMessage(ctx, bobMessage.MessageID, bobSpace.SpaceID))
	_, err = controller.Create(ctx, aliceSpace, bobSpace.SpaceID, models.CreateMessageRequest{
		MessageCipher:                spaceTestB64("reply-after-delete-cipher"),
		SenderEncryptedMessageKey:    spaceTestB64("reply-after-delete-sender-key"),
		RecipientEncryptedMessageKey: spaceTestB64("reply-after-delete-recipient-key"),
		ReplyMessageID:               bobMessage.MessageID,
	})
	require.Error(t, err)
	require.Contains(t, err.Error(), "cannot reply to a deleted message")
}

func TestMessageLikeAndDeleteAccess(t *testing.T) {
	controller, repos, ctx := setupMessagesControllerTest(t)
	aliceID, aliceSpace := createMessageControllerUserAndSpace(t, repos, "alice-message-actions", "alice-actions-public")
	bobID, bobSpace := createMessageControllerUserAndSpace(t, repos, "bob-message-actions", "bob-actions-public")
	require.NoError(t, testAddFriend(ctx, repos, bobID, bobSpace.SpaceID, aliceSpace.SpaceID, "alice-share-key", aliceSpace.CurrentVersion, "bob-share-key", bobSpace.CurrentVersion))
	message := createRepoMessage(t, repos, bobID, bobSpace.SpaceID, aliceID, aliceSpace.SpaceID, "")
	messageToDelete := createRepoMessage(t, repos, bobID, bobSpace.SpaceID, aliceID, aliceSpace.SpaceID, "")

	liked, err := controller.SetLike(ctx, aliceSpace, message.MessageID, true)
	require.NoError(t, err)
	require.True(t, liked.Liked)
	viewed, err := repos.Messages.GetMessage(ctx, message.MessageID, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.True(t, viewed.Liked)
	require.True(t, viewed.ViewerLiked)

	require.NoError(t, controller.Delete(ctx, bobSpace, messageToDelete.MessageID))
	_, err = controller.SetLike(ctx, aliceSpace, messageToDelete.MessageID, true)
	require.Error(t, err)
	require.Contains(t, err.Error(), "cannot like a deleted message")

	require.NoError(t, repos.Friends.DeleteFriendship(ctx, aliceSpace.SpaceID, bobSpace.SpaceID))
	_, err = controller.SetLike(ctx, aliceSpace, message.MessageID, false)
	require.True(t, errors.Is(err, ente.ErrPermissionDenied))
	thread, _, err := repos.Messages.ListThread(ctx, aliceSpace.SpaceID, bobSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Len(t, thread, 1)

	require.Error(t, controller.Delete(ctx, aliceSpace, message.MessageID))
	err = controller.Delete(ctx, bobSpace, message.MessageID)
	require.True(t, errors.Is(err, ente.ErrPermissionDenied))
}

func TestListThreadHidesDeletedTargetOwner(t *testing.T) {
	controller, repos, ctx := setupMessagesControllerTest(t)
	aliceID, aliceSpace := createMessageControllerUserAndSpace(t, repos, "alice-thread-deleted-owner", "alice-thread-public")
	bobID, bobSpace := createMessageControllerUserAndSpace(t, repos, "bob-thread-deleted-owner", "bob-thread-public")
	require.NoError(t, testAddFriend(ctx, repos, bobID, bobSpace.SpaceID, aliceSpace.SpaceID, "alice-share-key", aliceSpace.CurrentVersion, "bob-share-key", bobSpace.CurrentVersion))
	createRepoMessage(t, repos, bobID, bobSpace.SpaceID, aliceID, aliceSpace.SpaceID, "")

	page, err := controller.ListThread(ctx, aliceSpace, bobSpace.SpaceID, models.ListMessageThreadRequest{})
	require.NoError(t, err)
	require.Len(t, page.Items, 1)

	_, err = repos.Spaces.DB.Exec(`UPDATE users SET encrypted_email = NULL WHERE user_id = $1`, bobID)
	require.NoError(t, err)

	page, err = controller.ListThread(ctx, aliceSpace, bobSpace.SpaceID, models.ListMessageThreadRequest{})
	require.Nil(t, page)
	require.True(t, errors.Is(err, ente.ErrNotFound))
}

func TestListConversationsIncludesLatestActivePostCreatedAt(t *testing.T) {
	controller, repos, ctx := setupMessagesControllerTest(t)
	aliceID, aliceSpace := createMessageControllerUserAndSpace(t, repos, "alice-conversation-post", "alice-post-public")

	page, err := controller.ListConversations(ctx, aliceSpace)
	require.NoError(t, err)
	require.Empty(t, page.LatestPostCreatedAt)

	postID, err := testCreatePost(ctx, repos, aliceID, aliceSpace.SpaceID, "post-key", nil, aliceSpace.CurrentVersion, nil)
	require.NoError(t, err)
	var createdAt int64
	require.NoError(t, repos.Posts.DB.QueryRow(`SELECT created_at FROM space_posts WHERE post_id = $1`, postID).Scan(&createdAt))

	page, err = controller.ListConversations(ctx, aliceSpace)
	require.NoError(t, err)
	require.Equal(t, formatMicros(createdAt), page.LatestPostCreatedAt)

	require.NoError(t, repos.Posts.DeletePost(ctx, postID, aliceSpace.SpaceID))
	page, err = controller.ListConversations(ctx, aliceSpace)
	require.NoError(t, err)
	require.Empty(t, page.LatestPostCreatedAt)
}

func TestValidateCreateMessageRequestLimits(t *testing.T) {
	valid := models.CreateMessageRequest{
		MessageCipher:                spaceTestB64("cipher"),
		SenderEncryptedMessageKey:    spaceTestB64("sender-key"),
		RecipientEncryptedMessageKey: spaceTestB64("recipient-key"),
	}
	_, _, _, err := decodeCreateMessageRequest(valid)
	require.NoError(t, err)

	invalidBase64 := valid
	invalidBase64.MessageCipher = "not-base64"
	_, _, _, err = decodeCreateMessageRequest(invalidBase64)
	require.Error(t, err)

	tooLargeCipher := valid
	tooLargeCipher.MessageCipher = base64.StdEncoding.EncodeToString(make([]byte, maxSpaceMessageCipherDecodedBytes+1))
	_, _, _, err = decodeCreateMessageRequest(tooLargeCipher)
	require.Error(t, err)
	require.Contains(t, err.Error(), "messageCipher is too large")

	tooLargeKey := valid
	tooLargeKey.SenderEncryptedMessageKey = base64.StdEncoding.EncodeToString(make([]byte, maxSpaceMessageKeyDecodedBytes+1))
	_, _, _, err = decodeCreateMessageRequest(tooLargeKey)
	require.Error(t, err)
	require.Contains(t, err.Error(), "senderEncryptedMessageKey is too large")
}

func TestNormalizeOptionalMessageID(t *testing.T) {
	messageID := "wmsg_0123456789ABCDEFGHIJKL"
	normalizedMessageID, err := normalizeOptionalMessageID(messageID)
	require.NoError(t, err)
	require.Equal(t, messageID, normalizedMessageID)

	for _, invalidMessageID := range []string{
		"../../../spaces/space_0123456789ABCDEFGHIJKL/posts/42",
		"wmsg_/../../posts/123456789",
	} {
		_, err = normalizeOptionalMessageID(invalidMessageID)
		require.Error(t, err)
		require.Contains(t, err.Error(), "messageId is invalid")
	}
}

func createMessageControllerUserAndSpace(t *testing.T, repos *spacerepo.Module, slug string, publicKey string) (int64, *spacerepo.SpaceRecord) {
	t.Helper()
	userID := insertSpaceControllerUser(t, repos, slug+"@example.com", publicKey)
	spaceSlug := strings.ReplaceAll(slug, "-", "_")
	space, err := testCreateSpace(context.Background(), repos, userID, spaceSlug, slug+"-space-key", slug+"-public", slug+"-secret", slug+"-secret-nonce", slug+"-profile")
	require.NoError(t, err)
	return userID, space
}

func createRepoMessage(t *testing.T, repos *spacerepo.Module, senderID int64, senderSpaceID string, recipientID int64, recipientSpaceID string, replyMessageID string) *spacerepo.SpaceMessageRecord {
	t.Helper()
	input := spacerepo.CreateSpaceMessageRecord{
		Kind:                         "regular",
		SenderSpaceID:                senderSpaceID,
		RecipientSpaceID:             recipientSpaceID,
		MessageCipher:                testSpaceBytes("cipher"),
		SenderEncryptedMessageKey:    testSpaceBytes("sender-key"),
		RecipientEncryptedMessageKey: testSpaceBytes("recipient-key"),
	}
	if replyMessageID != "" {
		input.ReplyMessageID.Valid = true
		input.ReplyMessageID.String = replyMessageID
	}
	message, err := repos.Messages.CreateMessage(context.Background(), input)
	require.NoError(t, err)
	return message
}

func spaceTestB64(value string) string {
	return base64.StdEncoding.EncodeToString([]byte(value))
}

func TestMessageReactions(t *testing.T) {
	controller, repos, ctx := setupMessagesControllerTest(t)
	aliceID, alice := createMessageControllerUserAndSpace(t, repos, "alice-reactions", "alice-reactions-key")
	bobID, bob := createMessageControllerUserAndSpace(t, repos, "bob-reactions", "bob-reactions-key")
	require.NoError(t, testAddFriend(ctx, repos, bobID, bob.SpaceID, alice.SpaceID, "alice-share-key", alice.CurrentVersion, "bob-share-key", bob.CurrentVersion))
	message := createRepoMessage(t, repos, bobID, bob.SpaceID, aliceID, alice.SpaceID, "")
	notifier := newRecordingSpaceActivityNotifier()
	controller.ActivityNotifier = notifier
	request := models.SetMessageReactionRequest{
		SenderEncryptedReaction:    base64.StdEncoding.EncodeToString([]byte(strings.Repeat("s", 304))),
		RecipientEncryptedReaction: base64.StdEncoding.EncodeToString([]byte(strings.Repeat("r", 304))),
	}
	_, err := controller.SetReaction(ctx, bob, message.MessageID, request)
	require.Error(t, err)
	invalid := request
	invalid.SenderEncryptedReaction = "not base64"
	_, err = controller.SetReaction(ctx, alice, message.MessageID, invalid)
	require.Error(t, err)
	invalid.SenderEncryptedReaction = base64.StdEncoding.EncodeToString([]byte("short"))
	_, err = controller.SetReaction(ctx, alice, message.MessageID, invalid)
	require.Error(t, err)

	response, err := controller.SetReaction(ctx, alice, message.MessageID, request)
	require.NoError(t, err)
	require.True(t, response.Liked)
	require.Equal(t, bobID, requireSpaceActivity(t, notifier).recipientIDs[0])
	for _, viewer := range []*spacerepo.SpaceRecord{alice, bob} {
		loaded, err := repos.Messages.GetMessage(ctx, message.MessageID, viewer.SpaceID)
		require.NoError(t, err)
		expected := strings.Repeat("s", 304)
		if viewer.SpaceID == alice.SpaceID {
			expected = strings.Repeat("r", 304)
		}
		require.Equal(t, []byte(expected), loaded.EncryptedReaction)
		require.True(t, loaded.Liked)
		require.Equal(t, viewer.SpaceID == alice.SpaceID, loaded.ViewerLiked)
	}
	summaries, err := repos.Messages.ListLatestChatSummaries(ctx, bob.SpaceID, []string{alice.SpaceID})
	require.NoError(t, err)
	activity := summaries[alice.SpaceID].LatestActivity
	require.Equal(t, "message_like", activity.Type)
	require.Equal(t, []byte(strings.Repeat("s", 304)), activity.EncryptedReaction)
	require.NoError(t, repos.Read.UpsertNotificationReadMarker(ctx, bob.SpaceID, alice.SpaceID, activity.CreatedAt))

	_, err = controller.SetReaction(ctx, alice, message.MessageID, request)
	require.NoError(t, err)
	requireNoSpaceActivity(t, notifier)
	request.SenderEncryptedReaction = base64.StdEncoding.EncodeToString([]byte(strings.Repeat("n", 304)))
	_, err = controller.SetReaction(ctx, alice, message.MessageID, request)
	require.NoError(t, err)
	requireNoSpaceActivity(t, notifier)
	summaries, err = repos.Messages.ListLatestChatSummaries(ctx, bob.SpaceID, []string{alice.SpaceID})
	require.NoError(t, err)
	require.Equal(t, activity.CreatedAt, summaries[alice.SpaceID].LatestActivity.CreatedAt)
	require.Equal(t, []byte(strings.Repeat("n", 304)), summaries[alice.SpaceID].LatestActivity.EncryptedReaction)
	require.Empty(t, summaries[alice.SpaceID].UnreadActivities)

	_, err = controller.SetLike(ctx, alice, message.MessageID, false)
	require.NoError(t, err)
	loaded, err := repos.Messages.GetMessage(ctx, message.MessageID, bob.SpaceID)
	require.NoError(t, err)
	require.Empty(t, loaded.EncryptedReaction)
	require.False(t, loaded.Liked)
	_, err = controller.SetReaction(ctx, alice, message.MessageID, request)
	require.NoError(t, err)
	requireSpaceActivity(t, notifier)
	require.NoError(t, controller.Delete(ctx, bob, message.MessageID))
	loaded, err = repos.Messages.GetMessage(ctx, message.MessageID, bob.SpaceID)
	require.NoError(t, err)
	require.Empty(t, loaded.EncryptedReaction)
	require.False(t, loaded.Liked)
	_, err = controller.SetReaction(ctx, alice, message.MessageID, request)
	require.Error(t, err)

	message = createRepoMessage(t, repos, bobID, bob.SpaceID, aliceID, alice.SpaceID, "")
	require.NoError(t, repos.Friends.DeleteFriendship(ctx, alice.SpaceID, bob.SpaceID))
	_, err = controller.SetReaction(ctx, alice, message.MessageID, request)
	require.ErrorIs(t, err, ente.ErrPermissionDenied)
}
