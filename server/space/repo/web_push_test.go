package repo

import (
	"bytes"
	"context"
	"testing"

	timeutil "github.com/ente/museum/pkg/utils/time"
	"github.com/stretchr/testify/require"
)

func TestWebPushSubscriptionsFollowTargetsAndActiveSessions(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := context.Background()
	ownerID := insertSpaceUser(t, module, "space-web-push-owner@example.com", "owner-public")
	friendID := insertSpaceUser(t, module, "space-web-push-friend@example.com", "friend-public")
	space, err := testCreateSpace(ctx, module, ownerID, "space_push_owner", "root", "public", "secret", "nonce", "profile")
	require.NoError(t, err)
	friendSpace, err := testCreateSpace(ctx, module, friendID, "space_push_friend", "friend-root", "friend-public", "friend-secret", "friend-nonce", "friend-profile")
	require.NoError(t, err)
	require.NoError(t, testAddFriend(
		ctx,
		module,
		friendID,
		friendSpace.SpaceID,
		space.SpaceID,
		"owner-share-key",
		space.CurrentVersion,
		"friend-share-key",
		friendSpace.CurrentVersion,
	))
	link, err := module.Links.Create(
		ctx,
		space.SpaceID,
		bytes.Repeat([]byte{1}, 32),
		bytes.Repeat([]byte{2}, 16),
		67108864,
		2,
		space.CurrentVersion,
		[]byte("encrypted-space-key"),
		[]byte("encrypted-access-key"),
	)
	require.NoError(t, err)

	activeSession := []byte("active-space-web-push-session")
	expiredSession := []byte("expired-space-web-push-session")
	require.NoError(t, module.Sessions.CreateBrowserSession(ctx, activeSession, friendID, "active-wrap", timeutil.NDaysFromNow(1)))
	require.NoError(t, module.Sessions.CreateBrowserSession(ctx, expiredSession, friendID, "expired-wrap", timeutil.Microseconds()-1))

	_, err = module.WebPush.UpsertAccountSubscription(
		ctx,
		activeSession,
		"https://push.example/active",
		"active-p256dh",
		"active-auth",
	)
	require.NoError(t, err)
	accountTargetID, err := module.WebPush.UpsertAccountSubscription(
		ctx,
		activeSession,
		"https://push.example/replaced",
		"replaced-p256dh",
		"replaced-auth",
	)
	require.NoError(t, err)
	_, err = module.WebPush.UpsertAccountSubscription(
		ctx,
		expiredSession,
		"https://push.example/expired",
		"expired-p256dh",
		"expired-auth",
	)
	require.NoError(t, err)
	publicTargetID, err := module.WebPush.UpsertLinkSubscription(
		ctx,
		link.LinkID,
		"https://push.example/public",
		"public-p256dh",
		"public-auth",
	)
	require.NoError(t, err)
	require.NotEqual(t, accountTargetID, publicTargetID)

	accountSubscriptions, err := module.WebPush.ListActiveAccountSubscriptions(ctx, friendID)
	require.NoError(t, err)
	require.Len(t, accountSubscriptions, 1)
	require.Equal(t, "https://push.example/replaced", accountSubscriptions[0].Endpoint)

	postSubscriptions, err := module.WebPush.ListPostSubscriptions(ctx, space.SpaceID)
	require.NoError(t, err)
	require.ElementsMatch(t, []SpaceWebPushSubscriptionRecord{
		{
			TargetID: accountTargetID,
			Endpoint: "https://push.example/replaced",
			P256dh:   "replaced-p256dh",
			Auth:     "replaced-auth",
		},
		{
			TargetID: publicTargetID,
			Endpoint: "https://push.example/public",
			P256dh:   "public-p256dh",
			Auth:     "public-auth",
			Public:   true,
		},
	}, postSubscriptions)

	require.NoError(t, module.Sessions.DeleteBrowserSession(ctx, activeSession))
	var count int
	require.NoError(t, module.WebPush.DB.QueryRow(`
		SELECT COUNT(*)
		FROM space_web_push_subscriptions
		WHERE endpoint = 'https://push.example/replaced'
	`).Scan(&count))
	require.Zero(t, count)
	require.NoError(t, module.WebPush.DB.QueryRow(`
		SELECT COUNT(*)
		FROM space_web_push_subscriptions
		WHERE endpoint = 'https://push.example/public'
	`).Scan(&count))
	require.Equal(t, 1, count)

	_, err = module.Links.Rotate(
		ctx,
		space.SpaceID,
		bytes.Repeat([]byte{3}, 32),
		bytes.Repeat([]byte{4}, 16),
		67108864,
		2,
		space.CurrentVersion,
		[]byte("rotated-encrypted-space-key"),
		[]byte("rotated-encrypted-access-key"),
	)
	require.NoError(t, err)
	require.NoError(t, module.WebPush.DB.QueryRow(`
		SELECT COUNT(*)
		FROM space_web_push_subscriptions
		WHERE endpoint = 'https://push.example/public'
	`).Scan(&count))
	require.Zero(t, count)
}

func TestWebPushAccountSubscriptionRequiresAuthToReassignSession(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := context.Background()
	ownerID := insertSpaceUser(t, module, "space-web-push-auth-owner@example.com", "owner-public")
	attackerID := insertSpaceUser(t, module, "space-web-push-auth-attacker@example.com", "attacker-public")
	session := []byte("original-space-web-push-session")
	newSession := []byte("new-space-web-push-session")
	attackerSession := []byte("attacker-space-web-push-session")
	require.NoError(t, module.Sessions.CreateBrowserSession(ctx, session, ownerID, "wrap", timeutil.NDaysFromNow(1)))
	require.NoError(t, module.Sessions.CreateBrowserSession(ctx, newSession, ownerID, "wrap", timeutil.NDaysFromNow(1)))
	require.NoError(t, module.Sessions.CreateBrowserSession(ctx, attackerSession, attackerID, "wrap", timeutil.NDaysFromNow(1)))
	endpoint := "https://push.example/victim"
	targetID, err := module.WebPush.UpsertAccountSubscription(ctx, session, endpoint, "victim-p256dh", "victim-auth")
	require.NoError(t, err)
	_, err = module.WebPush.UpsertAccountSubscription(ctx, attackerSession, "https://push.example/attacker", "attacker-p256dh", "attacker-auth")
	require.NoError(t, err)
	before, err := module.WebPush.ListActiveAccountSubscriptions(ctx, ownerID)
	require.NoError(t, err)
	attackerBefore, err := module.WebPush.ListActiveAccountSubscriptions(ctx, attackerID)
	require.NoError(t, err)

	for _, caller := range [][]byte{session, attackerSession} {
		_, err = module.WebPush.UpsertAccountSubscription(ctx, caller, endpoint, "attacker-p256dh", "attacker-auth")
		require.Error(t, err)
	}
	unchanged, err := module.WebPush.ListActiveAccountSubscriptions(ctx, ownerID)
	require.NoError(t, err)
	require.Equal(t, before, unchanged)
	attackerUnchanged, err := module.WebPush.ListActiveAccountSubscriptions(ctx, attackerID)
	require.NoError(t, err)
	require.Equal(t, attackerBefore, attackerUnchanged)

	repeatedTargetID, err := module.WebPush.UpsertAccountSubscription(ctx, session, endpoint, "victim-p256dh", "victim-auth")
	require.NoError(t, err)
	require.Equal(t, targetID, repeatedTargetID)
	newTargetID, err := module.WebPush.UpsertAccountSubscription(ctx, newSession, endpoint, "victim-p256dh", "victim-auth")
	require.NoError(t, err)
	require.Equal(t, targetID, newTargetID)
	var storedSession []byte
	require.NoError(t, module.WebPush.DB.QueryRow(`
		SELECT session_token_hash FROM space_web_push_subscriptions WHERE target_id = $1
	`, targetID).Scan(&storedSession))
	require.Equal(t, newSession, storedSession)
	after, err := module.WebPush.ListActiveAccountSubscriptions(ctx, ownerID)
	require.NoError(t, err)
	require.Equal(t, before, after)
}

func TestResetUserAccessDeletesLinkSubscriptions(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := context.Background()
	ownerID := insertSpaceUser(t, module, "space-web-push-reset@example.com", "reset-public")
	space, err := testCreateSpace(ctx, module, ownerID, "space_push_reset", "root", "public", "secret", "nonce", "profile")
	require.NoError(t, err)
	link, err := module.Links.Create(
		ctx,
		space.SpaceID,
		bytes.Repeat([]byte{9}, 32),
		bytes.Repeat([]byte{10}, 16),
		67108864,
		2,
		space.CurrentVersion,
		[]byte("encrypted-space-key"),
		[]byte("encrypted-access-key"),
	)
	require.NoError(t, err)
	endpoint := "https://push.example/reset"
	_, err = module.WebPush.UpsertLinkSubscription(ctx, link.LinkID, endpoint, "p256dh", "auth")
	require.NoError(t, err)

	require.NoError(t, module.ResetUserAccess(ctx, ownerID))

	require.Equal(t, int64(0), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_web_push_subscriptions WHERE endpoint = $1`, endpoint))
}

func TestWebPushSharedEndpointKeepsIndependentTargets(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := context.Background()
	ownerID := insertSpaceUser(t, module, "space-web-push-shared-owner@example.com", "owner-public")
	space, err := testCreateSpace(ctx, module, ownerID, "space_push_shared", "root", "public", "secret", "nonce", "profile")
	require.NoError(t, err)
	link, err := module.Links.Create(
		ctx,
		space.SpaceID,
		bytes.Repeat([]byte{5}, 32),
		bytes.Repeat([]byte{6}, 16),
		67108864,
		2,
		space.CurrentVersion,
		[]byte("encrypted-space-key"),
		[]byte("encrypted-access-key"),
	)
	require.NoError(t, err)
	session := []byte("shared-space-web-push-session")
	require.NoError(t, module.Sessions.CreateBrowserSession(ctx, session, ownerID, "wrap", timeutil.NDaysFromNow(1)))
	endpoint := "https://push.example/shared"

	accountTargetID, err := module.WebPush.UpsertAccountSubscription(ctx, session, endpoint, "first-p256dh", "first-auth")
	require.NoError(t, err)
	linkTargetID, err := module.WebPush.UpsertLinkSubscription(ctx, link.LinkID, endpoint, "second-p256dh", "second-auth")
	require.NoError(t, err)
	_, err = module.WebPush.UpsertLinkSubscription(ctx, link.LinkID, endpoint, "attacker-p256dh", "attacker-auth")
	require.Error(t, err)
	updatedLinkTargetID, err := module.WebPush.UpsertLinkSubscription(ctx, link.LinkID, endpoint, "updated-link-p256dh", "second-auth")
	require.NoError(t, err)
	require.Equal(t, linkTargetID, updatedLinkTargetID)
	accountSubscriptions, err := module.WebPush.ListActiveAccountSubscriptions(ctx, ownerID)
	require.NoError(t, err)
	require.Equal(t, []SpaceWebPushSubscriptionRecord{{
		TargetID: accountTargetID,
		Endpoint: endpoint,
		P256dh:   "first-p256dh",
		Auth:     "first-auth",
	}}, accountSubscriptions)
	updatedAccountTargetID, err := module.WebPush.UpsertAccountSubscription(ctx, session, endpoint, "updated-account-p256dh", "first-auth")
	require.NoError(t, err)
	require.Equal(t, accountTargetID, updatedAccountTargetID)
	var linkP256dh, linkAuth string
	require.NoError(t, module.WebPush.DB.QueryRow(`
		SELECT p256dh, auth FROM space_web_push_subscriptions WHERE target_id = $1
	`, linkTargetID).Scan(&linkP256dh, &linkAuth))
	require.Equal(t, "updated-link-p256dh", linkP256dh)
	require.Equal(t, "second-auth", linkAuth)

	var count int
	require.NoError(t, module.WebPush.DB.QueryRow(`
		SELECT COUNT(*)
		FROM space_web_push_subscriptions
		WHERE endpoint = $1
	`, endpoint).Scan(&count))
	require.Equal(t, 2, count)

	require.NoError(t, module.WebPush.DeleteAccountSubscription(ctx, session, endpoint))
	require.NoError(t, module.WebPush.DB.QueryRow(`
		SELECT COUNT(*)
		FROM space_web_push_subscriptions
		WHERE endpoint = $1 AND link_id = $2
	`, endpoint, link.LinkID).Scan(&count))
	require.Equal(t, 1, count)

	require.NoError(t, module.WebPush.DeleteLinkSubscription(ctx, link.LinkID, endpoint))
	require.NoError(t, module.WebPush.DB.QueryRow(`
		SELECT COUNT(*)
		FROM space_web_push_subscriptions
		WHERE endpoint = $1
	`, endpoint).Scan(&count))
	require.Zero(t, count)
}

func TestWebPushLinkSubscriptionLimit(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := context.Background()
	ownerID := insertSpaceUser(t, module, "space-web-push-limit-owner@example.com", "limit-owner")
	space, err := testCreateSpace(ctx, module, ownerID, "space_push_limit", "root", "public", "secret", "nonce", "profile")
	require.NoError(t, err)
	link, err := module.Links.Create(
		ctx,
		space.SpaceID,
		bytes.Repeat([]byte{7}, 32),
		bytes.Repeat([]byte{8}, 16),
		67108864,
		2,
		space.CurrentVersion,
		[]byte("encrypted-space-key"),
		[]byte("encrypted-access-key"),
	)
	require.NoError(t, err)

	_, err = module.WebPush.DB.Exec(`
		INSERT INTO space_web_push_subscriptions (
			target_id, endpoint, link_id, p256dh, auth
		)
		SELECT
			'wpt_limit_' || value,
			'https://push.example/limit/' || value,
			$1,
			'p256dh',
			'auth'
		FROM generate_series(1, $2) value
	`, link.LinkID, spaceWebPushLinkSubscriptionLimit)
	require.NoError(t, err)

	_, err = module.WebPush.UpsertLinkSubscription(
		ctx,
		link.LinkID,
		"https://push.example/limit/new",
		"p256dh",
		"auth",
	)
	require.ErrorIs(t, err, ErrSpaceWebPushLinkSubscriptionLimit)

	_, err = module.WebPush.UpsertLinkSubscription(
		ctx,
		link.LinkID,
		"https://push.example/limit/1",
		"updated-p256dh",
		"auth",
	)
	require.NoError(t, err)
}
