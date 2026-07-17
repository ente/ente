package repo

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"errors"
	"sort"
	"strconv"
	"sync"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	timeutil "github.com/ente/museum/pkg/utils/time"
	"github.com/stretchr/testify/require"
)

func newSpaceTestModule(t *testing.T) *Module {
	t.Helper()
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})
	return NewModule(db, nil)
}

type SpaceMessageConversationRecord struct {
	Friend             SpaceActorRecord
	LatestActivity     SpaceMessageConversationActivityRecord
	UnreadActivities   []SpaceMessageConversationActivityRecord
	Unread             bool
	UnreadCount        int64
	NotificationUnread bool
	SortCreatedAt      int64
	SortID             string
}

func listTestConversations(ctx context.Context, module *Module, viewerSpaceID string, cursor string, limit int) ([]SpaceMessageConversationRecord, string, error) {
	friends, err := module.Friends.ListFriendsForSpace(ctx, viewerSpaceID)
	if err != nil {
		return nil, "", err
	}
	friendSpaceIDs := make([]string, 0, len(friends))
	for _, friend := range friends {
		friendSpaceIDs = append(friendSpaceIDs, friend.Friend.SpaceID)
	}
	summaries, err := module.Messages.ListLatestChatSummaries(ctx, viewerSpaceID, friendSpaceIDs)
	if err != nil {
		return nil, "", err
	}
	conversations := make([]SpaceMessageConversationRecord, 0, len(friends))
	for _, friend := range friends {
		summary, ok := summaries[friend.Friend.SpaceID]
		conversation := SpaceMessageConversationRecord{
			Friend: friend.Friend,
		}
		if ok {
			conversation.LatestActivity = summary.LatestActivity
			conversation.UnreadActivities = summary.UnreadActivities
			conversation.UnreadCount = countChatUnreadActivities(summary.UnreadActivities)
			conversation.Unread = conversation.UnreadCount > 0
			conversation.NotificationUnread = len(summary.UnreadActivities) > 0
		} else {
			conversation.LatestActivity = SpaceMessageConversationActivityRecord{
				ID:        "empty:" + friend.Friend.SpaceID,
				Type:      "empty",
				CreatedAt: friend.CreatedAt,
			}
		}
		conversation.SortCreatedAt = conversation.LatestActivity.CreatedAt
		conversation.SortID = conversation.LatestActivity.ID
		conversations = append(conversations, conversation)
	}
	sort.Slice(conversations, func(i, j int) bool {
		if conversations[i].SortCreatedAt != conversations[j].SortCreatedAt {
			return conversations[i].SortCreatedAt > conversations[j].SortCreatedAt
		}
		return conversations[i].SortID > conversations[j].SortID
	})
	if createdAt, id, ok := parseMessageCursor(cursor); ok {
		filtered := conversations[:0]
		for _, conversation := range conversations {
			if conversation.SortCreatedAt < createdAt || (conversation.SortCreatedAt == createdAt && conversation.SortID < id) {
				filtered = append(filtered, conversation)
			}
		}
		conversations = filtered
	}
	limit = optionalInt(limit, 50)
	if limit > 100 {
		limit = 100
	}
	nextCursor := ""
	if len(conversations) > limit {
		last := conversations[limit-1]
		nextCursor = strconv.FormatInt(last.SortCreatedAt, 10) + ":" + last.SortID
		conversations = conversations[:limit]
	}
	return conversations, nextCursor, nil
}

func countChatUnreadActivities(activities []SpaceMessageConversationActivityRecord) int64 {
	var count int64
	for _, activity := range activities {
		if activity.Type == "message" || activity.Type == "post_reply" {
			count++
		}
	}
	return count
}

func testSpaceBytes(value string) []byte {
	return []byte(value)
}

func testCreateSpace(ctx context.Context, module *Module, ownerID int64, spaceSlug string, rootWrappedSpaceKey string, publicKey string, encryptedSecretKey string, _ string, encryptedProfile string) (*SpaceRecord, error) {
	return module.Spaces.CreateSpace(ctx, ownerID, spaceSlug, testSpaceBytes(rootWrappedSpaceKey), testSpaceBytes(publicKey), testSpaceBytes(encryptedSecretKey), testSpaceBytes(encryptedProfile), "")
}

func testUpdateProfile(ctx context.Context, module *Module, _ int64, spaceID string, keyVersion int, encryptedProfile string, avatar *ProfileAssetUpdate, cover *ProfileAssetUpdate, removeAvatar bool, removeCover bool) (*SpaceRecord, error) {
	return module.Spaces.UpdateProfile(ctx, spaceID, keyVersion, testSpaceBytes(encryptedProfile), avatar, cover, removeAvatar, removeCover)
}

func testRotateKey(ctx context.Context, module *Module, _ int64, spaceID string, keyVersion int, rootWrappedSpaceKey string, wrappedPrevKey string, encryptedProfile string) (*SpaceRecord, error) {
	return module.Spaces.RotateKey(ctx, spaceID, keyVersion, testSpaceBytes(rootWrappedSpaceKey), testSpaceBytes(wrappedPrevKey), testSpaceBytes(encryptedProfile))
}

func testAddFriend(ctx context.Context, module *Module, requesterID int64, requesterSpaceID string, targetSpaceID string, targetFriendSealedSpaceKey string, targetKeyVersion int, requesterFriendSealedSpaceKey string, requesterKeyVersion int) error {
	request, _, _, err := module.Friends.CreateFriendRequest(ctx, requesterID, requesterSpaceID, targetSpaceID, testSpaceBytes(requesterFriendSealedSpaceKey), requesterKeyVersion)
	if err != nil {
		return err
	}
	_, _, err = module.Friends.ConfirmFriendRequest(ctx, targetSpaceID, request.RequestID, testSpaceBytes(targetFriendSealedSpaceKey), targetKeyVersion)
	if err != nil {
		return err
	}
	res, err := module.Messages.DB.ExecContext(ctx, `
		UPDATE space_messages
		SET created_at = 1, updated_at = 1
		WHERE kind = 'friend_added'
		  AND (
		      (sender_space_id = $1 AND recipient_space_id = $2)
		      OR (sender_space_id = $2 AND recipient_space_id = $1)
		  )
	`, requesterSpaceID, targetSpaceID)
	if err != nil {
		return err
	}
	affected, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if affected == 0 {
		return sql.ErrNoRows
	}
	_, err = module.Read.DB.ExecContext(ctx, `
		INSERT INTO space_notification_read_markers (viewer_space_id, friend_space_id, read_at)
		VALUES ($1, $2, 1), ($2, $1, 1)
		ON CONFLICT (viewer_space_id, friend_space_id) DO UPDATE
		SET read_at = EXCLUDED.read_at
	`, requesterSpaceID, targetSpaceID)
	return err
}

func testSetPostLike(ctx context.Context, module *Module, postID int64, actorSpaceID string, like bool) error {
	_, err := module.Posts.SetLikeWithCreated(ctx, postID, actorSpaceID, like)
	return err
}

func testCreateFriendRequest(ctx context.Context, module *Module, requesterID int64, requesterSpaceID string, targetSpaceID string, requesterFriendSealedSpaceKey string, requesterKeyVersion int) (*SpaceFriendRequestRecord, bool, error) {
	request, created, _, err := module.Friends.CreateFriendRequest(ctx, requesterID, requesterSpaceID, targetSpaceID, testSpaceBytes(requesterFriendSealedSpaceKey), requesterKeyVersion)
	return request, created, err
}

func testConfirmFriendRequest(ctx context.Context, module *Module, _ int64, targetSpaceID string, requestID int64, targetFriendSealedSpaceKey string, targetKeyVersion int) (int64, bool, error) {
	return module.Friends.ConfirmFriendRequest(ctx, targetSpaceID, requestID, testSpaceBytes(targetFriendSealedSpaceKey), targetKeyVersion)
}

func testUpsertShare(ctx context.Context, module *Module, spaceID string, friendSpaceID string, friendSealedSpaceKey string, keyVersion int) error {
	return upsertFriendShare(ctx, module.Friends.DB, friendShareMutation{
		SpaceID:              spaceID,
		FriendSpaceID:        friendSpaceID,
		FriendSealedSpaceKey: testSpaceBytes(friendSealedSpaceKey),
		KeyVersion:           keyVersion,
	})
}

func testUpdateShare(ctx context.Context, module *Module, spaceID string, friendSpaceID string, friendSealedSpaceKey string, keyVersion int) error {
	return module.Friends.UpdateShares(ctx, spaceID, []SpaceShareUpdateRecord{
		{FriendSpaceID: friendSpaceID, FriendSealedSpaceKey: testSpaceBytes(friendSealedSpaceKey)},
	}, keyVersion)
}

func deleteShareBySpaceAndFriend(ctx context.Context, module *Module, spaceID string, friendSpaceID string) error {
	_, err := module.Friends.DB.ExecContext(ctx, `DELETE FROM space_friend_shares WHERE space_id = $1 AND friend_space_id = $2`, spaceID, friendSpaceID)
	return err
}

func testCreatePost(ctx context.Context, module *Module, _ int64, spaceID string, encryptedPostKey string, captionCipher *string, keyVersion int, objects []SpacePostAssetRecord) (int64, error) {
	var caption []byte
	if captionCipher != nil {
		caption = testSpaceBytes(*captionCipher)
	}
	postID, _, err := module.Posts.CreatePost(ctx, spaceID, testSpaceBytes(encryptedPostKey), caption, keyVersion, objects)
	return postID, err
}

func TestCreateSpaceEnforcesOneSpacePerOwner(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := context.Background()
	userID := insertSpaceUser(t, module, "space-limit@example.com", "space-limit-public")

	_, err := testCreateSpace(ctx, module, userID, "space_limit", "root", "public", "secret", "nonce", "profile")
	require.NoError(t, err)

	_, err = testCreateSpace(ctx, module, userID, "another_space", "root", "public", "secret", "nonce", "profile")
	require.ErrorIs(t, err, ErrSpaceOwnerLimitReached)
	require.Equal(t, int64(1), countSpaceRows(t, module, `SELECT COUNT(*) FROM spaces WHERE owner_id = $1`, userID))
}

func TestCreatePostEnforcesSpacePostLimit(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := context.Background()
	userID := insertSpaceUser(t, module, "post-limit@example.com", "post-limit-public")
	space, err := testCreateSpace(ctx, module, userID, "post_limit", "root", "public", "secret", "nonce", "profile")
	require.NoError(t, err)

	_, err = module.Posts.DB.ExecContext(ctx, `
		INSERT INTO space_posts (space_id, encrypted_post_key, key_version)
		SELECT $1, 'post-key', $2
		FROM generate_series(1, $3)
	`, space.SpaceID, space.CurrentVersion, MaxPostsPerSpace)
	require.NoError(t, err)

	_, postCount, err := module.Posts.CreatePost(ctx, space.SpaceID, testSpaceBytes("post-key"), nil, space.CurrentVersion, nil)
	require.ErrorIs(t, err, ErrSpacePostLimitReached)
	require.Equal(t, MaxPostsPerSpace, postCount)

	_, err = module.Posts.DB.ExecContext(ctx, `
		UPDATE space_posts
		SET is_deleted = TRUE
		WHERE post_id = (
			SELECT MIN(post_id)
			FROM space_posts
			WHERE space_id = $1
		)
	`, space.SpaceID)
	require.NoError(t, err)

	postID, postCount, err := module.Posts.CreatePost(ctx, space.SpaceID, testSpaceBytes("post-key"), nil, space.CurrentVersion, nil)
	require.NoError(t, err)
	require.NotZero(t, postID)
	require.Equal(t, MaxPostsPerSpace, postCount)
}

func TestCreateMessageEnforcesSenderLimit(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := context.Background()
	aliceID := insertSpaceUser(t, module, "message-limit-alice@example.com", "message-limit-alice-public")
	bobID := insertSpaceUser(t, module, "message-limit-bob@example.com", "message-limit-bob-public")
	aliceSpace, err := testCreateSpace(ctx, module, aliceID, "message_limit_alice", "root", "public", "secret", "nonce", "profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, module, bobID, "message_limit_bob", "root", "public", "secret", "nonce", "profile")
	require.NoError(t, err)

	_, err = module.Messages.DB.ExecContext(ctx, `
		INSERT INTO space_messages (
			message_id,
			sender_space_id,
			recipient_space_id,
			kind,
			message_cipher,
			sender_encrypted_message_key,
			recipient_encrypted_message_key
		)
		SELECT 'message-limit-' || value, $1, $2, 'regular', $3, $4, $5
		FROM generate_series(1, $6) AS value
	`, aliceSpace.SpaceID, bobSpace.SpaceID, testSpaceBytes("cipher"), testSpaceBytes("sender-key"), testSpaceBytes("recipient-key"), MaxActiveMessagesSentPerSpace)
	require.NoError(t, err)

	input := CreateSpaceMessageRecord{
		Kind:                         "regular",
		SenderSpaceID:                aliceSpace.SpaceID,
		RecipientSpaceID:             bobSpace.SpaceID,
		MessageCipher:                testSpaceBytes("cipher"),
		SenderEncryptedMessageKey:    testSpaceBytes("sender-key"),
		RecipientEncryptedMessageKey: testSpaceBytes("recipient-key"),
	}
	_, err = module.Messages.CreateMessage(ctx, input)
	require.ErrorIs(t, err, ErrSpaceMessageLimitReached)

	input.SenderSpaceID = bobSpace.SpaceID
	input.RecipientSpaceID = aliceSpace.SpaceID
	_, err = module.Messages.CreateMessage(ctx, input)
	require.NoError(t, err)

	require.NoError(t, module.Messages.DeleteMessage(ctx, "message-limit-1", aliceSpace.SpaceID))
	input.SenderSpaceID = aliceSpace.SpaceID
	input.RecipientSpaceID = bobSpace.SpaceID
	_, err = module.Messages.CreateMessage(ctx, input)
	require.NoError(t, err)
}

func TestCreateFriendRequestEnforcesTargetLimit(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := context.Background()
	targetID := insertSpaceUser(t, module, "request-limit-target@example.com", "request-limit-target-public")
	targetSpace, err := testCreateSpace(ctx, module, targetID, "request_limit_target", "root", "public", "secret", "nonce", "profile")
	require.NoError(t, err)

	var firstRequestID int64
	for i := 0; i < MaxPendingFriendRequestsPerSpace; i++ {
		suffix := strconv.Itoa(i)
		requesterID := insertSpaceUser(t, module, "request-limit-"+suffix+"@example.com", "request-limit-public-"+suffix)
		requesterSpace, err := testCreateSpace(ctx, module, requesterID, "request_limit_"+suffix, "root", "public", "secret", "nonce", "profile")
		require.NoError(t, err)
		request, created, err := testCreateFriendRequest(ctx, module, requesterID, requesterSpace.SpaceID, targetSpace.SpaceID, "share-key", requesterSpace.CurrentVersion)
		require.NoError(t, err)
		require.True(t, created)
		if i == 0 {
			firstRequestID = request.RequestID
		}
	}

	extraID := insertSpaceUser(t, module, "request-limit-extra@example.com", "request-limit-extra-public")
	extraSpace, err := testCreateSpace(ctx, module, extraID, "request_limit_extra", "root", "public", "secret", "nonce", "profile")
	require.NoError(t, err)
	_, _, err = testCreateFriendRequest(ctx, module, extraID, extraSpace.SpaceID, targetSpace.SpaceID, "share-key", extraSpace.CurrentVersion)
	require.ErrorIs(t, err, ErrSpaceFriendRequestLimitReached)

	require.NoError(t, module.Friends.DeleteFriendRequest(ctx, targetSpace.SpaceID, firstRequestID))
	_, created, err := testCreateFriendRequest(ctx, module, extraID, extraSpace.SpaceID, targetSpace.SpaceID, "share-key", extraSpace.CurrentVersion)
	require.NoError(t, err)
	require.True(t, created)
}

func testUpdateCaption(ctx context.Context, module *Module, postID int64, _ int64, spaceID string, captionCipher *string) error {
	var caption []byte
	if captionCipher != nil {
		caption = testSpaceBytes(*captionCipher)
	}
	return module.Posts.UpdateCaption(ctx, postID, spaceID, caption)
}

func insertSpaceUser(t *testing.T, module *Module, email string, publicKey string) int64 {
	t.Helper()
	userID := testutil.InsertUser(t, module.Spaces.DB, testutil.UserFixture{
		Email:        email,
		CreationTime: timeutil.Microseconds(),
	})
	_, err := module.Spaces.DB.Exec(`
		INSERT INTO key_attributes (
			user_id, kek_salt, kek_hash_bytes, encrypted_key, key_decryption_nonce,
			public_key, encrypted_secret_key, secret_key_decryption_nonce
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
	`, userID, "salt", []byte{1, 2, 3}, "encrypted-key", "nonce", publicKey, "encrypted-secret-key", "secret-nonce")
	require.NoError(t, err)
	return userID
}

func countSpaceRows(t *testing.T, module *Module, query string, args ...any) int64 {
	t.Helper()
	var count int64
	err := module.Spaces.DB.QueryRow(query, args...).Scan(&count)
	require.NoError(t, err)
	return count
}

func TestGetBrowserSession(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)
	userID := insertSpaceUser(t, module, "browser-session@example.com", "browser-session-public")
	tokenHash := sha256.Sum256([]byte("browser-session-token"))
	expiresAt := timeutil.NDaysFromNow(1)

	err := module.Sessions.CreateBrowserSession(ctx, tokenHash[:], userID, "session-wrap-key", expiresAt)
	require.NoError(t, err)

	session, err := module.Sessions.GetBrowserSession(ctx, tokenHash[:])
	require.NoError(t, err)
	require.Equal(t, userID, session.UserID)
	require.Equal(t, "session-wrap-key", session.SessionWrapKey)
	require.Equal(t, expiresAt, session.ExpiresAt)
}

func TestGetBrowserSessionRejectsDeletedUser(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)
	userID := insertSpaceUser(t, module, "deleted-browser-session@example.com", "deleted-browser-session-public")
	tokenHash := sha256.Sum256([]byte("deleted-browser-session-token"))

	require.NoError(t, module.Sessions.CreateBrowserSession(ctx, tokenHash[:], userID, "session-wrap-key", timeutil.NDaysFromNow(1)))
	_, err := module.Sessions.DB.Exec(`UPDATE users SET encrypted_email = NULL WHERE user_id = $1`, userID)
	require.NoError(t, err)

	_, err = module.Sessions.GetBrowserSession(ctx, tokenHash[:])
	require.ErrorIs(t, err, sql.ErrNoRows)
}

func TestExchangeBrowserSessionConsumesTokenOnce(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)
	userID := insertSpaceUser(t, module, "browser-session-exchange@example.com", "browser-session-exchange-public")
	authToken := "browser-session-exchange-token"
	_, err := module.Sessions.DB.Exec(`
		INSERT INTO tokens (user_id, token, creation_time, app)
		VALUES ($1, $2, $3, 'photos')
	`, userID, authToken, timeutil.Microseconds())
	require.NoError(t, err)

	start := make(chan struct{})
	errs := make(chan error, 2)
	for _, tokenHash := range [][]byte{[]byte("first-space-token-hash"), []byte("second-space-token-hash")} {
		go func(tokenHash []byte) {
			<-start
			errs <- module.Sessions.ExchangeBrowserSession(ctx, authToken, tokenHash, userID, "session-wrap-key", timeutil.NDaysFromNow(1))
		}(tokenHash)
	}
	close(start)

	var created, rejected int
	for range 2 {
		err := <-errs
		if err == nil {
			created++
		} else if errors.Is(err, ente.ErrAuthenticationRequired) {
			rejected++
		} else {
			require.NoError(t, err)
		}
	}
	require.Equal(t, 1, created)
	require.Equal(t, 1, rejected)
	require.Equal(t, int64(1), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_browser_sessions WHERE user_id = $1`, userID))
}

func TestExchangeBrowserSessionKeepsTokenWhenSessionCreationFails(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)
	userID := insertSpaceUser(t, module, "browser-session-rollback@example.com", "browser-session-rollback-public")
	authToken := "browser-session-rollback-token"
	tokenHash := []byte("duplicate-space-token-hash")
	_, err := module.Sessions.DB.Exec(`
		INSERT INTO tokens (user_id, token, creation_time, app)
		VALUES ($1, $2, $3, 'photos')
	`, userID, authToken, timeutil.Microseconds())
	require.NoError(t, err)
	require.NoError(t, module.Sessions.CreateBrowserSession(ctx, tokenHash, userID, "existing-wrap-key", timeutil.NDaysFromNow(1)))

	err = module.Sessions.ExchangeBrowserSession(ctx, authToken, tokenHash, userID, "new-wrap-key", timeutil.NDaysFromNow(1))
	require.Error(t, err)
	var isDeleted bool
	require.NoError(t, module.Sessions.DB.QueryRow(`SELECT is_deleted FROM tokens WHERE token = $1`, authToken).Scan(&isDeleted))
	require.False(t, isDeleted)
}

func TestSpaceAccountDeletionResetAccountDeletionAccess(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice-reset-space@example.com", "alice-reset-public")
	bobID := insertSpaceUser(t, module, "bob-reset-space@example.com", "bob-reset-public")
	charlieID := insertSpaceUser(t, module, "charlie-reset-space@example.com", "charlie-reset-public")
	aliceSpace, err := testCreateSpace(ctx, module, aliceID, "alice_reset_space", "alice-space-key", "alice-reset-public", "alice-secret", "alice-secret-nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, module, bobID, "bob_reset_space", "bob-space-key", "bob-reset-public", "bob-secret", "bob-secret-nonce", "bob-profile")
	require.NoError(t, err)
	charlieSpace, err := testCreateSpace(ctx, module, charlieID, "charlie_reset_space", "charlie-space-key", "charlie-reset-public", "charlie-secret", "charlie-secret-nonce", "charlie-profile")
	require.NoError(t, err)

	require.NoError(t, testAddFriend(ctx, module, bobID, bobSpace.SpaceID, aliceSpace.SpaceID, "alice-share-key", aliceSpace.CurrentVersion, "bob-share-key", bobSpace.CurrentVersion))
	pendingRequest, created, err := testCreateFriendRequest(ctx, module, aliceID, aliceSpace.SpaceID, charlieSpace.SpaceID, "alice-charlie-share-key", aliceSpace.CurrentVersion)
	require.NoError(t, err)
	require.True(t, created)
	require.NoError(t, module.Sessions.CreateBrowserSession(ctx, []byte("alice-browser-token"), aliceID, "session-wrap-key", timeutil.NDaysFromNow(1)))

	postID, err := testCreatePost(ctx, module, aliceID, aliceSpace.SpaceID, "alice-post-key", nil, aliceSpace.CurrentVersion, nil)
	require.NoError(t, err)
	require.NoError(t, testSetPostLike(ctx, module, postID, bobSpace.SpaceID, true))
	message, err := module.Messages.CreateMessage(ctx, CreateSpaceMessageRecord{
		Kind:                         "regular",
		SenderSpaceID:                bobSpace.SpaceID,
		RecipientSpaceID:             aliceSpace.SpaceID,
		MessageCipher:                testSpaceBytes("cipher"),
		SenderEncryptedMessageKey:    testSpaceBytes("sender-key"),
		RecipientEncryptedMessageKey: testSpaceBytes("recipient-key"),
	})
	require.NoError(t, err)
	require.NoError(t, module.Messages.SetLike(ctx, message.MessageID, aliceSpace.SpaceID, true))
	setMessageLikeCreatedAt(t, module, 1500, message.MessageID, aliceSpace.SpaceID)
	require.NoError(t, module.Read.UpsertNotificationReadMarker(ctx, aliceSpace.SpaceID, bobSpace.SpaceID, timeutil.Microseconds()))

	require.NoError(t, module.ResetAccountDeletionAccess(ctx, aliceID))

	require.Equal(t, int64(1), countSpaceRows(t, module, `SELECT COUNT(*) FROM spaces WHERE owner_id = $1`, aliceID))
	require.Equal(t, int64(1), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_posts WHERE space_id = $1`, aliceSpace.SpaceID))
	require.Equal(t, int64(0), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_browser_sessions WHERE user_id = $1`, aliceID))
	require.Equal(t, int64(2), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_friend_shares WHERE space_id = $1 OR friend_space_id = $1`, aliceSpace.SpaceID))
	require.Equal(t, int64(1), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_friend_requests WHERE requester_space_id = $1 OR target_space_id = $1`, aliceSpace.SpaceID))
	require.Equal(t, int64(2), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_notification_read_markers WHERE viewer_space_id = $1 OR friend_space_id = $1`, aliceSpace.SpaceID))
	require.Equal(t, int64(1), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_messages WHERE kind = 'post_like' AND reply_post_id = $1`, postID))
	require.Equal(t, int64(1), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_messages WHERE message_id = $1 AND recipient_liked_at IS NOT NULL`, message.MessageID))
	_, _, err = testConfirmFriendRequest(ctx, module, charlieID, charlieSpace.SpaceID, pendingRequest.RequestID, "charlie-share-key", charlieSpace.CurrentVersion)
	require.NoError(t, err)
	require.Equal(t, int64(2), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_friend_shares WHERE (space_id = $1 AND friend_space_id = $2) OR (space_id = $2 AND friend_space_id = $1)`, aliceSpace.SpaceID, charlieSpace.SpaceID))
}

func TestSpaceAccountDeletionDeleteUserData(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice-delete-space@example.com", "alice-delete-public")
	bobID := insertSpaceUser(t, module, "bob-delete-space@example.com", "bob-delete-public")
	aliceSpace, err := testCreateSpace(ctx, module, aliceID, "alice_delete_space", "alice-space-key", "alice-delete-public", "alice-secret", "alice-secret-nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, module, bobID, "bob_delete_space", "bob-space-key", "bob-delete-public", "bob-secret", "bob-secret-nonce", "bob-profile")
	require.NoError(t, err)

	_, err = module.Spaces.DB.Exec(`
		INSERT INTO space_profile_assets (space_id, asset_type, object_id, bucket_id, size, key_version)
		VALUES ($1, $2, $3, $4, 11, 1),
		       ($1, $5, $6, $7, 22, 1)
	`, aliceSpace.SpaceID, ProfileAssetTypeAvatar, "avatar", "hot", ProfileAssetTypeCover, "cover", "cold")
	require.NoError(t, err)
	postID, err := testCreatePost(ctx, module, aliceID, aliceSpace.SpaceID, "alice-post-key", nil, aliceSpace.CurrentVersion, nil)
	require.NoError(t, err)
	_, err = module.Posts.DB.Exec(`
		INSERT INTO space_post_assets (post_id, object_key, bucket_id, size, position, metadata_cipher)
		VALUES ($1, $2, $3, 33, 0, $4)
	`, postID, "space/alice/post-asset", "hot", "metadata")
	require.NoError(t, err)
	require.NoError(t, module.Assets.AddTempObject(ctx, SpaceTempObjectRecord{
		ObjectKey:    "space/alice/staged-upload",
		SpaceID:      sql.NullString{String: aliceSpace.SpaceID, Valid: true},
		Purpose:      TempObjectPurposePost,
		BucketID:     "hot",
		ExpectedSize: 44,
		ExpiresAt:    timeutil.NDaysFromNow(1),
	}))
	require.NoError(t, module.Sessions.CreateBrowserSession(ctx, []byte("alice-delete-browser-token"), aliceID, "session-wrap-key", timeutil.NDaysFromNow(1)))
	require.NoError(t, testAddFriend(ctx, module, bobID, bobSpace.SpaceID, aliceSpace.SpaceID, "alice-share-key", aliceSpace.CurrentVersion, "bob-share-key", bobSpace.CurrentVersion))
	message, err := module.Messages.CreateMessage(ctx, CreateSpaceMessageRecord{
		Kind:                         "regular",
		SenderSpaceID:                bobSpace.SpaceID,
		RecipientSpaceID:             aliceSpace.SpaceID,
		MessageCipher:                testSpaceBytes("cipher"),
		SenderEncryptedMessageKey:    testSpaceBytes("sender-key"),
		RecipientEncryptedMessageKey: testSpaceBytes("recipient-key"),
	})
	require.NoError(t, err)
	require.NoError(t, module.Messages.SetLike(ctx, message.MessageID, aliceSpace.SpaceID, true))
	require.NoError(t, testSetPostLike(ctx, module, postID, bobSpace.SpaceID, true))
	require.NoError(t, module.Read.UpsertNotificationReadMarker(ctx, aliceSpace.SpaceID, bobSpace.SpaceID, timeutil.Microseconds()))

	require.NoError(t, module.DeleteUserData(ctx, aliceID))

	require.Equal(t, int64(0), countSpaceRows(t, module, `SELECT COUNT(*) FROM spaces WHERE owner_id = $1`, aliceID))
	require.Equal(t, int64(0), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_posts WHERE space_id = $1`, aliceSpace.SpaceID))
	require.Equal(t, int64(0), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_post_assets WHERE object_key = $1`, "space/alice/post-asset"))
	require.Equal(t, int64(0), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_messages WHERE sender_space_id = $1 OR recipient_space_id = $1`, aliceSpace.SpaceID))
	require.Equal(t, int64(0), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_browser_sessions WHERE user_id = $1`, aliceID))
	require.Equal(t, int64(0), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_friend_shares WHERE space_id = $1 OR friend_space_id = $1`, aliceSpace.SpaceID))
	require.Equal(t, int64(0), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_notification_read_markers WHERE viewer_space_id = $1 OR friend_space_id = $1`, aliceSpace.SpaceID))

	for _, objectKey := range []string{ProfileAssetObjectKey(aliceSpace.SpaceID, ProfileAssetTypeAvatar, "avatar"), ProfileAssetObjectKey(aliceSpace.SpaceID, ProfileAssetTypeCover, "cover"), "space/alice/post-asset", "space/alice/staged-upload"} {
		require.Equal(t, int64(1), countSpaceRows(t, module, `
			SELECT COUNT(*)
			FROM space_temp_objects
			WHERE object_key = $1
			  AND space_id IS NULL
			  AND cleanup_after >= now_utc_micro_seconds() + $2
		`, objectKey, SpaceUploadURLExpiry.Microseconds()))
	}
}

func TestSpaceMessagesThreadAndConversations(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice-messages@example.com", "alice-public")
	bobID := insertSpaceUser(t, module, "bob-messages@example.com", "bob-public")

	aliceSpace, err := testCreateSpace(ctx, module, aliceID, "alice_messages", "alice-space-key", "alice-messages-public", "alice-messages-secret", "alice-messages-secret-nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, module, bobID, "bob_messages", "bob-space-key", "bob-messages-public", "bob-messages-secret", "bob-messages-secret-nonce", "bob-profile")
	require.NoError(t, err)

	err = testAddFriend(ctx, module, bobID, bobSpace.SpaceID, aliceSpace.SpaceID, "alice-share-key", aliceSpace.CurrentVersion, "bob-share-key", bobSpace.CurrentVersion)
	require.NoError(t, err)

	message, err := module.Messages.CreateMessage(ctx, CreateSpaceMessageRecord{
		Kind:                         "regular",
		SenderSpaceID:                bobSpace.SpaceID,
		RecipientSpaceID:             aliceSpace.SpaceID,
		MessageCipher:                testSpaceBytes("cipher"),
		SenderEncryptedMessageKey:    testSpaceBytes("sender-key"),
		RecipientEncryptedMessageKey: testSpaceBytes("recipient-key"),
	})
	require.NoError(t, err)
	require.Equal(t, "regular", message.Kind)
	require.Equal(t, testSpaceBytes("sender-key"), message.EncryptedMessageKey)
	require.False(t, message.Liked)
	require.False(t, message.ViewerLiked)

	require.NoError(t, module.Messages.SetLike(ctx, message.MessageID, aliceSpace.SpaceID, true))
	setMessageLikeCreatedAt(t, module, 1500, message.MessageID, aliceSpace.SpaceID)
	likedMessage, err := module.Messages.GetMessage(ctx, message.MessageID, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.True(t, likedMessage.Liked)
	require.True(t, likedMessage.ViewerLiked)
	bobViewedMessage, err := module.Messages.GetMessage(ctx, message.MessageID, bobSpace.SpaceID)
	require.NoError(t, err)
	require.True(t, bobViewedMessage.Liked)
	require.False(t, bobViewedMessage.ViewerLiked)

	reply, err := module.Messages.CreateMessage(ctx, CreateSpaceMessageRecord{
		Kind:                         "regular",
		SenderSpaceID:                aliceSpace.SpaceID,
		RecipientSpaceID:             bobSpace.SpaceID,
		MessageCipher:                testSpaceBytes("reply-cipher"),
		SenderEncryptedMessageKey:    testSpaceBytes("reply-sender-key"),
		RecipientEncryptedMessageKey: testSpaceBytes("reply-recipient-key"),
		ReplyMessageID:               sql.NullString{String: message.MessageID, Valid: true},
	})
	require.NoError(t, err)
	require.Equal(t, message.MessageID, reply.ReplyMessageID.String)
	setMessageCreatedAt(t, module, 1000, message.MessageID)
	setMessageCreatedAt(t, module, 2000, reply.MessageID)

	aliceThread, nextCursor, err := module.Messages.ListThread(ctx, aliceSpace.SpaceID, bobSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Empty(t, nextCursor)
	require.Len(t, aliceThread, 3)
	require.Equal(t, reply.MessageID, aliceThread[0].MessageID)
	require.Equal(t, message.MessageID, aliceThread[0].ReplyMessageID.String)
	require.Equal(t, testSpaceBytes("recipient-key"), aliceThread[1].EncryptedMessageKey)
	require.Equal(t, bobSpace.SpaceID, aliceThread[1].SenderSpaceID)
	require.Equal(t, aliceSpace.SpaceID, aliceThread[1].RecipientSpaceID)

	conversations, nextCursor, err := listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Empty(t, nextCursor)
	require.Len(t, conversations, 1)
	require.Equal(t, bobSpace.SpaceID, conversations[0].Friend.SpaceID)
	require.Equal(t, "message", conversations[0].LatestActivity.Type)
	require.Equal(t, reply.MessageID, conversations[0].LatestActivity.MessageID.String)

	require.NoError(t, module.Messages.DeleteMessage(ctx, message.MessageID, bobSpace.SpaceID))
	deletedMessage, err := module.Messages.GetMessage(ctx, message.MessageID, bobSpace.SpaceID)
	require.NoError(t, err)
	require.True(t, deletedMessage.IsDeleted)
	require.Empty(t, deletedMessage.MessageCipher)
	require.Empty(t, deletedMessage.EncryptedMessageKey)
	require.False(t, deletedMessage.Liked)
	aliceThread, nextCursor, err = module.Messages.ListThread(ctx, aliceSpace.SpaceID, bobSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Empty(t, nextCursor)
	require.Len(t, aliceThread, 2)
	require.Equal(t, reply.MessageID, aliceThread[0].MessageID)
	require.Equal(t, message.MessageID, aliceThread[0].ReplyMessageID.String)

	_, err = module.Messages.CreateMessage(ctx, CreateSpaceMessageRecord{
		Kind:                         "regular",
		SenderSpaceID:                bobSpace.SpaceID,
		RecipientSpaceID:             aliceSpace.SpaceID,
		MessageCipher:                testSpaceBytes("cipher"),
		SenderEncryptedMessageKey:    testSpaceBytes("sender-key"),
		RecipientEncryptedMessageKey: testSpaceBytes("recipient-key"),
		ReplyPostID:                  sql.NullInt64{Int64: 1, Valid: true},
	})
	require.Error(t, err)
}

func TestSpaceConversationsUseProfileAssetAvatars(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice-message-avatars@example.com", "alice-message-avatars-public")
	bobID := insertSpaceUser(t, module, "bob-message-avatars@example.com", "bob-message-avatars-public")

	aliceSpace, err := testCreateSpace(ctx, module, aliceID, "alice_message_avatars", "alice-space-key", "alice-message-avatars-public", "alice-secret", "alice-secret-nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, module, bobID, "bob_message_avatars", "bob-space-key", "bob-message-avatars-public", "bob-secret", "bob-secret-nonce", "bob-profile")
	require.NoError(t, err)
	_, err = module.Spaces.DB.Exec(`
		INSERT INTO space_profile_assets (space_id, asset_type, object_id, bucket_id, size, key_version)
		VALUES ($1, $2, $3, $4, 101, 1),
		       ($5, $2, $6, $4, 202, 1)
	`, aliceSpace.SpaceID, ProfileAssetTypeAvatar, "alice-avatar-object-id", "b2-eu-cen", bobSpace.SpaceID, "bob-avatar-object-id")
	require.NoError(t, err)
	require.NoError(t, testAddFriend(ctx, module, bobID, bobSpace.SpaceID, aliceSpace.SpaceID, "alice-share-key", aliceSpace.CurrentVersion, "bob-share-key", bobSpace.CurrentVersion))

	message, err := module.Messages.CreateMessage(ctx, CreateSpaceMessageRecord{
		Kind:                         "regular",
		SenderSpaceID:                bobSpace.SpaceID,
		RecipientSpaceID:             aliceSpace.SpaceID,
		MessageCipher:                testSpaceBytes("cipher"),
		SenderEncryptedMessageKey:    testSpaceBytes("sender-key"),
		RecipientEncryptedMessageKey: testSpaceBytes("recipient-key"),
	})
	require.NoError(t, err)
	setMessageCreatedAt(t, module, 1000, message.MessageID)

	thread, nextCursor, err := module.Messages.ListThread(ctx, aliceSpace.SpaceID, bobSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Empty(t, nextCursor)
	require.Len(t, thread, 2)
	require.Equal(t, bobSpace.SpaceID, thread[0].SenderSpaceID)
	require.Equal(t, aliceSpace.SpaceID, thread[0].RecipientSpaceID)

	conversations, nextCursor, err := listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Empty(t, nextCursor)
	require.Len(t, conversations, 1)
	require.Equal(t, "bob-avatar-object-id", conversations[0].Friend.AvatarObjectID.String)
	require.EqualValues(t, 202, conversations[0].Friend.AvatarSize.Int64)
	require.True(t, conversations[0].LatestActivity.MessageID.Valid)
}

func TestSpaceMessageConversationsUseLatestActivity(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice-activity@example.com", "alice-activity-public")
	bobID := insertSpaceUser(t, module, "bob-activity@example.com", "bob-activity-public")

	aliceSpace, err := testCreateSpace(ctx, module, aliceID, "alice_activity", "alice-space-key", "alice-activity-public", "alice-activity-secret", "alice-activity-secret-nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, module, bobID, "bob_activity", "bob-space-key", "bob-activity-public", "bob-activity-secret", "bob-activity-secret-nonce", "bob-profile")
	require.NoError(t, err)

	require.NoError(t, testAddFriend(ctx, module, bobID, bobSpace.SpaceID, aliceSpace.SpaceID, "alice-share-key", aliceSpace.CurrentVersion, "bob-share-key", bobSpace.CurrentVersion))

	conversations, nextCursor, err := listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Empty(t, nextCursor)
	require.Len(t, conversations, 1)
	require.Equal(t, bobSpace.SpaceID, conversations[0].Friend.SpaceID)
	require.Equal(t, "friend_added", conversations[0].LatestActivity.Type)
	require.True(t, conversations[0].LatestActivity.MessageID.Valid)
	require.False(t, conversations[0].Unread)
	require.Zero(t, conversations[0].UnreadCount)
	require.False(t, conversations[0].NotificationUnread)

	bobMessage, err := module.Messages.CreateMessage(ctx, CreateSpaceMessageRecord{
		Kind:                         "regular",
		SenderSpaceID:                bobSpace.SpaceID,
		RecipientSpaceID:             aliceSpace.SpaceID,
		MessageCipher:                testSpaceBytes("bob-message-cipher"),
		SenderEncryptedMessageKey:    testSpaceBytes("bob-message-sender-key"),
		RecipientEncryptedMessageKey: testSpaceBytes("bob-message-recipient-key"),
	})
	require.NoError(t, err)
	setMessageCreatedAt(t, module, 2000, bobMessage.MessageID)

	conversations, _, err = listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Equal(t, "message", conversations[0].LatestActivity.Type)
	require.Equal(t, bobMessage.MessageID, conversations[0].LatestActivity.MessageID.String)

	aliceMessage, err := module.Messages.CreateMessage(ctx, CreateSpaceMessageRecord{
		Kind:                         "regular",
		SenderSpaceID:                aliceSpace.SpaceID,
		RecipientSpaceID:             bobSpace.SpaceID,
		MessageCipher:                testSpaceBytes("alice-message-cipher"),
		SenderEncryptedMessageKey:    testSpaceBytes("alice-message-sender-key"),
		RecipientEncryptedMessageKey: testSpaceBytes("alice-message-recipient-key"),
	})
	require.NoError(t, err)
	setMessageCreatedAt(t, module, 2500, aliceMessage.MessageID)
	require.NoError(t, module.Messages.SetLike(ctx, aliceMessage.MessageID, bobSpace.SpaceID, true))
	setMessageLikeCreatedAt(t, module, 3000, aliceMessage.MessageID, bobSpace.SpaceID)
	require.NoError(t, module.Messages.SetLike(ctx, bobMessage.MessageID, aliceSpace.SpaceID, true))
	setMessageLikeCreatedAt(t, module, 3500, bobMessage.MessageID, aliceSpace.SpaceID)

	conversations, _, err = listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Equal(t, "message_like", conversations[0].LatestActivity.Type)
	require.True(t, conversations[0].LatestActivity.Outgoing)
	require.Equal(t, bobMessage.MessageID, conversations[0].LatestActivity.MessageID.String)
	require.Equal(t, testSpaceBytes("bob-message-cipher"), conversations[0].LatestActivity.MessageCipher)
	require.Equal(t, testSpaceBytes("bob-message-recipient-key"), conversations[0].LatestActivity.EncryptedMessageKey)

	postID, err := testCreatePost(ctx, module, aliceID, aliceSpace.SpaceID, "post-key", nil, aliceSpace.CurrentVersion, nil)
	require.NoError(t, err)
	_, err = module.Posts.DB.Exec(`
			INSERT INTO space_post_assets (post_id, object_key, bucket_id, metadata_cipher)
			VALUES ($1, $2, $3, $4)
		`, postID, "activity-post-object", "bucket", "metadata")
	require.NoError(t, err)
	require.NoError(t, testSetPostLike(ctx, module, postID, bobSpace.SpaceID, true))
	setPostLikeCreatedAt(t, module, 4000, postID, bobSpace.SpaceID)

	conversations, _, err = listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Equal(t, "post_like", conversations[0].LatestActivity.Type)
	require.True(t, conversations[0].LatestActivity.PostID.Valid)
	require.Equal(t, postID, conversations[0].LatestActivity.PostID.Int64)

	postReply, err := module.Messages.CreateMessage(ctx, CreateSpaceMessageRecord{
		Kind:                         "post_reply",
		SenderSpaceID:                bobSpace.SpaceID,
		RecipientSpaceID:             aliceSpace.SpaceID,
		MessageCipher:                testSpaceBytes("post-reply-cipher"),
		SenderEncryptedMessageKey:    testSpaceBytes("post-reply-sender-key"),
		RecipientEncryptedMessageKey: testSpaceBytes("post-reply-recipient-key"),
		ReplyPostID:                  sql.NullInt64{Int64: postID, Valid: true},
	})
	require.NoError(t, err)
	setMessageCreatedAt(t, module, 5000, postReply.MessageID)

	conversations, _, err = listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Equal(t, "post_reply", conversations[0].LatestActivity.Type)
	require.True(t, conversations[0].LatestActivity.MessageID.Valid)
	require.Equal(t, postReply.MessageID, conversations[0].LatestActivity.MessageID.String)
	require.Equal(t, postID, conversations[0].LatestActivity.PostID.Int64)

	replyOnlyPostID, err := testCreatePost(ctx, module, aliceID, aliceSpace.SpaceID, "reply-only-post-key", nil, aliceSpace.CurrentVersion, nil)
	require.NoError(t, err)
	replyOnly, err := module.Messages.CreateMessage(ctx, CreateSpaceMessageRecord{
		Kind:                         "post_reply",
		SenderSpaceID:                bobSpace.SpaceID,
		RecipientSpaceID:             aliceSpace.SpaceID,
		MessageCipher:                testSpaceBytes("reply-only-cipher"),
		SenderEncryptedMessageKey:    testSpaceBytes("reply-only-sender-key"),
		RecipientEncryptedMessageKey: testSpaceBytes("reply-only-recipient-key"),
		ReplyPostID:                  sql.NullInt64{Int64: replyOnlyPostID, Valid: true},
	})
	require.NoError(t, err)
	setMessageCreatedAt(t, module, 5500, replyOnly.MessageID)

	conversations, _, err = listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Equal(t, "post_reply", conversations[0].LatestActivity.Type)
	require.True(t, conversations[0].LatestActivity.MessageID.Valid)
	require.Equal(t, replyOnly.MessageID, conversations[0].LatestActivity.MessageID.String)
	require.Equal(t, replyOnlyPostID, conversations[0].LatestActivity.PostID.Int64)

	require.NoError(t, module.Posts.DeletePost(ctx, replyOnlyPostID, aliceSpace.SpaceID))

	conversations, _, err = listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Equal(t, "post_reply", conversations[0].LatestActivity.Type)
	require.True(t, conversations[0].LatestActivity.MessageID.Valid)
	require.Equal(t, replyOnly.MessageID, conversations[0].LatestActivity.MessageID.String)
	require.True(t, conversations[0].LatestActivity.PostID.Valid)
	require.Equal(t, replyOnlyPostID, conversations[0].LatestActivity.PostID.Int64)
	thread, _, err := module.Messages.ListThread(ctx, aliceSpace.SpaceID, bobSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Equal(t, replyOnly.MessageID, thread[0].MessageID)
	latestActivityAt, err := module.Read.GetLatestConversationActivityAt(ctx, aliceSpace.SpaceID, bobSpace.SpaceID)
	require.NoError(t, err)
	require.Equal(t, int64(5500), latestActivityAt)
	notificationsUnread, err := module.Read.HasUnreadNotifications(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.True(t, notificationsUnread)

	require.NoError(t, module.Friends.DeleteFriendship(ctx, bobSpace.SpaceID, aliceSpace.SpaceID))

	conversations, _, err = listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Empty(t, conversations)
}

func TestCurrentFriendsWithoutMessagesUseFriendAddedActivity(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice-empty-friend@example.com", "alice-empty-friend-public")
	bobID := insertSpaceUser(t, module, "bob-empty-friend@example.com", "bob-empty-friend-public")
	aliceSpace, err := testCreateSpace(ctx, module, aliceID, "alice_empty_friend", "alice-space-key", "alice-empty-friend-public", "alice-secret", "alice-secret-nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, module, bobID, "bob_empty_friend", "bob-space-key", "bob-empty-friend-public", "bob-secret", "bob-secret-nonce", "bob-profile")
	require.NoError(t, err)

	require.NoError(t, testAddFriend(ctx, module, bobID, bobSpace.SpaceID, aliceSpace.SpaceID, "alice-share-key", aliceSpace.CurrentVersion, "bob-share-key", bobSpace.CurrentVersion))
	setFriendShareCreatedAt(t, module, 1000, aliceSpace.SpaceID, bobSpace.SpaceID)
	setFriendShareCreatedAt(t, module, 1000, bobSpace.SpaceID, aliceSpace.SpaceID)

	conversations, nextCursor, err := listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Empty(t, nextCursor)
	require.Len(t, conversations, 1)
	require.Equal(t, bobSpace.SpaceID, conversations[0].Friend.SpaceID)
	require.Equal(t, "friend_added", conversations[0].LatestActivity.Type)
	require.Equal(t, int64(1), conversations[0].LatestActivity.CreatedAt)
	require.True(t, conversations[0].LatestActivity.MessageID.Valid)
	require.False(t, conversations[0].Unread)
	require.Zero(t, conversations[0].UnreadCount)
	require.False(t, conversations[0].NotificationUnread)

	latestActivityAt, err := module.Read.GetLatestConversationActivityAt(ctx, aliceSpace.SpaceID, bobSpace.SpaceID)
	require.NoError(t, err)
	require.Equal(t, int64(1), latestActivityAt)

	require.NoError(t, module.Friends.DeleteFriendship(ctx, aliceSpace.SpaceID, bobSpace.SpaceID))
	conversations, _, err = listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Empty(t, conversations)
}

func TestLatestChatSummariesUseCurrentFriendActivities(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice-chat-summary@example.com", "alice-chat-summary-public")
	bobID := insertSpaceUser(t, module, "bob-chat-summary@example.com", "bob-chat-summary-public")
	charlieID := insertSpaceUser(t, module, "charlie-chat-summary@example.com", "charlie-chat-summary-public")
	aliceSpace, err := testCreateSpace(ctx, module, aliceID, "alice_chat_summary", "alice-space-key", "alice-chat-summary-public", "alice-secret", "alice-secret-nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, module, bobID, "bob_chat_summary", "bob-space-key", "bob-chat-summary-public", "bob-secret", "bob-secret-nonce", "bob-profile")
	require.NoError(t, err)
	charlieSpace, err := testCreateSpace(ctx, module, charlieID, "charlie_chat_summary", "charlie-space-key", "charlie-chat-summary-public", "charlie-secret", "charlie-secret-nonce", "charlie-profile")
	require.NoError(t, err)
	require.NoError(t, testAddFriend(ctx, module, bobID, bobSpace.SpaceID, aliceSpace.SpaceID, "alice-bob-share-key", aliceSpace.CurrentVersion, "bob-alice-share-key", bobSpace.CurrentVersion))
	require.NoError(t, testAddFriend(ctx, module, charlieID, charlieSpace.SpaceID, aliceSpace.SpaceID, "alice-charlie-share-key", aliceSpace.CurrentVersion, "charlie-alice-share-key", charlieSpace.CurrentVersion))

	bobMessage, err := module.Messages.CreateMessage(ctx, CreateSpaceMessageRecord{
		Kind:                         "regular",
		SenderSpaceID:                bobSpace.SpaceID,
		RecipientSpaceID:             aliceSpace.SpaceID,
		MessageCipher:                testSpaceBytes("bob-summary-message-cipher"),
		SenderEncryptedMessageKey:    testSpaceBytes("bob-summary-message-sender-key"),
		RecipientEncryptedMessageKey: testSpaceBytes("bob-summary-message-recipient-key"),
	})
	require.NoError(t, err)
	setMessageCreatedAt(t, module, 2000, bobMessage.MessageID)
	postID, err := testCreatePost(ctx, module, aliceID, aliceSpace.SpaceID, "summary-post-key", nil, aliceSpace.CurrentVersion, nil)
	require.NoError(t, err)
	require.NoError(t, testSetPostLike(ctx, module, postID, bobSpace.SpaceID, true))
	setPostLikeCreatedAt(t, module, 3000, postID, bobSpace.SpaceID)

	summaries, err := module.Messages.ListLatestChatSummaries(ctx, aliceSpace.SpaceID, []string{bobSpace.SpaceID, charlieSpace.SpaceID})
	require.NoError(t, err)
	require.Len(t, summaries, 2)
	charlieSummary := summaries[charlieSpace.SpaceID]
	require.Equal(t, "friend_added", charlieSummary.LatestActivity.Type)
	require.Empty(t, charlieSummary.UnreadActivities)
	bobSummary := summaries[bobSpace.SpaceID]
	require.Equal(t, "post_like", bobSummary.LatestActivity.Type)
	require.True(t, bobSummary.LatestActivity.PostID.Valid)
	require.Equal(t, postID, bobSummary.LatestActivity.PostID.Int64)
	require.Len(t, bobSummary.UnreadActivities, 2)
	for _, activity := range bobSummary.UnreadActivities {
		require.Empty(t, activity.MessageCipher)
		require.Empty(t, activity.EncryptedMessageKey)
	}
	require.Equal(t, int64(1), countChatUnreadActivities(bobSummary.UnreadActivities))

	require.NoError(t, module.Read.UpsertNotificationReadMarker(ctx, aliceSpace.SpaceID, bobSpace.SpaceID, 3000))
	summaries, err = module.Messages.ListLatestChatSummaries(ctx, aliceSpace.SpaceID, []string{bobSpace.SpaceID, charlieSpace.SpaceID})
	require.NoError(t, err)
	bobSummary = summaries[bobSpace.SpaceID]
	require.Empty(t, bobSummary.UnreadActivities)
	require.Equal(t, "post_like", bobSummary.LatestActivity.Type)

	require.NoError(t, module.Friends.DeleteFriendship(ctx, aliceSpace.SpaceID, bobSpace.SpaceID))
	notificationsUnread, err := module.Read.HasUnreadNotifications(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.False(t, notificationsUnread)
}

func TestConfirmFriendRequestCreatesFriendshipAndNotifiesRequester(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice-confirm-request@example.com", "alice-confirm-request-public")
	bobID := insertSpaceUser(t, module, "bob-confirm-request@example.com", "bob-confirm-request-public")
	aliceSpace, err := testCreateSpace(ctx, module, aliceID, "alice_confirm_request", "alice-space-key", "alice-confirm-request-public", "alice-confirm-secret", "alice-confirm-secret-nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, module, bobID, "bob_confirm_request", "bob-space-key", "bob-confirm-request-public", "bob-confirm-secret", "bob-confirm-secret-nonce", "bob-profile")
	require.NoError(t, err)

	request, created, err := testCreateFriendRequest(ctx, module, bobID, bobSpace.SpaceID, aliceSpace.SpaceID, "bob-share-key", bobSpace.CurrentVersion)
	require.NoError(t, err)
	require.True(t, created)
	aliceUnread, err := module.Read.HasUnreadNotifications(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.True(t, aliceUnread)

	requesterID, created, err := testConfirmFriendRequest(ctx, module, aliceID, aliceSpace.SpaceID, request.RequestID, "alice-share-key", aliceSpace.CurrentVersion)
	require.NoError(t, err)
	require.True(t, created)
	require.Equal(t, bobID, requesterID)

	aliceShare, err := module.Friends.GetShareForFriendAndSpace(ctx, aliceSpace.SpaceID, bobSpace.SpaceID)
	require.NoError(t, err)
	require.Equal(t, testSpaceBytes("bob-share-key"), aliceShare.FriendSealedSpaceKey)
	bobShare, err := module.Friends.GetShareForFriendAndSpace(ctx, bobSpace.SpaceID, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.Equal(t, testSpaceBytes("alice-share-key"), bobShare.FriendSealedSpaceKey)
	requests, err := module.Friends.ListFriendRequestsForSpace(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.Empty(t, requests)
	aliceUnread, err = module.Read.HasUnreadNotifications(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.False(t, aliceUnread)
	bobRequests, err := module.Friends.ListFriendRequestsForSpace(ctx, bobSpace.SpaceID)
	require.NoError(t, err)
	require.Empty(t, bobRequests)
	bobUnread, err := module.Read.HasUnreadNotifications(ctx, bobSpace.SpaceID)
	require.NoError(t, err)
	require.True(t, bobUnread)
	aliceConversations, _, err := listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Len(t, aliceConversations, 1)
	require.Equal(t, bobSpace.SpaceID, aliceConversations[0].Friend.SpaceID)
	require.Equal(t, "friend_added", aliceConversations[0].LatestActivity.Type)
	require.False(t, aliceConversations[0].NotificationUnread)
	require.False(t, aliceConversations[0].Unread)
	require.Zero(t, aliceConversations[0].UnreadCount)
	bobConversations, _, err := listTestConversations(ctx, module, bobSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Len(t, bobConversations, 1)
	require.Equal(t, aliceSpace.SpaceID, bobConversations[0].Friend.SpaceID)
	require.Equal(t, "friend_added", bobConversations[0].LatestActivity.Type)
	require.True(t, bobConversations[0].NotificationUnread)
	require.False(t, bobConversations[0].Unread)
	require.Zero(t, bobConversations[0].UnreadCount)
	require.Len(t, bobConversations[0].UnreadActivities, 1)
}

func TestReciprocalFriendRequestAutoConfirms(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice-reciprocal-request@example.com", "alice-reciprocal-request-public")
	bobID := insertSpaceUser(t, module, "bob-reciprocal-request@example.com", "bob-reciprocal-request-public")
	aliceSpace, err := testCreateSpace(ctx, module, aliceID, "alice_reciprocal_request", "alice-space-key", "alice-reciprocal-request-public", "alice-reciprocal-secret", "alice-reciprocal-secret-nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, module, bobID, "bob_reciprocal_request", "bob-space-key", "bob-reciprocal-request-public", "bob-reciprocal-secret", "bob-reciprocal-secret-nonce", "bob-profile")
	require.NoError(t, err)

	_, created, autoConfirmed, err := module.Friends.CreateFriendRequest(ctx, bobID, bobSpace.SpaceID, aliceSpace.SpaceID, testSpaceBytes("bob-share-key"), bobSpace.CurrentVersion)
	require.NoError(t, err)
	require.True(t, created)
	require.False(t, autoConfirmed)
	_, created, autoConfirmed, err = module.Friends.CreateFriendRequest(ctx, aliceID, aliceSpace.SpaceID, bobSpace.SpaceID, testSpaceBytes("alice-share-key"), aliceSpace.CurrentVersion)
	require.NoError(t, err)
	require.False(t, created)
	require.True(t, autoConfirmed)

	aliceShare, err := module.Friends.GetShareForFriendAndSpace(ctx, aliceSpace.SpaceID, bobSpace.SpaceID)
	require.NoError(t, err)
	require.Equal(t, testSpaceBytes("bob-share-key"), aliceShare.FriendSealedSpaceKey)
	bobShare, err := module.Friends.GetShareForFriendAndSpace(ctx, bobSpace.SpaceID, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.Equal(t, testSpaceBytes("alice-share-key"), bobShare.FriendSealedSpaceKey)
	aliceRequests, err := module.Friends.ListFriendRequestsForSpace(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.Empty(t, aliceRequests)
	bobRequests, err := module.Friends.ListFriendRequestsForSpace(ctx, bobSpace.SpaceID)
	require.NoError(t, err)
	require.Empty(t, bobRequests)
	aliceUnread, err := module.Read.HasUnreadNotifications(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.False(t, aliceUnread)
	bobUnread, err := module.Read.HasUnreadNotifications(ctx, bobSpace.SpaceID)
	require.NoError(t, err)
	require.True(t, bobUnread)
}

func TestDeleteFriendRequestClearsUnread(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice-delete-request@example.com", "alice-delete-request-public")
	bobID := insertSpaceUser(t, module, "bob-delete-request@example.com", "bob-delete-request-public")
	aliceSpace, err := testCreateSpace(ctx, module, aliceID, "alice_delete_request", "alice-space-key", "alice-delete-request-public", "alice-delete-secret", "alice-delete-secret-nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, module, bobID, "bob_delete_request", "bob-space-key", "bob-delete-request-public", "bob-delete-secret", "bob-delete-secret-nonce", "bob-profile")
	require.NoError(t, err)

	request, created, err := testCreateFriendRequest(ctx, module, bobID, bobSpace.SpaceID, aliceSpace.SpaceID, "bob-share-key", bobSpace.CurrentVersion)
	require.NoError(t, err)
	require.True(t, created)
	aliceUnread, err := module.Read.HasUnreadNotifications(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.True(t, aliceUnread)

	require.NoError(t, module.Friends.DeleteFriendRequest(ctx, aliceSpace.SpaceID, request.RequestID))
	aliceUnread, err = module.Read.HasUnreadNotifications(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.False(t, aliceUnread)
	requests, err := module.Friends.ListFriendRequestsForSpace(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.Empty(t, requests)
}

func TestFriendRequestsStayOutOfMessageConversations(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice-request-conversation@example.com", "alice-request-conversation-public")
	bobID := insertSpaceUser(t, module, "bob-request-conversation@example.com", "bob-request-conversation-public")
	aliceSpace, err := testCreateSpace(ctx, module, aliceID, "alice_request_conversation", "alice-space-key", "alice-request-conversation-public", "alice-request-secret", "alice-request-secret-nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, module, bobID, "bob_request_conversation", "bob-space-key", "bob-request-conversation-public", "bob-request-secret", "bob-request-secret-nonce", "bob-profile")
	require.NoError(t, err)

	request, created, err := testCreateFriendRequest(ctx, module, bobID, bobSpace.SpaceID, aliceSpace.SpaceID, "bob-share-key-v2", bobSpace.CurrentVersion)
	require.NoError(t, err)
	require.True(t, created)
	setFriendRequestCreatedAt(t, module, 2000, request.RequestID)

	conversations, _, err := listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Empty(t, conversations)
	requests, err := module.Friends.ListFriendRequestsForSpace(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.Len(t, requests, 1)
	require.Equal(t, request.RequestID, requests[0].RequestID)
	require.Equal(t, bobSpace.SpaceID, requests[0].Requester.SpaceID)
	notificationsUnread, err := module.Read.HasUnreadNotifications(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.True(t, notificationsUnread)

	require.NoError(t, module.Friends.DeleteFriendRequest(ctx, aliceSpace.SpaceID, request.RequestID))
	conversations, _, err = listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Empty(t, conversations)
	notificationsUnread, err = module.Read.HasUnreadNotifications(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.False(t, notificationsUnread)
}

func TestSpaceMessageConversationPreviewUsesLatestActivityWithSeparateUnreadState(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice-preview-priority@example.com", "alice-preview-public")
	bobID := insertSpaceUser(t, module, "bob-preview-priority@example.com", "bob-preview-public")
	aliceSpace, err := testCreateSpace(ctx, module, aliceID, "alice_preview_priority", "alice-space-key", "alice-preview-priority-public", "alice-preview-priority-secret", "alice-preview-priority-secret-nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, module, bobID, "bob_preview_priority", "bob-space-key", "bob-preview-priority-public", "bob-preview-priority-secret", "bob-preview-priority-secret-nonce", "bob-profile")
	require.NoError(t, err)
	require.NoError(t, testAddFriend(ctx, module, bobID, bobSpace.SpaceID, aliceSpace.SpaceID, "alice-share-key", aliceSpace.CurrentVersion, "bob-share-key", bobSpace.CurrentVersion))

	aliceOldMessage, err := module.Messages.CreateMessage(ctx, CreateSpaceMessageRecord{
		Kind:                         "regular",
		SenderSpaceID:                aliceSpace.SpaceID,
		RecipientSpaceID:             bobSpace.SpaceID,
		MessageCipher:                testSpaceBytes("alice-old-cipher"),
		SenderEncryptedMessageKey:    testSpaceBytes("alice-old-sender-key"),
		RecipientEncryptedMessageKey: testSpaceBytes("alice-old-recipient-key"),
	})
	require.NoError(t, err)
	setMessageCreatedAt(t, module, 1000, aliceOldMessage.MessageID)
	bobNewMessage, err := module.Messages.CreateMessage(ctx, CreateSpaceMessageRecord{
		Kind:                         "regular",
		SenderSpaceID:                bobSpace.SpaceID,
		RecipientSpaceID:             aliceSpace.SpaceID,
		MessageCipher:                testSpaceBytes("bob-new-cipher"),
		SenderEncryptedMessageKey:    testSpaceBytes("bob-new-sender-key"),
		RecipientEncryptedMessageKey: testSpaceBytes("bob-new-recipient-key"),
	})
	require.NoError(t, err)
	setMessageCreatedAt(t, module, 2000, bobNewMessage.MessageID)
	require.NoError(t, module.Messages.SetLike(ctx, aliceOldMessage.MessageID, bobSpace.SpaceID, true))
	setMessageLikeCreatedAt(t, module, 3000, aliceOldMessage.MessageID, bobSpace.SpaceID)

	conversations, _, err := listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Len(t, conversations, 1)
	require.True(t, conversations[0].Unread)
	require.True(t, conversations[0].NotificationUnread)
	require.Equal(t, "message_like", conversations[0].LatestActivity.Type)
	require.Equal(t, aliceOldMessage.MessageID, conversations[0].LatestActivity.MessageID.String)
	require.Equal(t, testSpaceBytes("alice-old-cipher"), conversations[0].LatestActivity.MessageCipher)
	require.Equal(t, testSpaceBytes("alice-old-sender-key"), conversations[0].LatestActivity.EncryptedMessageKey)
	require.Equal(t, int64(3000), conversations[0].SortCreatedAt)

	latestActivityAt, err := module.Read.GetLatestConversationActivityAt(ctx, aliceSpace.SpaceID, bobSpace.SpaceID)
	require.NoError(t, err)
	require.Equal(t, int64(3000), latestActivityAt)
	require.NoError(t, module.Read.UpsertNotificationReadMarker(ctx, aliceSpace.SpaceID, bobSpace.SpaceID, latestActivityAt))

	conversations, _, err = listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.False(t, conversations[0].Unread)
	require.False(t, conversations[0].NotificationUnread)
	require.Equal(t, "message_like", conversations[0].LatestActivity.Type)
	require.Equal(t, aliceOldMessage.MessageID, conversations[0].LatestActivity.MessageID.String)
}

func TestPostLikeUnreadCountSuppression(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice-post-like-unread@example.com", "alice-post-like-unread-public")
	bobID := insertSpaceUser(t, module, "bob-post-like-unread@example.com", "bob-post-like-unread-public")
	aliceSpace, err := testCreateSpace(ctx, module, aliceID, "alice_post_like_unread", "alice-space-key", "alice-post-like-unread-public", "alice-post-like-unread-secret", "alice-post-like-unread-secret-nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, module, bobID, "bob_post_like_unread", "bob-space-key", "bob-post-like-unread-public", "bob-post-like-unread-secret", "bob-post-like-unread-secret-nonce", "bob-profile")
	require.NoError(t, err)
	require.NoError(t, testAddFriend(ctx, module, bobID, bobSpace.SpaceID, aliceSpace.SpaceID, "alice-share-key", aliceSpace.CurrentVersion, "bob-share-key", bobSpace.CurrentVersion))

	aliceMessage, err := module.Messages.CreateMessage(ctx, CreateSpaceMessageRecord{
		Kind:                         "regular",
		SenderSpaceID:                aliceSpace.SpaceID,
		RecipientSpaceID:             bobSpace.SpaceID,
		MessageCipher:                testSpaceBytes("alice-message-cipher"),
		SenderEncryptedMessageKey:    testSpaceBytes("alice-message-sender-key"),
		RecipientEncryptedMessageKey: testSpaceBytes("alice-message-recipient-key"),
	})
	require.NoError(t, err)
	setMessageCreatedAt(t, module, 1000, aliceMessage.MessageID)

	firstPostID, err := testCreatePost(ctx, module, aliceID, aliceSpace.SpaceID, "first-post-key", nil, aliceSpace.CurrentVersion, nil)
	require.NoError(t, err)
	secondPostID, err := testCreatePost(ctx, module, aliceID, aliceSpace.SpaceID, "second-post-key", nil, aliceSpace.CurrentVersion, nil)
	require.NoError(t, err)
	thirdPostID, err := testCreatePost(ctx, module, aliceID, aliceSpace.SpaceID, "third-post-key", nil, aliceSpace.CurrentVersion, nil)
	require.NoError(t, err)

	require.NoError(t, testSetPostLike(ctx, module, firstPostID, bobSpace.SpaceID, true))
	setPostLikeCreatedAt(t, module, 2000, firstPostID, bobSpace.SpaceID)
	conversations, _, err := listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Len(t, conversations, 1)
	require.Equal(t, "post_like", conversations[0].LatestActivity.Type)
	require.False(t, conversations[0].Unread)
	require.Equal(t, int64(0), conversations[0].UnreadCount)
	require.True(t, conversations[0].NotificationUnread)

	require.NoError(t, testSetPostLike(ctx, module, secondPostID, bobSpace.SpaceID, true))
	setPostLikeCreatedAt(t, module, 3000, secondPostID, bobSpace.SpaceID)
	conversations, _, err = listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Equal(t, "post_like", conversations[0].LatestActivity.Type)
	require.False(t, conversations[0].Unread)
	require.Equal(t, int64(0), conversations[0].UnreadCount)
	require.True(t, conversations[0].NotificationUnread)

	latestActivityAt, err := module.Read.GetLatestConversationActivityAt(ctx, aliceSpace.SpaceID, bobSpace.SpaceID)
	require.NoError(t, err)
	require.Equal(t, int64(3000), latestActivityAt)
	require.NoError(t, module.Read.UpsertNotificationReadMarker(ctx, aliceSpace.SpaceID, bobSpace.SpaceID, latestActivityAt))
	require.NoError(t, testSetPostLike(ctx, module, thirdPostID, bobSpace.SpaceID, true))
	setPostLikeCreatedAt(t, module, 4000, thirdPostID, bobSpace.SpaceID)
	conversations, _, err = listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Equal(t, "post_like", conversations[0].LatestActivity.Type)
	require.False(t, conversations[0].Unread)
	require.Equal(t, int64(0), conversations[0].UnreadCount)
	require.True(t, conversations[0].NotificationUnread)

	require.NoError(t, module.Messages.SetLike(ctx, aliceMessage.MessageID, bobSpace.SpaceID, true))
	setMessageLikeCreatedAt(t, module, 5000, aliceMessage.MessageID, bobSpace.SpaceID)
	conversations, _, err = listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Equal(t, "message_like", conversations[0].LatestActivity.Type)
	require.False(t, conversations[0].Unread)
	require.Equal(t, int64(0), conversations[0].UnreadCount)
	require.True(t, conversations[0].NotificationUnread)

	latestActivityAt, err = module.Read.GetLatestConversationActivityAt(ctx, aliceSpace.SpaceID, bobSpace.SpaceID)
	require.NoError(t, err)
	require.Equal(t, int64(5000), latestActivityAt)
	require.NoError(t, module.Read.UpsertNotificationReadMarker(ctx, aliceSpace.SpaceID, bobSpace.SpaceID, latestActivityAt))
	secondAliceMessage, err := module.Messages.CreateMessage(ctx, CreateSpaceMessageRecord{
		Kind:                         "regular",
		SenderSpaceID:                aliceSpace.SpaceID,
		RecipientSpaceID:             bobSpace.SpaceID,
		MessageCipher:                testSpaceBytes("second-alice-message-cipher"),
		SenderEncryptedMessageKey:    testSpaceBytes("second-alice-message-sender-key"),
		RecipientEncryptedMessageKey: testSpaceBytes("second-alice-message-recipient-key"),
	})
	require.NoError(t, err)
	setMessageCreatedAt(t, module, 6000, secondAliceMessage.MessageID)
	require.NoError(t, module.Messages.SetLike(ctx, secondAliceMessage.MessageID, bobSpace.SpaceID, true))
	setMessageLikeCreatedAt(t, module, 7000, secondAliceMessage.MessageID, bobSpace.SpaceID)
	conversations, _, err = listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Equal(t, "message_like", conversations[0].LatestActivity.Type)
	require.False(t, conversations[0].Unread)
	require.Equal(t, int64(0), conversations[0].UnreadCount)
	require.True(t, conversations[0].NotificationUnread)
}

func TestSpaceModuleLifecycle(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice@example.com", "alice-public")
	bobID := insertSpaceUser(t, module, "bob@example.com", "bob-public")

	aliceSpace, err := testCreateSpace(ctx, module, aliceID, "alice", "alice-space-key", "alice-public", "alice-secret", "alice-secret-nonce", "alice-profile")
	require.NoError(t, err)
	require.Equal(t, 1, aliceSpace.CurrentVersion)

	bobSpace, err := testCreateSpace(ctx, module, bobID, "bob", "bob-space-key", "bob-public", "bob-secret", "bob-secret-nonce", "bob-profile")
	require.NoError(t, err)

	listedSpaces, err := module.Spaces.ListSpacesByOwner(ctx, aliceID)
	require.NoError(t, err)
	require.Len(t, listedSpaces, 1)

	err = module.Assets.AddTempObject(ctx, SpaceTempObjectRecord{
		ObjectKey:    ProfileAssetObjectKey(aliceSpace.SpaceID, ProfileAssetTypeAvatar, "avatar.jpg"),
		SpaceID:      sql.NullString{String: aliceSpace.SpaceID, Valid: true},
		Purpose:      TempObjectPurposeAvatar,
		BucketID:     "b2-eu-cen",
		ExpectedSize: 111,
		ExpiresAt:    timeutil.MicrosecondsAfterMinutes(30),
	})
	require.NoError(t, err)
	updatedSpace, err := testUpdateProfile(ctx, module, aliceID, aliceSpace.SpaceID, aliceSpace.CurrentVersion, "alice-profile-v2", &ProfileAssetUpdate{
		ObjectID: "avatar.jpg",
		BucketID: "b2-eu-cen",
		Size:     111,
	}, nil, false, false)
	require.NoError(t, err)
	require.Equal(t, testSpaceBytes("alice-profile-v2"), updatedSpace.EncryptedProfile)
	require.Equal(t, "avatar.jpg", updatedSpace.AvatarObjectID.String)
	avatarBucketID, err := module.Assets.GetProfileAssetBucketID(ctx, aliceSpace.SpaceID, ProfileAssetTypeAvatar, "avatar.jpg")
	require.NoError(t, err)
	require.Equal(t, "b2-eu-cen", avatarBucketID)

	rotatedSpace, err := testRotateKey(ctx, module, aliceID, aliceSpace.SpaceID, updatedSpace.CurrentVersion, "alice-space-key-v2", "wrapped-prev-key", "alice-profile-v3")
	require.NoError(t, err)
	require.Equal(t, 2, rotatedSpace.CurrentVersion)
	require.Equal(t, sql.NullInt64{Int64: 1, Valid: true}, rotatedSpace.AvatarKeyVersion)

	versions, err := module.Spaces.ListVersions(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.Len(t, versions, 2)

	err = testAddFriend(ctx, module, bobID, bobSpace.SpaceID, aliceSpace.SpaceID, "alice-share-key", rotatedSpace.CurrentVersion, "bob-share-key", bobSpace.CurrentVersion)
	require.NoError(t, err)

	shares, err := module.Friends.ListSharesForFriendAndSpace(ctx, bobSpace.SpaceID)
	require.NoError(t, err)
	require.Len(t, shares, 1)
	require.Equal(t, testSpaceBytes("alice-share-key"), shares[0].FriendSealedSpaceKey)

	aliceShares, err := module.Friends.ListSharesForFriendAndSpace(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.Len(t, aliceShares, 1)
	require.Equal(t, testSpaceBytes("bob-share-key"), aliceShares[0].FriendSealedSpaceKey)

	friends, err := module.Friends.ListFriendsForSpace(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.Len(t, friends, 1)
	require.Equal(t, "bob", friends[0].Friend.SpaceSlug)

	bobFriends, err := module.Friends.ListFriendsForSpace(ctx, bobSpace.SpaceID)
	require.NoError(t, err)
	require.Len(t, bobFriends, 1)
	require.Equal(t, "alice", bobFriends[0].Friend.SpaceSlug)
	require.Equal(t, sql.NullInt64{Int64: 1, Valid: true}, bobFriends[0].Friend.AvatarKeyVersion)

	for _, tempObject := range []SpaceTempObjectRecord{
		{
			ObjectKey:    "space/alice/post1/full",
			SpaceID:      sql.NullString{String: aliceSpace.SpaceID, Valid: true},
			Purpose:      TempObjectPurposePost,
			BucketID:     "b2-eu-cen",
			ExpectedSize: 123,
			ExpiresAt:    timeutil.MicrosecondsAfterMinutes(30),
		},
		{
			ObjectKey:    "space/alice/post1/thumb",
			SpaceID:      sql.NullString{String: aliceSpace.SpaceID, Valid: true},
			Purpose:      TempObjectPurposePost,
			BucketID:     "b2-eu-cen",
			ExpectedSize: 45,
			ExpiresAt:    timeutil.MicrosecondsAfterMinutes(30),
		},
	} {
		err = module.Assets.AddTempObject(ctx, tempObject)
		require.NoError(t, err)
	}
	postID, err := testCreatePost(ctx, module, aliceID, aliceSpace.SpaceID, "post-key", ptr("caption"), rotatedSpace.CurrentVersion, []SpacePostAssetRecord{
		{
			ObjectKey:      "space/alice/post1/full",
			BucketID:       "b2-eu-cen",
			Size:           sqlNullInt64(123),
			Position:       0,
			MetadataCipher: testSpaceBytes("full-metadata"),
		},
		{
			ObjectKey:      "space/alice/post1/thumb",
			BucketID:       "b2-eu-cen",
			Size:           sqlNullInt64(45),
			Position:       1,
			MetadataCipher: testSpaceBytes("thumbnail-metadata"),
		},
	})
	require.NoError(t, err)

	post, err := module.Posts.GetPost(ctx, postID, bobSpace.SpaceID)
	require.NoError(t, err)
	require.Equal(t, "alice", post.Author.SpaceSlug)

	err = testSetPostLike(ctx, module, postID, bobSpace.SpaceID, true)
	require.NoError(t, err)

	assets, err := module.Posts.ListAssetsByPostIDs(ctx, []int64{postID})
	require.NoError(t, err)
	require.Len(t, assets[postID], 2)
	require.Equal(t, "b2-eu-cen", assets[postID][0].BucketID)

	bucketID, err := module.Assets.GetAssetBucketID(ctx, aliceSpace.SpaceID, "space/alice/post1/full")
	require.NoError(t, err)
	require.Equal(t, "b2-eu-cen", bucketID)

	bucketID, err = module.Assets.GetAssetBucketID(ctx, aliceSpace.SpaceID, ProfileAssetObjectKey(aliceSpace.SpaceID, ProfileAssetTypeAvatar, "avatar.jpg"))
	require.NoError(t, err)
	require.Equal(t, "b2-eu-cen", bucketID)

	tx, err := module.Assets.DB.BeginTx(ctx, nil)
	require.NoError(t, err)
	referenced, err := IsObjectReferencedTx(ctx, tx, "space/alice/post1/full")
	require.NoError(t, err)
	require.True(t, referenced)
	require.NoError(t, tx.Rollback())

	require.NoError(t, module.Posts.DeletePost(ctx, postID, aliceSpace.SpaceID))
	requireQueuedTempObject(t, module, "space/alice/post1/full", TempObjectPurposePost, "b2-eu-cen")
	requireQueuedTempObject(t, module, "space/alice/post1/thumb", TempObjectPurposePost, "b2-eu-cen")
	var likeCount int
	err = module.Posts.DB.QueryRow(`SELECT COUNT(*) FROM space_messages WHERE kind = 'post_like' AND reply_post_id = $1`, postID).Scan(&likeCount)
	require.NoError(t, err)
	require.Equal(t, 1, likeCount)

	require.NoError(t, module.Posts.DeletePost(ctx, postID, aliceSpace.SpaceID))
	err = module.Posts.DB.QueryRow(`SELECT COUNT(*) FROM space_messages WHERE kind = 'post_like' AND reply_post_id = $1`, postID).Scan(&likeCount)
	require.NoError(t, err)
	require.Equal(t, 1, likeCount)

	_, err = module.Posts.GetPost(ctx, postID, bobSpace.SpaceID)
	require.Error(t, err)

	err = testUpdateCaption(ctx, module, postID, aliceID, aliceSpace.SpaceID, ptr("edited-caption"))
	require.ErrorIs(t, err, sql.ErrNoRows)

	_, err = module.Assets.GetAssetBucketID(ctx, aliceSpace.SpaceID, "space/alice/post1/full")
	require.Error(t, err)

	tx, err = module.Assets.DB.BeginTx(ctx, nil)
	require.NoError(t, err)
	referenced, err = IsObjectReferencedTx(ctx, tx, "space/alice/post1/full")
	require.NoError(t, err)
	require.False(t, referenced)
	require.NoError(t, tx.Rollback())

	lookup, err := module.Spaces.GetSpaceBySlug(ctx, "alice")
	require.NoError(t, err)
	require.Equal(t, aliceSpace.SpaceID, lookup.SpaceID)

	_ = bobSpace
}

func TestReserveTempObjectEnforcesCountAtomically(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)
	userID := insertSpaceUser(t, module, "upload-count@example.com", "upload-count-public")
	space, err := testCreateSpace(ctx, module, userID, "upload_count", "root", "public", "secret", "nonce", "profile")
	require.NoError(t, err)

	start := make(chan struct{})
	errs := make(chan error, MaxActiveUploadCount*2)
	var wg sync.WaitGroup
	for i := 0; i < MaxActiveUploadCount*2; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			<-start
			errs <- module.Assets.ReserveTempObject(ctx, SpaceTempObjectRecord{
				ObjectKey:    "space/upload-count/" + strconv.Itoa(i),
				SpaceID:      sql.NullString{String: space.SpaceID, Valid: true},
				Purpose:      TempObjectPurposePost,
				BucketID:     "b2-eu-cen",
				ExpectedSize: 1,
				ExpiresAt:    timeutil.MicrosecondsAfterMinutes(30),
			})
		}(i)
	}
	close(start)
	wg.Wait()
	close(errs)

	accepted := 0
	rejected := 0
	for err := range errs {
		switch {
		case err == nil:
			accepted++
		case errors.Is(err, ErrSpaceUploadLimitReached):
			rejected++
		default:
			require.NoError(t, err)
		}
	}
	require.Equal(t, MaxActiveUploadCount, accepted)
	require.Equal(t, MaxActiveUploadCount, rejected)
	require.Equal(t, int64(MaxActiveUploadCount), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_temp_objects WHERE space_id = $1`, space.SpaceID))
}

func TestPostAssetPositionIsUnique(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice-assets@example.com", "alice-public")
	aliceSpace, err := testCreateSpace(ctx, module, aliceID, "alice_assets", "alice-space-key", "alice-assets-public", "alice-assets-secret", "alice-assets-secret-nonce", "alice-profile")
	require.NoError(t, err)
	postID, err := testCreatePost(ctx, module, aliceID, aliceSpace.SpaceID, "post-key", nil, aliceSpace.CurrentVersion, nil)
	require.NoError(t, err)

	_, err = module.Posts.DB.Exec(`
			INSERT INTO space_post_assets (post_id, object_key, bucket_id, position, metadata_cipher)
			VALUES ($1, $2, $3, $4, $5)
		`, postID, "space/alice-assets/post/full-1", "b2-eu-cen", 0, "metadata-1")
	require.NoError(t, err)
	_, err = module.Posts.DB.Exec(`
			INSERT INTO space_post_assets (post_id, object_key, bucket_id, position, metadata_cipher)
			VALUES ($1, $2, $3, $4, $5)
		`, postID, "space/alice-assets/post/full-2", "b2-eu-cen", 0, "metadata-2")

	require.Error(t, err)
}

func TestUpdateProfileQueuesOldAvatarForCleanup(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice@example.com", "alice-public")
	space, err := testCreateSpace(ctx, module, aliceID, "alice", "alice-space-key", "alice-public", "alice-secret", "alice-secret-nonce", "alice-profile")
	require.NoError(t, err)

	for _, rec := range []SpaceTempObjectRecord{
		{
			ObjectKey:    ProfileAssetObjectKey(space.SpaceID, ProfileAssetTypeAvatar, "avatar-old"),
			SpaceID:      sql.NullString{String: space.SpaceID, Valid: true},
			Purpose:      TempObjectPurposeAvatar,
			BucketID:     "b2-eu-cen",
			ExpectedSize: 111,
			ExpiresAt:    timeutil.MicrosecondsAfterMinutes(30),
		},
		{
			ObjectKey:    ProfileAssetObjectKey(space.SpaceID, ProfileAssetTypeAvatar, "avatar-new"),
			SpaceID:      sql.NullString{String: space.SpaceID, Valid: true},
			Purpose:      TempObjectPurposeAvatar,
			BucketID:     "b2-us-west",
			ExpectedSize: 222,
			ExpiresAt:    timeutil.MicrosecondsAfterMinutes(30),
		},
	} {
		require.NoError(t, module.Assets.AddTempObject(ctx, rec))
	}

	oldAvatar := &ProfileAssetUpdate{ObjectID: "avatar-old", BucketID: "b2-eu-cen", Size: 111}
	_, err = testUpdateProfile(ctx, module, aliceID, space.SpaceID, space.CurrentVersion, "alice-profile-old-avatar", oldAvatar, nil, false, false)
	require.NoError(t, err)
	require.Equal(t, int64(1), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_profile_assets WHERE space_id = $1 AND asset_type = $2 AND object_id = $3`, space.SpaceID, ProfileAssetTypeAvatar, "avatar-old"))

	newAvatar := &ProfileAssetUpdate{ObjectID: "avatar-new", BucketID: "b2-us-west", Size: 222}
	updated, err := testUpdateProfile(ctx, module, aliceID, space.SpaceID, space.CurrentVersion, "alice-profile-new-avatar", newAvatar, nil, false, false)
	require.NoError(t, err)
	require.Equal(t, "avatar-new", updated.AvatarObjectID.String)
	require.Equal(t, int64(0), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_profile_assets WHERE space_id = $1 AND asset_type = $2 AND object_id = $3`, space.SpaceID, ProfileAssetTypeAvatar, "avatar-old"))
	require.Equal(t, int64(1), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_profile_assets WHERE space_id = $1 AND asset_type = $2 AND object_id = $3`, space.SpaceID, ProfileAssetTypeAvatar, "avatar-new"))
	requireQueuedTempObject(t, module, ProfileAssetObjectKey(space.SpaceID, ProfileAssetTypeAvatar, "avatar-old"), TempObjectPurposeAvatar, "b2-eu-cen")

	updated, err = testUpdateProfile(ctx, module, aliceID, space.SpaceID, space.CurrentVersion, "alice-profile-no-avatar", nil, nil, true, false)
	require.NoError(t, err)
	require.False(t, updated.AvatarObjectID.Valid)
	require.Equal(t, int64(0), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_profile_assets WHERE space_id = $1 AND asset_type = $2`, space.SpaceID, ProfileAssetTypeAvatar))
	requireQueuedTempObject(t, module, ProfileAssetObjectKey(space.SpaceID, ProfileAssetTypeAvatar, "avatar-new"), TempObjectPurposeAvatar, "b2-us-west")
}

func TestUpdateProfileQueuesOldCoverForCleanup(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice-cover@example.com", "alice-public")
	space, err := testCreateSpace(ctx, module, aliceID, "alice_cover", "alice-space-key", "alice-cover-public", "alice-cover-secret", "alice-cover-secret-nonce", "alice-profile")
	require.NoError(t, err)

	for _, rec := range []SpaceTempObjectRecord{
		{
			ObjectKey:    ProfileAssetObjectKey(space.SpaceID, ProfileAssetTypeCover, "cover-old"),
			SpaceID:      sql.NullString{String: space.SpaceID, Valid: true},
			Purpose:      TempObjectPurposeCover,
			BucketID:     "b2-eu-cen",
			ExpectedSize: 333,
			ExpiresAt:    timeutil.MicrosecondsAfterMinutes(30),
		},
		{
			ObjectKey:    ProfileAssetObjectKey(space.SpaceID, ProfileAssetTypeCover, "cover-new"),
			SpaceID:      sql.NullString{String: space.SpaceID, Valid: true},
			Purpose:      TempObjectPurposeCover,
			BucketID:     "b2-us-west",
			ExpectedSize: 444,
			ExpiresAt:    timeutil.MicrosecondsAfterMinutes(30),
		},
	} {
		require.NoError(t, module.Assets.AddTempObject(ctx, rec))
	}

	oldCover := &ProfileAssetUpdate{ObjectID: "cover-old", BucketID: "b2-eu-cen", Size: 333}
	_, err = testUpdateProfile(ctx, module, aliceID, space.SpaceID, space.CurrentVersion, "alice-profile-old-cover", nil, oldCover, false, false)
	require.NoError(t, err)
	require.Equal(t, int64(1), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_profile_assets WHERE space_id = $1 AND asset_type = $2 AND object_id = $3`, space.SpaceID, ProfileAssetTypeCover, "cover-old"))

	newCover := &ProfileAssetUpdate{ObjectID: "cover-new", BucketID: "b2-us-west", Size: 444}
	updated, err := testUpdateProfile(ctx, module, aliceID, space.SpaceID, space.CurrentVersion, "alice-profile-new-cover", nil, newCover, false, false)
	require.NoError(t, err)
	require.Equal(t, "cover-new", updated.CoverObjectID.String)
	require.Equal(t, int64(0), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_profile_assets WHERE space_id = $1 AND asset_type = $2 AND object_id = $3`, space.SpaceID, ProfileAssetTypeCover, "cover-old"))
	require.Equal(t, int64(1), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_profile_assets WHERE space_id = $1 AND asset_type = $2 AND object_id = $3`, space.SpaceID, ProfileAssetTypeCover, "cover-new"))
	requireQueuedTempObject(t, module, ProfileAssetObjectKey(space.SpaceID, ProfileAssetTypeCover, "cover-old"), TempObjectPurposeCover, "b2-eu-cen")

	updated, err = testUpdateProfile(ctx, module, aliceID, space.SpaceID, space.CurrentVersion, "alice-profile-no-cover", nil, nil, false, true)
	require.NoError(t, err)
	require.False(t, updated.CoverObjectID.Valid)
	require.Equal(t, int64(0), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_profile_assets WHERE space_id = $1 AND asset_type = $2`, space.SpaceID, ProfileAssetTypeCover))
	requireQueuedTempObject(t, module, ProfileAssetObjectKey(space.SpaceID, ProfileAssetTypeCover, "cover-new"), TempObjectPurposeCover, "b2-us-west")
}

func TestAddFriendCreatesReciprocalShares(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice@example.com", "alice-public")
	bobID := insertSpaceUser(t, module, "bob@example.com", "bob-public")
	aliceSpace, err := testCreateSpace(ctx, module, aliceID, "alice", "alice-space-key", "alice-public", "alice-secret", "alice-secret-nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, module, bobID, "bob", "bob-space-key", "bob-public", "bob-secret", "bob-secret-nonce", "bob-profile")
	require.NoError(t, err)

	err = testAddFriend(ctx, module, bobID, bobSpace.SpaceID, aliceSpace.SpaceID, "alice-share-key", aliceSpace.CurrentVersion, "bob-share-key", bobSpace.CurrentVersion)
	require.NoError(t, err)

	share, err := module.Friends.GetShareForFriendAndSpace(ctx, bobSpace.SpaceID, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.Equal(t, testSpaceBytes("alice-share-key"), share.FriendSealedSpaceKey)
	require.Equal(t, aliceSpace.CurrentVersion, share.KeyVersion)

	reciprocalShare, err := module.Friends.GetShareForFriendAndSpace(ctx, aliceSpace.SpaceID, bobSpace.SpaceID)
	require.NoError(t, err)
	require.Equal(t, testSpaceBytes("bob-share-key"), reciprocalShare.FriendSealedSpaceKey)
	require.Equal(t, bobSpace.CurrentVersion, reciprocalShare.KeyVersion)

}

func TestAddFriendRejectsSelfFriendship(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice-self@example.com", "alice-public")
	aliceSpace, err := testCreateSpace(ctx, module, aliceID, "alice_self", "alice-space-key", "alice-self-public", "alice-self-secret", "alice-self-secret-nonce", "alice-profile")
	require.NoError(t, err)

	err = testAddFriend(ctx, module, aliceID, aliceSpace.SpaceID, aliceSpace.SpaceID, "alice-share-key", aliceSpace.CurrentVersion, "alice-share-key", aliceSpace.CurrentVersion)

	require.ErrorIs(t, err, ErrSelfFriendship)
}

func TestCreateFriendRequestRejectsExistingFriends(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice@example.com", "alice-public")
	bobID := insertSpaceUser(t, module, "bob@example.com", "bob-public")
	aliceSpace, err := testCreateSpace(ctx, module, aliceID, "alice", "alice-space-key", "alice-public", "alice-secret", "alice-secret-nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, module, bobID, "bob", "bob-space-key", "bob-public", "bob-secret", "bob-secret-nonce", "bob-profile")
	require.NoError(t, err)
	err = testAddFriend(ctx, module, bobID, bobSpace.SpaceID, aliceSpace.SpaceID, "alice-share-key", aliceSpace.CurrentVersion, "bob-share-key", bobSpace.CurrentVersion)
	require.NoError(t, err)

	err = testAddFriend(ctx, module, bobID, bobSpace.SpaceID, aliceSpace.SpaceID, "alice-share-key-v2", aliceSpace.CurrentVersion, "bob-share-key-v2", bobSpace.CurrentVersion)

	require.ErrorIs(t, err, ErrAlreadyFriends)
	share, err := module.Friends.GetShareForFriendAndSpace(ctx, bobSpace.SpaceID, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.Equal(t, testSpaceBytes("alice-share-key"), share.FriendSealedSpaceKey)
}

func TestDeleteFriendshipRemovesReciprocalShares(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice-delete-friend@example.com", "alice-public")
	bobID := insertSpaceUser(t, module, "bob-delete-friend@example.com", "bob-public")
	aliceSpace, err := testCreateSpace(ctx, module, aliceID, "alice_delete_friend", "alice-space-key", "alice-delete-friend-public", "alice-delete-friend-secret", "alice-delete-friend-secret-nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, module, bobID, "bob_delete_friend", "bob-space-key", "bob-delete-friend-public", "bob-delete-friend-secret", "bob-delete-friend-secret-nonce", "bob-profile")
	require.NoError(t, err)

	err = testAddFriend(ctx, module, aliceID, aliceSpace.SpaceID, bobSpace.SpaceID, "bob-share-key", bobSpace.CurrentVersion, "alice-share-key", aliceSpace.CurrentVersion)
	require.NoError(t, err)

	aliceShares, err := module.Friends.ListSharesForFriendAndSpace(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.Len(t, aliceShares, 1)
	bobShares, err := module.Friends.ListSharesForFriendAndSpace(ctx, bobSpace.SpaceID)
	require.NoError(t, err)
	require.Len(t, bobShares, 1)

	err = module.Friends.DeleteFriendship(ctx, aliceSpace.SpaceID, bobSpace.SpaceID)
	require.NoError(t, err)

	aliceShares, err = module.Friends.ListSharesForFriendAndSpace(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.Empty(t, aliceShares)
	bobShares, err = module.Friends.ListSharesForFriendAndSpace(ctx, bobSpace.SpaceID)
	require.NoError(t, err)
	require.Empty(t, bobShares)
	aliceFriends, err := module.Friends.ListFriendsForSpace(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.Empty(t, aliceFriends)
	bobFriends, err := module.Friends.ListFriendsForSpace(ctx, bobSpace.SpaceID)
	require.NoError(t, err)
	require.Empty(t, bobFriends)
	relationship, err := module.Friends.GetRelationship(ctx, aliceSpace.SpaceID, bobSpace.SpaceID)
	require.NoError(t, err)
	require.Empty(t, relationship)

	err = module.Friends.DeleteFriendship(ctx, aliceSpace.SpaceID, bobSpace.SpaceID)
	require.NoError(t, err)
}

func TestUpdateShareOnlyRefreshesExistingShares(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice@example.com", "alice-public")
	bobID := insertSpaceUser(t, module, "bob@example.com", "bob-public")
	aliceSpace, err := testCreateSpace(ctx, module, aliceID, "alice", "alice-space-key", "alice-public", "alice-secret", "alice-secret-nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, module, bobID, "bob", "bob-space-key", "bob-public", "bob-secret", "bob-secret-nonce", "bob-profile")
	require.NoError(t, err)

	err = testUpsertShare(ctx, module, aliceSpace.SpaceID, bobSpace.SpaceID, "share-key-v1", aliceSpace.CurrentVersion)
	require.NoError(t, err)

	rotatedSpace, err := testRotateKey(ctx, module, aliceID, aliceSpace.SpaceID, aliceSpace.CurrentVersion, "alice-space-key-v2", "wrapped-prev-key", "alice-profile-v2")
	require.NoError(t, err)

	err = testUpdateShare(ctx, module, aliceSpace.SpaceID, bobSpace.SpaceID, "share-key-v2", rotatedSpace.CurrentVersion)
	require.NoError(t, err)
	share, err := module.Friends.GetShareForFriendAndSpace(ctx, bobSpace.SpaceID, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.Equal(t, testSpaceBytes("share-key-v2"), share.FriendSealedSpaceKey)
	require.Equal(t, rotatedSpace.CurrentVersion, share.KeyVersion)

	err = deleteShareBySpaceAndFriend(ctx, module, aliceSpace.SpaceID, bobSpace.SpaceID)
	require.NoError(t, err)
	err = testUpdateShare(ctx, module, aliceSpace.SpaceID, bobSpace.SpaceID, "stale-share-key", rotatedSpace.CurrentVersion)
	require.ErrorIs(t, err, sql.ErrNoRows)

	_, err = module.Friends.GetShareForFriendAndSpace(ctx, bobSpace.SpaceID, aliceSpace.SpaceID)
	require.ErrorIs(t, err, sql.ErrNoRows)
}

func TestCreatePostRejectsStaleKeyVersion(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice@example.com", "alice-public")
	space, err := testCreateSpace(ctx, module, aliceID, "alice", "alice-space-key", "alice-public", "alice-secret", "alice-secret-nonce", "alice-profile")
	require.NoError(t, err)
	_, err = testRotateKey(ctx, module, aliceID, space.SpaceID, space.CurrentVersion, "alice-space-key-v2", "wrapped-prev-key", "alice-profile-v2")
	require.NoError(t, err)

	postID, err := testCreatePost(ctx, module, aliceID, space.SpaceID, "post-key-stale", nil, space.CurrentVersion, nil)
	require.Zero(t, postID)
	require.ErrorIs(t, err, sql.ErrNoRows)

	posts, next, err := module.Posts.ListPostsBySpace(ctx, space.SpaceID, space.SpaceID, "", 20)
	require.NoError(t, err)
	require.Empty(t, next)
	require.Empty(t, posts)
}

func TestUpdateProfileRejectsStaleKeyVersion(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice@example.com", "alice-public")
	space, err := testCreateSpace(ctx, module, aliceID, "alice", "alice-space-key-v1", "alice-public", "alice-secret", "alice-secret-nonce", "alice-profile-v1")
	require.NoError(t, err)

	rotated, err := testRotateKey(ctx, module, aliceID, space.SpaceID, space.CurrentVersion, "alice-space-key-v2", "wrapped-prev-key", "alice-profile-v2")
	require.NoError(t, err)
	require.Equal(t, 2, rotated.CurrentVersion)

	_, err = testUpdateProfile(ctx, module, aliceID, space.SpaceID, space.CurrentVersion, "stale-profile", nil, nil, false, false)
	require.ErrorIs(t, err, sql.ErrNoRows)

	current, err := module.Spaces.GetSpaceByID(ctx, space.SpaceID)
	require.NoError(t, err)
	require.Equal(t, rotated.CurrentVersion, current.CurrentVersion)
	require.Equal(t, testSpaceBytes("alice-profile-v2"), current.EncryptedProfile)
}

func TestRotateKeyRejectsStaleKeyVersion(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice@example.com", "alice-public")
	space, err := testCreateSpace(ctx, module, aliceID, "alice", "alice-space-key-v1", "alice-public", "alice-secret", "alice-secret-nonce", "alice-profile-v1")
	require.NoError(t, err)

	rotated, err := testRotateKey(ctx, module, aliceID, space.SpaceID, space.CurrentVersion, "alice-space-key-v2", "wrapped-v1", "alice-profile-v2")
	require.NoError(t, err)
	require.Equal(t, 2, rotated.CurrentVersion)

	_, err = testRotateKey(ctx, module, aliceID, space.SpaceID, space.CurrentVersion, "alice-space-key-v3", "stale-wrapped-v1", "alice-profile-v3")
	require.ErrorIs(t, err, sql.ErrNoRows)

	current, err := module.Spaces.GetSpaceByID(ctx, space.SpaceID)
	require.NoError(t, err)
	require.Equal(t, 2, current.CurrentVersion)
	require.Equal(t, testSpaceBytes("alice-space-key-v2"), current.RootWrappedSpaceKey)

	versions, err := module.Spaces.ListVersions(ctx, space.SpaceID)
	require.NoError(t, err)
	require.Len(t, versions, 2)
}

func TestAddFriendRejectsStaleKeyVersion(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice@example.com", "alice-public")
	bobID := insertSpaceUser(t, module, "bob@example.com", "bob-public")
	aliceSpace, err := testCreateSpace(ctx, module, aliceID, "alice", "alice-space-key", "alice-public", "alice-secret", "alice-secret-nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, module, bobID, "bob", "bob-space-key", "bob-public", "bob-secret", "bob-secret-nonce", "bob-profile")
	require.NoError(t, err)
	_, err = testRotateKey(ctx, module, aliceID, aliceSpace.SpaceID, aliceSpace.CurrentVersion, "alice-space-key-v2", "wrapped-prev-key", "alice-profile-v2")
	require.NoError(t, err)

	err = testAddFriend(ctx, module, bobID, bobSpace.SpaceID, aliceSpace.SpaceID, "stale-share-key", aliceSpace.CurrentVersion, "bob-share-key", bobSpace.CurrentVersion)
	require.ErrorIs(t, err, sql.ErrNoRows)

	_, err = module.Friends.GetShareForFriendAndSpace(ctx, bobSpace.SpaceID, aliceSpace.SpaceID)
	require.ErrorIs(t, err, sql.ErrNoRows)
	_, err = module.Friends.GetShareForFriendAndSpace(ctx, aliceSpace.SpaceID, bobSpace.SpaceID)
	require.ErrorIs(t, err, sql.ErrNoRows)
}

func TestUpdateShareRejectsStaleKeyVersion(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice@example.com", "alice-public")
	bobID := insertSpaceUser(t, module, "bob@example.com", "bob-public")
	aliceSpace, err := testCreateSpace(ctx, module, aliceID, "alice", "alice-space-key", "alice-public", "alice-secret", "alice-secret-nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, module, bobID, "bob", "bob-space-key", "bob-public", "bob-secret", "bob-secret-nonce", "bob-profile")
	require.NoError(t, err)
	err = testUpsertShare(ctx, module, aliceSpace.SpaceID, bobSpace.SpaceID, "share-key-v1", aliceSpace.CurrentVersion)
	require.NoError(t, err)
	_, err = testRotateKey(ctx, module, aliceID, aliceSpace.SpaceID, aliceSpace.CurrentVersion, "alice-space-key-v2", "wrapped-prev-key", "alice-profile-v2")
	require.NoError(t, err)

	err = testUpdateShare(ctx, module, aliceSpace.SpaceID, bobSpace.SpaceID, "stale-share-key", aliceSpace.CurrentVersion)
	require.ErrorIs(t, err, sql.ErrNoRows)

	share, err := module.Friends.GetShareForFriendAndSpace(ctx, bobSpace.SpaceID, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.Equal(t, testSpaceBytes("share-key-v1"), share.FriendSealedSpaceKey)
	require.Equal(t, aliceSpace.CurrentVersion, share.KeyVersion)
}

func TestGetVersionReturnsHistoricalProfile(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice@example.com", "alice-public")
	space, err := testCreateSpace(ctx, module, aliceID, "alice", "alice-space-key-v1", "alice-public", "alice-secret", "alice-secret-nonce", "alice-profile-v1")
	require.NoError(t, err)
	rotated, err := testRotateKey(ctx, module, aliceID, space.SpaceID, space.CurrentVersion, "alice-space-key-v2", "wrapped-prev-key", "alice-profile-v2")
	require.NoError(t, err)
	require.Equal(t, 2, rotated.CurrentVersion)

	v1, err := module.Spaces.GetVersion(ctx, space.SpaceID, 1)
	require.NoError(t, err)
	require.Equal(t, 1, v1.Version)
	require.Equal(t, testSpaceBytes("alice-profile-v1"), v1.EncryptedProfile)

	v2, err := module.Spaces.GetVersion(ctx, space.SpaceID, 2)
	require.NoError(t, err)
	require.Equal(t, 2, v2.Version)
	require.Equal(t, testSpaceBytes("alice-profile-v2"), v2.EncryptedProfile)
}

func TestListPostsBySpacePaginates(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice@example.com", "alice-public")
	space, err := testCreateSpace(ctx, module, aliceID, "alice", "alice-space-key", "alice-public", "alice-secret", "alice-secret-nonce", "alice-profile")
	require.NoError(t, err)
	first, err := testCreatePost(ctx, module, aliceID, space.SpaceID, "post-key-1", nil, space.CurrentVersion, nil)
	require.NoError(t, err)
	second, err := testCreatePost(ctx, module, aliceID, space.SpaceID, "post-key-2", nil, space.CurrentVersion, nil)
	require.NoError(t, err)
	third, err := testCreatePost(ctx, module, aliceID, space.SpaceID, "post-key-3", nil, space.CurrentVersion, nil)
	require.NoError(t, err)
	setPostCreatedAt(t, module, 1000, first, second, third)

	page, nextCursor, err := module.Posts.ListPostsBySpace(ctx, space.SpaceID, space.SpaceID, "", 2)
	require.NoError(t, err)
	require.Len(t, page, 2)
	require.Equal(t, third, page[0].PostID)
	require.Equal(t, second, page[1].PostID)
	require.Equal(t, "1000:"+strconv.FormatInt(second, 10), nextCursor)

	page, nextCursor, err = module.Posts.ListPostsBySpace(ctx, space.SpaceID, space.SpaceID, nextCursor, 2)
	require.NoError(t, err)
	require.Len(t, page, 1)
	require.Equal(t, first, page[0].PostID)
	require.Empty(t, nextCursor)
}

func TestListPostsBySpaceCursorUsesCreatedAtSortOrder(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice@example.com", "alice-public")
	space, err := testCreateSpace(ctx, module, aliceID, "alice", "alice-space-key", "alice-public", "alice-secret", "alice-secret-nonce", "alice-profile")
	require.NoError(t, err)
	first, err := testCreatePost(ctx, module, aliceID, space.SpaceID, "post-key-1", nil, space.CurrentVersion, nil)
	require.NoError(t, err)
	second, err := testCreatePost(ctx, module, aliceID, space.SpaceID, "post-key-2", nil, space.CurrentVersion, nil)
	require.NoError(t, err)
	third, err := testCreatePost(ctx, module, aliceID, space.SpaceID, "post-key-3", nil, space.CurrentVersion, nil)
	require.NoError(t, err)
	setPostCreatedAt(t, module, 3000, first)
	setPostCreatedAt(t, module, 2000, second)
	setPostCreatedAt(t, module, 1000, third)

	page, nextCursor, err := module.Posts.ListPostsBySpace(ctx, space.SpaceID, space.SpaceID, "", 1)
	require.NoError(t, err)
	require.Len(t, page, 1)
	require.Equal(t, first, page[0].PostID)
	require.Equal(t, "3000:"+strconv.FormatInt(first, 10), nextCursor)

	page, nextCursor, err = module.Posts.ListPostsBySpace(ctx, space.SpaceID, space.SpaceID, nextCursor, 1)
	require.NoError(t, err)
	require.Len(t, page, 1)
	require.Equal(t, second, page[0].PostID)
	require.Equal(t, "2000:"+strconv.FormatInt(second, 10), nextCursor)
}

func TestListFeedCursorUsesCreatedAtSortOrder(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice@example.com", "alice-public")
	bobID := insertSpaceUser(t, module, "bob@example.com", "bob-public")
	charlieID := insertSpaceUser(t, module, "charlie@example.com", "charlie-public")
	aliceSpace, err := testCreateSpace(ctx, module, aliceID, "alice", "alice-space-key", "alice-public", "alice-secret", "alice-secret-nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, module, bobID, "bob", "bob-space-key", "bob-public", "bob-secret", "bob-secret-nonce", "bob-profile")
	require.NoError(t, err)
	charlieSpace, err := testCreateSpace(ctx, module, charlieID, "charlie", "charlie-space-key", "charlie-public", "charlie-secret", "charlie-secret-nonce", "charlie-profile")
	require.NoError(t, err)
	err = testAddFriend(ctx, module, aliceID, aliceSpace.SpaceID, bobSpace.SpaceID, "bob-share-key", bobSpace.CurrentVersion, "alice-share-key", aliceSpace.CurrentVersion)
	require.NoError(t, err)

	ownPost, err := testCreatePost(ctx, module, aliceID, aliceSpace.SpaceID, "own-post-key", nil, aliceSpace.CurrentVersion, nil)
	require.NoError(t, err)
	unrelatedPost, err := testCreatePost(ctx, module, charlieID, charlieSpace.SpaceID, "unrelated-post-key", nil, charlieSpace.CurrentVersion, nil)
	require.NoError(t, err)
	first, err := testCreatePost(ctx, module, bobID, bobSpace.SpaceID, "post-key-1", nil, bobSpace.CurrentVersion, nil)
	require.NoError(t, err)
	second, err := testCreatePost(ctx, module, bobID, bobSpace.SpaceID, "post-key-2", nil, bobSpace.CurrentVersion, nil)
	require.NoError(t, err)
	third, err := testCreatePost(ctx, module, bobID, bobSpace.SpaceID, "post-key-3", nil, bobSpace.CurrentVersion, nil)
	require.NoError(t, err)
	setPostCreatedAt(t, module, 5000, ownPost)
	setPostCreatedAt(t, module, 4000, unrelatedPost)
	setPostCreatedAt(t, module, 3000, first)
	setPostCreatedAt(t, module, 2000, second)
	setPostCreatedAt(t, module, 1000, third)

	page, nextCursor, err := module.Posts.ListFeed(ctx, aliceSpace.SpaceID, "", 1)
	require.NoError(t, err)
	require.Len(t, page, 1)
	require.Equal(t, ownPost, page[0].PostID)
	require.Equal(t, aliceSpace.SpaceID, page[0].SpaceID)
	require.False(t, page[0].ViewerLiked)
	require.Equal(t, "5000:"+strconv.FormatInt(ownPost, 10), nextCursor)

	page, nextCursor, err = module.Posts.ListFeed(ctx, aliceSpace.SpaceID, nextCursor, 1)
	require.NoError(t, err)
	require.Len(t, page, 1)
	require.Equal(t, first, page[0].PostID)
	require.Equal(t, "3000:"+strconv.FormatInt(first, 10), nextCursor)

	page, nextCursor, err = module.Posts.ListFeed(ctx, aliceSpace.SpaceID, nextCursor, 1)
	require.NoError(t, err)
	require.Len(t, page, 1)
	require.Equal(t, second, page[0].PostID)
	require.Equal(t, "2000:"+strconv.FormatInt(second, 10), nextCursor)

	page, nextCursor, err = module.Posts.ListFeed(ctx, aliceSpace.SpaceID, nextCursor, 1)
	require.NoError(t, err)
	require.Len(t, page, 1)
	require.Equal(t, third, page[0].PostID)
	require.Empty(t, nextCursor)
}

func TestSpaceReadMarkersDriveNotificationState(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice-unread@example.com", "alice-unread-public")
	bobID := insertSpaceUser(t, module, "bob-unread@example.com", "bob-unread-public")
	aliceSpace, err := testCreateSpace(ctx, module, aliceID, "alice_unread", "alice-space-key", "alice-unread-public", "alice-unread-secret", "alice-unread-secret-nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, module, bobID, "bob_unread", "bob-space-key", "bob-unread-public", "bob-unread-secret", "bob-unread-secret-nonce", "bob-profile")
	require.NoError(t, err)
	require.NoError(t, testAddFriend(ctx, module, bobID, bobSpace.SpaceID, aliceSpace.SpaceID, "alice-share-key", aliceSpace.CurrentVersion, "bob-share-key", bobSpace.CurrentVersion))

	incoming, err := module.Messages.CreateMessage(ctx, CreateSpaceMessageRecord{
		Kind:                         "regular",
		SenderSpaceID:                bobSpace.SpaceID,
		RecipientSpaceID:             aliceSpace.SpaceID,
		MessageCipher:                testSpaceBytes("incoming-cipher"),
		SenderEncryptedMessageKey:    testSpaceBytes("incoming-sender-key"),
		RecipientEncryptedMessageKey: testSpaceBytes("incoming-recipient-key"),
	})
	require.NoError(t, err)
	setMessageCreatedAt(t, module, 2000, incoming.MessageID)
	conversations, _, err := listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Len(t, conversations, 1)
	require.True(t, conversations[0].Unread)
	require.Equal(t, int64(1), conversations[0].UnreadCount)
	notificationsUnread, err := module.Read.HasUnreadNotifications(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.True(t, notificationsUnread)

	require.NoError(t, module.Read.UpsertNotificationReadMarker(ctx, aliceSpace.SpaceID, bobSpace.SpaceID, 2000))
	conversations, _, err = listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.False(t, conversations[0].Unread)
	require.Equal(t, int64(0), conversations[0].UnreadCount)
	notificationsUnread, err = module.Read.HasUnreadNotifications(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.False(t, notificationsUnread)

	outgoing, err := module.Messages.CreateMessage(ctx, CreateSpaceMessageRecord{
		Kind:                         "regular",
		SenderSpaceID:                aliceSpace.SpaceID,
		RecipientSpaceID:             bobSpace.SpaceID,
		MessageCipher:                testSpaceBytes("outgoing-cipher"),
		SenderEncryptedMessageKey:    testSpaceBytes("outgoing-sender-key"),
		RecipientEncryptedMessageKey: testSpaceBytes("outgoing-recipient-key"),
	})
	require.NoError(t, err)
	setMessageCreatedAt(t, module, 3000, outgoing.MessageID)
	conversations, _, err = listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Equal(t, outgoing.MessageID, conversations[0].LatestActivity.MessageID.String)
	require.False(t, conversations[0].Unread)
	require.Equal(t, int64(0), conversations[0].UnreadCount)
	notificationsUnread, err = module.Read.HasUnreadNotifications(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.False(t, notificationsUnread)
}

func TestSpaceNotificationReadMarkersArePerFriend(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice-per-friend-unread@example.com", "alice-per-friend-public")
	bobID := insertSpaceUser(t, module, "bob-per-friend-unread@example.com", "bob-per-friend-public")
	charlieID := insertSpaceUser(t, module, "charlie-per-friend-unread@example.com", "charlie-per-friend-public")
	aliceSpace, err := testCreateSpace(ctx, module, aliceID, "alice_per_friend_unread", "alice-space-key", "alice-per-friend-unread-public", "alice-per-friend-unread-secret", "alice-per-friend-unread-secret-nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, module, bobID, "bob_per_friend_unread", "bob-space-key", "bob-per-friend-unread-public", "bob-per-friend-unread-secret", "bob-per-friend-unread-secret-nonce", "bob-profile")
	require.NoError(t, err)
	charlieSpace, err := testCreateSpace(ctx, module, charlieID, "charlie_per_friend_unread", "charlie-space-key", "charlie-per-friend-unread-public", "charlie-per-friend-unread-secret", "charlie-per-friend-unread-secret-nonce", "charlie-profile")
	require.NoError(t, err)
	require.NoError(t, testAddFriend(ctx, module, bobID, bobSpace.SpaceID, aliceSpace.SpaceID, "alice-bob-share-key", aliceSpace.CurrentVersion, "bob-share-key", bobSpace.CurrentVersion))
	require.NoError(t, testAddFriend(ctx, module, charlieID, charlieSpace.SpaceID, aliceSpace.SpaceID, "alice-charlie-share-key", aliceSpace.CurrentVersion, "charlie-share-key", charlieSpace.CurrentVersion))

	bobMessage, err := module.Messages.CreateMessage(ctx, CreateSpaceMessageRecord{
		Kind:                         "regular",
		SenderSpaceID:                bobSpace.SpaceID,
		RecipientSpaceID:             aliceSpace.SpaceID,
		MessageCipher:                testSpaceBytes("bob-cipher"),
		SenderEncryptedMessageKey:    testSpaceBytes("bob-sender-key"),
		RecipientEncryptedMessageKey: testSpaceBytes("bob-recipient-key"),
	})
	require.NoError(t, err)
	setMessageCreatedAt(t, module, 1000, bobMessage.MessageID)
	aliceMessageToBob, err := module.Messages.CreateMessage(ctx, CreateSpaceMessageRecord{
		Kind:                         "regular",
		SenderSpaceID:                aliceSpace.SpaceID,
		RecipientSpaceID:             bobSpace.SpaceID,
		MessageCipher:                testSpaceBytes("alice-bob-cipher"),
		SenderEncryptedMessageKey:    testSpaceBytes("alice-bob-sender-key"),
		RecipientEncryptedMessageKey: testSpaceBytes("alice-bob-recipient-key"),
	})
	require.NoError(t, err)
	setMessageCreatedAt(t, module, 1001, aliceMessageToBob.MessageID)
	require.NoError(t, module.Messages.SetLike(ctx, aliceMessageToBob.MessageID, bobSpace.SpaceID, true))
	setMessageLikeCreatedAt(t, module, 1002, aliceMessageToBob.MessageID, bobSpace.SpaceID)
	charlieMessage, err := module.Messages.CreateMessage(ctx, CreateSpaceMessageRecord{
		Kind:                         "regular",
		SenderSpaceID:                charlieSpace.SpaceID,
		RecipientSpaceID:             aliceSpace.SpaceID,
		MessageCipher:                testSpaceBytes("charlie-cipher"),
		SenderEncryptedMessageKey:    testSpaceBytes("charlie-sender-key"),
		RecipientEncryptedMessageKey: testSpaceBytes("charlie-recipient-key"),
	})
	require.NoError(t, err)
	setMessageCreatedAt(t, module, 2000, charlieMessage.MessageID)

	conversationBySpaceID := func(spaceID string) SpaceMessageConversationRecord {
		t.Helper()
		conversations, _, err := listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
		require.NoError(t, err)
		for _, conversation := range conversations {
			if conversation.Friend.SpaceID == spaceID {
				return conversation
			}
		}
		require.FailNowf(t, "conversation not found", "spaceID=%s", spaceID)
		return SpaceMessageConversationRecord{}
	}

	bobConversation := conversationBySpaceID(bobSpace.SpaceID)
	require.True(t, bobConversation.Unread)
	require.Equal(t, int64(1), bobConversation.UnreadCount)
	charlieConversation := conversationBySpaceID(charlieSpace.SpaceID)
	require.True(t, charlieConversation.Unread)
	require.Equal(t, int64(1), charlieConversation.UnreadCount)
	notificationsUnread, err := module.Read.HasUnreadNotifications(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.True(t, notificationsUnread)

	bobLatestActivityAt, err := module.Read.GetLatestConversationActivityAt(ctx, aliceSpace.SpaceID, bobSpace.SpaceID)
	require.NoError(t, err)
	require.Equal(t, int64(1002), bobLatestActivityAt)
	require.NoError(t, module.Read.UpsertNotificationReadMarker(ctx, aliceSpace.SpaceID, bobSpace.SpaceID, bobLatestActivityAt))
	bobConversation = conversationBySpaceID(bobSpace.SpaceID)
	require.False(t, bobConversation.Unread)
	require.Equal(t, int64(0), bobConversation.UnreadCount)
	charlieConversation = conversationBySpaceID(charlieSpace.SpaceID)
	require.True(t, charlieConversation.Unread)
	require.Equal(t, int64(1), charlieConversation.UnreadCount)
	notificationsUnread, err = module.Read.HasUnreadNotifications(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.True(t, notificationsUnread)

	require.NoError(t, module.Read.UpsertNotificationReadMarker(ctx, aliceSpace.SpaceID, charlieSpace.SpaceID, 2000))
	notificationsUnread, err = module.Read.HasUnreadNotifications(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.False(t, notificationsUnread)
}

func TestUnreadNotificationsTrackReadableActivityWithoutChangingLatestPreview(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)

	aliceID := insertSpaceUser(t, module, "alice-priority-unread@example.com", "alice-priority-unread-public")
	bobID := insertSpaceUser(t, module, "bob-priority-unread@example.com", "bob-priority-unread-public")
	aliceSpace, err := testCreateSpace(ctx, module, aliceID, "alice_priority_unread", "alice-space-key", "alice-priority-unread-public", "alice-priority-unread-secret", "alice-priority-unread-secret-nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, module, bobID, "bob_priority_unread", "bob-space-key", "bob-priority-unread-public", "bob-priority-unread-secret", "bob-priority-unread-secret-nonce", "bob-profile")
	require.NoError(t, err)
	require.NoError(t, testAddFriend(ctx, module, bobID, bobSpace.SpaceID, aliceSpace.SpaceID, "alice-share-key", aliceSpace.CurrentVersion, "bob-share-key", bobSpace.CurrentVersion))

	incoming, err := module.Messages.CreateMessage(ctx, CreateSpaceMessageRecord{
		Kind:                         "regular",
		SenderSpaceID:                bobSpace.SpaceID,
		RecipientSpaceID:             aliceSpace.SpaceID,
		MessageCipher:                testSpaceBytes("incoming-cipher"),
		SenderEncryptedMessageKey:    testSpaceBytes("incoming-sender-key"),
		RecipientEncryptedMessageKey: testSpaceBytes("incoming-recipient-key"),
	})
	require.NoError(t, err)
	setMessageCreatedAt(t, module, 1000, incoming.MessageID)
	outgoing, err := module.Messages.CreateMessage(ctx, CreateSpaceMessageRecord{
		Kind:                         "regular",
		SenderSpaceID:                aliceSpace.SpaceID,
		RecipientSpaceID:             bobSpace.SpaceID,
		MessageCipher:                testSpaceBytes("outgoing-cipher"),
		SenderEncryptedMessageKey:    testSpaceBytes("outgoing-sender-key"),
		RecipientEncryptedMessageKey: testSpaceBytes("outgoing-recipient-key"),
	})
	require.NoError(t, err)
	setMessageCreatedAt(t, module, 2000, outgoing.MessageID)

	conversations, _, err := listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Len(t, conversations, 1)
	require.Equal(t, outgoing.MessageID, conversations[0].LatestActivity.MessageID.String)
	require.Equal(t, int64(2000), conversations[0].SortCreatedAt)
	require.True(t, conversations[0].Unread)
	require.Equal(t, int64(1), conversations[0].UnreadCount)
	require.True(t, conversations[0].NotificationUnread)
	notificationsUnread, err := module.Read.HasUnreadNotifications(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.True(t, notificationsUnread)

	latestActivityAt, err := module.Read.GetLatestConversationActivityAt(ctx, aliceSpace.SpaceID, bobSpace.SpaceID)
	require.NoError(t, err)
	require.Equal(t, int64(2000), latestActivityAt)
	require.NoError(t, module.Read.UpsertNotificationReadMarker(ctx, aliceSpace.SpaceID, bobSpace.SpaceID, latestActivityAt))
	conversations, _, err = listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Equal(t, outgoing.MessageID, conversations[0].LatestActivity.MessageID.String)
	require.False(t, conversations[0].Unread)
	require.Equal(t, int64(0), conversations[0].UnreadCount)
	require.False(t, conversations[0].NotificationUnread)
	notificationsUnread, err = module.Read.HasUnreadNotifications(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.False(t, notificationsUnread)

	require.NoError(t, module.Messages.SetLike(ctx, incoming.MessageID, aliceSpace.SpaceID, true))
	setMessageLikeCreatedAt(t, module, 2500, incoming.MessageID, aliceSpace.SpaceID)

	conversations, _, err = listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Equal(t, "message_like", conversations[0].LatestActivity.Type)
	require.True(t, conversations[0].LatestActivity.Outgoing)
	require.Equal(t, incoming.MessageID, conversations[0].LatestActivity.MessageID.String)
	require.Equal(t, int64(2500), conversations[0].SortCreatedAt)
	require.False(t, conversations[0].Unread)
	require.Equal(t, int64(0), conversations[0].UnreadCount)
	require.False(t, conversations[0].NotificationUnread)
	notificationsUnread, err = module.Read.HasUnreadNotifications(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.False(t, notificationsUnread)
	latestActivityAt, err = module.Read.GetLatestConversationActivityAt(ctx, aliceSpace.SpaceID, bobSpace.SpaceID)
	require.NoError(t, err)
	require.Equal(t, int64(2500), latestActivityAt)

	alicePostID, err := testCreatePost(ctx, module, aliceID, aliceSpace.SpaceID, "alice-post-key", nil, aliceSpace.CurrentVersion, nil)
	require.NoError(t, err)
	bobPostID, err := testCreatePost(ctx, module, bobID, bobSpace.SpaceID, "bob-post-key", nil, bobSpace.CurrentVersion, nil)
	require.NoError(t, err)
	_, err = module.Posts.DB.Exec(`
			INSERT INTO space_post_assets (post_id, object_key, bucket_id, metadata_cipher)
			VALUES ($1, $2, $3, $4)
		`, bobPostID, "bob-post-object", "bucket", "metadata")
	require.NoError(t, err)
	require.NoError(t, testSetPostLike(ctx, module, alicePostID, bobSpace.SpaceID, true))
	setPostLikeCreatedAt(t, module, 3000, alicePostID, bobSpace.SpaceID)
	outgoingPostReply, err := module.Messages.CreateMessage(ctx, CreateSpaceMessageRecord{
		Kind:                         "post_reply",
		SenderSpaceID:                aliceSpace.SpaceID,
		RecipientSpaceID:             bobSpace.SpaceID,
		MessageCipher:                testSpaceBytes("outgoing-post-reply-cipher"),
		SenderEncryptedMessageKey:    testSpaceBytes("outgoing-post-reply-sender-key"),
		RecipientEncryptedMessageKey: testSpaceBytes("outgoing-post-reply-recipient-key"),
		ReplyPostID:                  sql.NullInt64{Int64: bobPostID, Valid: true},
	})
	require.NoError(t, err)
	setMessageCreatedAt(t, module, 4000, outgoingPostReply.MessageID)

	conversations, _, err = listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Equal(t, "message", conversations[0].LatestActivity.Type)
	require.Equal(t, outgoingPostReply.MessageID, conversations[0].LatestActivity.MessageID.String)
	require.True(t, conversations[0].LatestActivity.PostID.Valid)
	require.Equal(t, bobPostID, conversations[0].LatestActivity.PostID.Int64)
	require.Equal(t, int64(4000), conversations[0].SortCreatedAt)
	require.False(t, conversations[0].Unread)
	require.Equal(t, int64(0), conversations[0].UnreadCount)
	require.True(t, conversations[0].NotificationUnread)
	notificationsUnread, err = module.Read.HasUnreadNotifications(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.True(t, notificationsUnread)

	require.NoError(t, testSetPostLike(ctx, module, bobPostID, aliceSpace.SpaceID, true))
	setPostLikeCreatedAt(t, module, 4500, bobPostID, aliceSpace.SpaceID)

	conversations, _, err = listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Equal(t, "post_like", conversations[0].LatestActivity.Type)
	require.True(t, conversations[0].LatestActivity.Outgoing)
	require.True(t, conversations[0].LatestActivity.PostID.Valid)
	require.Equal(t, bobPostID, conversations[0].LatestActivity.PostID.Int64)
	require.Equal(t, int64(4500), conversations[0].SortCreatedAt)
	require.False(t, conversations[0].Unread)
	require.Equal(t, int64(0), conversations[0].UnreadCount)
	require.True(t, conversations[0].NotificationUnread)
	latestActivityAt, err = module.Read.GetLatestConversationActivityAt(ctx, aliceSpace.SpaceID, bobSpace.SpaceID)
	require.NoError(t, err)
	require.Equal(t, int64(4500), latestActivityAt)

	thread, _, err := module.Messages.ListThread(ctx, aliceSpace.SpaceID, bobSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.GreaterOrEqual(t, len(thread), 3)
	require.Equal(t, "post_like", thread[0].Kind)
	require.Equal(t, "You liked a post", thread[0].Text)
	require.True(t, thread[0].ReplyPostID.Valid)
	require.Equal(t, bobPostID, thread[0].ReplyPostID.Int64)
	require.Equal(t, bobSpace.SpaceID, thread[0].RecipientSpaceID)
	require.Equal(t, "post_reply", thread[1].Kind)
	require.Equal(t, outgoingPostReply.MessageID, thread[1].MessageID)
	require.Equal(t, "post_like", thread[2].Kind)
	require.Equal(t, "Liked your post", thread[2].Text)
	require.True(t, thread[2].ReplyPostID.Valid)
	require.Equal(t, alicePostID, thread[2].ReplyPostID.Int64)
	require.Equal(t, aliceSpace.SpaceID, thread[2].RecipientSpaceID)

	incomingPostReply, err := module.Messages.CreateMessage(ctx, CreateSpaceMessageRecord{
		Kind:                         "post_reply",
		SenderSpaceID:                bobSpace.SpaceID,
		RecipientSpaceID:             aliceSpace.SpaceID,
		MessageCipher:                testSpaceBytes("incoming-post-reply-cipher"),
		SenderEncryptedMessageKey:    testSpaceBytes("incoming-post-reply-sender-key"),
		RecipientEncryptedMessageKey: testSpaceBytes("incoming-post-reply-recipient-key"),
		ReplyPostID:                  sql.NullInt64{Int64: alicePostID, Valid: true},
	})
	require.NoError(t, err)
	setMessageCreatedAt(t, module, 5000, incomingPostReply.MessageID)
	secondIncomingPostReply, err := module.Messages.CreateMessage(ctx, CreateSpaceMessageRecord{
		Kind:                         "post_reply",
		SenderSpaceID:                bobSpace.SpaceID,
		RecipientSpaceID:             aliceSpace.SpaceID,
		MessageCipher:                testSpaceBytes("second-incoming-post-reply-cipher"),
		SenderEncryptedMessageKey:    testSpaceBytes("second-incoming-post-reply-sender-key"),
		RecipientEncryptedMessageKey: testSpaceBytes("second-incoming-post-reply-recipient-key"),
		ReplyPostID:                  sql.NullInt64{Int64: alicePostID, Valid: true},
	})
	require.NoError(t, err)
	setMessageCreatedAt(t, module, 5001, secondIncomingPostReply.MessageID)

	conversations, _, err = listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Equal(t, "post_reply", conversations[0].LatestActivity.Type)
	require.Equal(t, secondIncomingPostReply.MessageID, conversations[0].LatestActivity.MessageID.String)
	require.Equal(t, int64(5001), conversations[0].SortCreatedAt)
	require.True(t, conversations[0].Unread)
	require.Equal(t, int64(2), conversations[0].UnreadCount)
	require.True(t, conversations[0].NotificationUnread)
	notificationsUnread, err = module.Read.HasUnreadNotifications(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.True(t, notificationsUnread)

	setPostLikeCreatedAt(t, module, 6000, alicePostID, bobSpace.SpaceID)

	conversations, _, err = listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.Equal(t, "post_like", conversations[0].LatestActivity.Type)
	require.Equal(t, alicePostID, conversations[0].LatestActivity.PostID.Int64)
	require.Equal(t, int64(6000), conversations[0].SortCreatedAt)
	require.True(t, conversations[0].Unread)
	require.Equal(t, int64(2), conversations[0].UnreadCount)
	require.True(t, conversations[0].NotificationUnread)
	notificationsUnread, err = module.Read.HasUnreadNotifications(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.True(t, notificationsUnread)

	latestActivityAt, err = module.Read.GetLatestConversationActivityAt(ctx, aliceSpace.SpaceID, bobSpace.SpaceID)
	require.NoError(t, err)
	require.Equal(t, int64(6000), latestActivityAt)
	require.NoError(t, module.Read.UpsertNotificationReadMarker(ctx, aliceSpace.SpaceID, bobSpace.SpaceID, latestActivityAt))
	conversations, _, err = listTestConversations(ctx, module, aliceSpace.SpaceID, "", 10)
	require.NoError(t, err)
	require.False(t, conversations[0].Unread)
	require.Equal(t, int64(0), conversations[0].UnreadCount)
	require.False(t, conversations[0].NotificationUnread)
	notificationsUnread, err = module.Read.HasUnreadNotifications(ctx, aliceSpace.SpaceID)
	require.NoError(t, err)
	require.False(t, notificationsUnread)
}

func ptr(value string) *string {
	return &value
}

func sqlNullInt64(value int64) sql.NullInt64 {
	return sql.NullInt64{Int64: value, Valid: true}
}

func requireQueuedTempObject(t *testing.T, module *Module, objectKey, purpose, bucketID string) {
	t.Helper()
	var gotPurpose, gotBucketID string
	var expired, cleanupDelayed bool
	err := module.Assets.DB.QueryRow(`
		SELECT purpose,
		       bucket_id,
		       expires_at <= now_utc_micro_seconds(),
		       cleanup_after >= now_utc_micro_seconds() + $2
		FROM space_temp_objects
		WHERE object_key = $1
	`, objectKey, SpaceUploadURLExpiry.Microseconds()).Scan(&gotPurpose, &gotBucketID, &expired, &cleanupDelayed)
	require.NoError(t, err)
	require.Equal(t, purpose, gotPurpose)
	require.Equal(t, bucketID, gotBucketID)
	require.True(t, expired)
	require.True(t, cleanupDelayed)
}

func setPostCreatedAt(t *testing.T, module *Module, createdAt int64, postIDs ...int64) {
	t.Helper()
	for _, postID := range postIDs {
		_, err := module.Posts.DB.Exec(`UPDATE space_posts SET created_at = $1 WHERE post_id = $2`, createdAt, postID)
		require.NoError(t, err)
	}
}

func setPostLikeCreatedAt(t *testing.T, module *Module, createdAt, postID int64, actorSpaceID string) {
	t.Helper()
	_, err := module.Posts.DB.Exec(`UPDATE space_messages SET created_at = $1, updated_at = $1 WHERE kind = 'post_like' AND reply_post_id = $2 AND sender_space_id = $3`, createdAt, postID, actorSpaceID)
	require.NoError(t, err)
}

func setFriendRequestCreatedAt(t *testing.T, module *Module, createdAt int64, requestID int64) {
	t.Helper()
	_, err := module.Friends.DB.Exec(`UPDATE space_friend_requests SET created_at = $1 WHERE request_id = $2`, createdAt, requestID)
	require.NoError(t, err)
}

func setFriendShareCreatedAt(t *testing.T, module *Module, createdAt int64, spaceID string, friendSpaceID string) {
	t.Helper()
	_, err := module.Friends.DB.Exec(`UPDATE space_friend_shares SET created_at = $1 WHERE space_id = $2 AND friend_space_id = $3`, createdAt, spaceID, friendSpaceID)
	require.NoError(t, err)
}

func setMessageCreatedAt(t *testing.T, module *Module, createdAt int64, messageID string) {
	t.Helper()
	_, err := module.Messages.DB.Exec(`UPDATE space_messages SET created_at = $1 WHERE message_id = $2`, createdAt, messageID)
	require.NoError(t, err)
}

func setMessageLikeCreatedAt(t *testing.T, module *Module, createdAt int64, messageID string, actorSpaceID string) {
	t.Helper()
	_, err := module.Messages.DB.Exec(`UPDATE space_messages SET recipient_liked_at = $1 WHERE message_id = $2 AND recipient_space_id = $3`, createdAt, messageID, actorSpaceID)
	require.NoError(t, err)
}
