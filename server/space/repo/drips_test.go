package repo

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"strconv"
	"testing"

	"github.com/ente/museum/internal/testutil"
	timeutil "github.com/ente/museum/pkg/utils/time"
	"github.com/stretchr/testify/require"
)

const (
	testSpaceDripProfileMissing24h = "space_profile_missing_24h"
	testSpaceDripProfileMissing4d  = "space_profile_missing_4d"
	testSpaceDripInvitePeople24h   = "space_invite_people_24h"
	testSpaceDripInvitePeople4d    = "space_invite_people_4d"
	testSpaceDripFirstPost24h      = "space_first_post_24h"
	testSpaceDripFirstPost4d       = "space_first_post_4d"
	testSpaceDripFeedback7d        = "space_feedback_7d"
)

func TestProfileMissingDripCandidatesUseSpaceSessionsOnly(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)
	now := timeutil.Microseconds()

	noSessionUserID := insertSpaceUser(t, module, "no-space-session@example.com", "no-session-public")
	oldSessionUserID := insertSpaceUser(t, module, "old-space-session@example.com", "old-session-public")
	recentSessionUserID := insertSpaceUser(t, module, "recent-space-session@example.com", "recent-session-public")
	completedProfileUserID := insertSpaceUser(t, module, "completed-space-profile@example.com", "completed-profile-public")

	insertSpaceBrowserSession(t, module, oldSessionUserID, now-25*timeutil.MicroSecondsInOneHour, now+timeutil.MicroSecondsInOneHour)
	insertSpaceBrowserSession(t, module, recentSessionUserID, now-2*timeutil.MicroSecondsInOneHour, now+timeutil.MicroSecondsInOneHour)
	insertSpaceBrowserSession(t, module, completedProfileUserID, now-25*timeutil.MicroSecondsInOneHour, now+timeutil.MicroSecondsInOneHour)
	_, err := testCreateSpace(ctx, module, completedProfileUserID, "completed_profile", "root", "public", "secret", "nonce", "profile")
	require.NoError(t, err)

	candidates, err := module.Drips.ListProfileMissingCandidates(ctx, now, now-24*timeutil.MicroSecondsInOneHour, []string{testSpaceDripProfileMissing24h, testSpaceDripProfileMissing4d}, 50)
	require.NoError(t, err)
	require.Equal(t, []int64{oldSessionUserID}, spaceDripCandidateUserIDs(candidates))
	require.NotContains(t, spaceDripCandidateUserIDs(candidates), noSessionUserID)

	testutil.InsertNotificationHistory(t, module.Drips.DB, testutil.NotificationHistoryFixture{
		UserID:     oldSessionUserID,
		TemplateID: testSpaceDripProfileMissing4d,
		SentTime:   now,
	})
	candidates, err = module.Drips.ListProfileMissingCandidates(ctx, now, now-24*timeutil.MicroSecondsInOneHour, []string{testSpaceDripProfileMissing24h, testSpaceDripProfileMissing4d}, 50)
	require.NoError(t, err)
	require.Empty(t, candidates)
}

func TestInvitePeopleDripCandidatesRequireNoFriendsOrRequests(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)
	now := timeutil.Microseconds()
	threshold := now - 24*timeutil.MicroSecondsInOneHour

	readyUserID := insertSpaceUser(t, module, "space-ready@example.com", "ready-public")
	friendUserID := insertSpaceUser(t, module, "space-with-friend@example.com", "friend-public")
	pendingUserID := insertSpaceUser(t, module, "space-with-request@example.com", "pending-public")
	otherUserID := insertSpaceUser(t, module, "space-other@example.com", "other-public")

	readySpace := mustCreateOldSpace(t, ctx, module, readyUserID, "space_ready", now-2*24*timeutil.MicroSecondsInOneHour)
	friendSpace := mustCreateOldSpace(t, ctx, module, friendUserID, "space_friend", now-2*24*timeutil.MicroSecondsInOneHour)
	pendingSpace := mustCreateOldSpace(t, ctx, module, pendingUserID, "space_pending", now-2*24*timeutil.MicroSecondsInOneHour)
	otherSpace := mustCreateOldSpace(t, ctx, module, otherUserID, "space_other", now-2*24*timeutil.MicroSecondsInOneHour)

	require.NoError(t, testAddFriend(ctx, module, friendUserID, friendSpace.SpaceID, otherSpace.SpaceID, "other-share", otherSpace.CurrentVersion, "friend-share", friendSpace.CurrentVersion))
	_, _, err := testCreateFriendRequest(ctx, module, pendingUserID, pendingSpace.SpaceID, otherSpace.SpaceID, "pending-share", pendingSpace.CurrentVersion)
	require.NoError(t, err)

	candidates, err := module.Drips.ListInvitePeopleCandidates(ctx, threshold, []string{testSpaceDripInvitePeople24h, testSpaceDripInvitePeople4d}, 50)
	require.NoError(t, err)
	require.Equal(t, []int64{readyUserID}, spaceDripCandidateUserIDs(candidates))
	require.NotEmpty(t, readySpace.SpaceID)
}

func TestFirstPostAndFeedbackDripCandidates(t *testing.T) {
	ctx := context.Background()
	module := newSpaceTestModule(t)
	now := timeutil.Microseconds()
	old := now - 8*24*timeutil.MicroSecondsInOneHour

	aliceID := insertSpaceUser(t, module, "alice-drips@example.com", "alice-public")
	bobID := insertSpaceUser(t, module, "bob-drips@example.com", "bob-public")
	charlieID := insertSpaceUser(t, module, "charlie-drips@example.com", "charlie-public")
	aliceSpace := mustCreateOldSpace(t, ctx, module, aliceID, "alice_drips", old)
	bobSpace := mustCreateOldSpace(t, ctx, module, bobID, "bob_drips", old)
	charlieSpace := mustCreateOldSpace(t, ctx, module, charlieID, "charlie_drips", old)

	require.NoError(t, testAddFriend(ctx, module, aliceID, aliceSpace.SpaceID, bobSpace.SpaceID, "bob-share", bobSpace.CurrentVersion, "alice-share", aliceSpace.CurrentVersion))
	setFriendshipCreatedAt(t, module, aliceSpace.SpaceID, bobSpace.SpaceID, old)
	require.NoError(t, testAddFriend(ctx, module, charlieID, charlieSpace.SpaceID, bobSpace.SpaceID, "bob-charlie-share", bobSpace.CurrentVersion, "charlie-share", charlieSpace.CurrentVersion))
	setFriendshipCreatedAt(t, module, charlieSpace.SpaceID, bobSpace.SpaceID, old)

	postID, err := testCreatePost(ctx, module, aliceID, aliceSpace.SpaceID, "alice-post-key", nil, aliceSpace.CurrentVersion, nil)
	require.NoError(t, err)
	setPostCreatedAt(t, module, old, postID)
	_, err = module.Messages.CreateMessage(ctx, CreateSpaceMessageRecord{
		Kind:                         "post_reply",
		SenderSpaceID:                bobSpace.SpaceID,
		RecipientSpaceID:             aliceSpace.SpaceID,
		MessageCipher:                testSpaceBytes("reply-cipher"),
		SenderEncryptedMessageKey:    testSpaceBytes("reply-sender-key"),
		RecipientEncryptedMessageKey: testSpaceBytes("reply-recipient-key"),
		ReplyPostID:                  sql.NullInt64{Int64: postID, Valid: true},
	})
	require.NoError(t, err)
	setPostRepliesCreatedAt(t, module, bobSpace.SpaceID, old)

	firstPostCandidates, err := module.Drips.ListFirstPostCandidates(ctx, now-24*timeutil.MicroSecondsInOneHour, []string{testSpaceDripFirstPost24h, testSpaceDripFirstPost4d}, 50)
	require.NoError(t, err)
	require.ElementsMatch(t, []int64{bobID, charlieID}, spaceDripCandidateUserIDs(firstPostCandidates))

	feedbackCandidates, err := module.Drips.ListFeedbackCandidates(ctx, now-7*24*timeutil.MicroSecondsInOneHour, []string{testSpaceDripFeedback7d}, 50)
	require.NoError(t, err)
	require.ElementsMatch(t, []int64{aliceID, bobID}, spaceDripCandidateUserIDs(feedbackCandidates))

	testutil.InsertNotificationHistory(t, module.Drips.DB, testutil.NotificationHistoryFixture{
		UserID:     aliceID,
		TemplateID: testSpaceDripFeedback7d,
		SentTime:   now,
	})
	feedbackCandidates, err = module.Drips.ListFeedbackCandidates(ctx, now-7*24*timeutil.MicroSecondsInOneHour, []string{testSpaceDripFeedback7d}, 50)
	require.NoError(t, err)
	require.Equal(t, []int64{bobID}, spaceDripCandidateUserIDs(feedbackCandidates))
}

func insertSpaceBrowserSession(t *testing.T, module *Module, userID int64, createdAt int64, expiresAt int64) {
	t.Helper()
	tokenHash := sha256.Sum256([]byte(strconv.FormatInt(userID, 10) + "-space-session"))
	require.NoError(t, module.Sessions.CreateBrowserSession(context.Background(), tokenHash[:], userID, "wrap-key", expiresAt))
	_, err := module.Sessions.DB.Exec(`
		UPDATE space_browser_sessions
		SET created_at = $1, updated_at = $1, last_used_at = $1, expires_at = $2
		WHERE user_id = $3
	`, createdAt, expiresAt, userID)
	require.NoError(t, err)
}

func mustCreateOldSpace(t *testing.T, ctx context.Context, module *Module, userID int64, slug string, createdAt int64) *SpaceRecord {
	t.Helper()
	space, err := testCreateSpace(ctx, module, userID, slug, slug+"-root", slug+"-public", slug+"-secret", slug+"-nonce", slug+"-profile")
	require.NoError(t, err)
	_, err = module.Spaces.DB.Exec(`
		UPDATE spaces
		SET created_at = $1, updated_at = $1
		WHERE space_id = $2
	`, createdAt, space.SpaceID)
	require.NoError(t, err)
	space.CreatedAt = createdAt
	return space
}

func setFriendshipCreatedAt(t *testing.T, module *Module, firstSpaceID string, secondSpaceID string, createdAt int64) {
	t.Helper()
	_, err := module.Friends.DB.Exec(`
		UPDATE space_friend_shares
		SET created_at = $1, updated_at = $1
		WHERE (space_id = $2 AND friend_space_id = $3)
		   OR (space_id = $3 AND friend_space_id = $2)
	`, createdAt, firstSpaceID, secondSpaceID)
	require.NoError(t, err)
}

func setPostRepliesCreatedAt(t *testing.T, module *Module, senderSpaceID string, createdAt int64) {
	t.Helper()
	_, err := module.Messages.DB.Exec(`
		UPDATE space_messages
		SET created_at = $1, updated_at = $1
		WHERE sender_space_id = $2 AND kind = 'post_reply'
	`, createdAt, senderSpaceID)
	require.NoError(t, err)
}

func spaceDripCandidateUserIDs(candidates []SpaceDripCandidate) []int64 {
	userIDs := make([]int64, 0, len(candidates))
	for _, candidate := range candidates {
		userIDs = append(userIDs, candidate.UserID)
	}
	return userIDs
}
