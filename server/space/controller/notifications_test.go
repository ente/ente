package controller

import (
	"context"
	"crypto/ecdh"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"testing"
	"time"

	webpush "github.com/SherClockHolmes/webpush-go"
	timeutil "github.com/ente/museum/pkg/utils/time"
	"github.com/ente/museum/space/models"
	"github.com/ente/museum/space/repo"
	"github.com/stretchr/testify/require"
)

type recordedSpaceActivity struct {
	event        string
	actorUserID  int64
	actorSpaceID string
	actorSlug    string
	recipientIDs []int64
}

type recordingSpaceActivityNotifier struct {
	events chan recordedSpaceActivity
}

func newRecordingSpaceActivityNotifier() *recordingSpaceActivityNotifier {
	return &recordingSpaceActivityNotifier{events: make(chan recordedSpaceActivity, 8)}
}

func (n *recordingSpaceActivityNotifier) OnSpacePostCreated(actor SpaceActivityActor) {
	n.record(spaceActivityPostCreated, actor)
}

func (n *recordingSpaceActivityNotifier) OnSpacePostLiked(actor SpaceActivityActor, recipientUserID int64) {
	n.record(spaceActivityPostLiked, actor, recipientUserID)
}

func (n *recordingSpaceActivityNotifier) OnSpacePostReplied(actor SpaceActivityActor, recipientUserID int64) {
	n.record(spaceActivityPostReplied, actor, recipientUserID)
}

func (n *recordingSpaceActivityNotifier) OnSpaceMessageSent(actor SpaceActivityActor, recipientUserID int64) {
	n.record(spaceActivityMessageSent, actor, recipientUserID)
}

func (n *recordingSpaceActivityNotifier) OnSpaceMessageLiked(actor SpaceActivityActor, recipientUserID int64) {
	n.record(spaceActivityMessageLiked, actor, recipientUserID)
}

func (n *recordingSpaceActivityNotifier) OnSpaceFriendAdded(actor SpaceActivityActor, recipientUserID int64) {
	n.record(spaceActivityFriendAdded, actor, recipientUserID)
}

func (n *recordingSpaceActivityNotifier) OnSpaceFriendRequested(actor SpaceActivityActor, recipientUserID int64) {
	n.record(spaceActivityFriendRequested, actor, recipientUserID)
}

func (n *recordingSpaceActivityNotifier) record(event string, actor SpaceActivityActor, recipientIDs ...int64) {
	n.events <- recordedSpaceActivity{
		event:        event,
		actorUserID:  actor.UserID,
		actorSpaceID: actor.SpaceID,
		actorSlug:    actor.Slug,
		recipientIDs: append([]int64(nil), recipientIDs...),
	}
}

func requireSpaceActivity(t *testing.T, notifier *recordingSpaceActivityNotifier) recordedSpaceActivity {
	t.Helper()
	select {
	case event := <-notifier.events:
		return event
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for Space activity notification")
		return recordedSpaceActivity{}
	}
}

func requireNoSpaceActivity(t *testing.T, notifier *recordingSpaceActivityNotifier) {
	t.Helper()
	select {
	case event := <-notifier.events:
		t.Fatalf("unexpected Space activity notification: %+v", event)
	case <-time.After(100 * time.Millisecond):
	}
}

func TestSpaceWebPushCopyAndValidation(t *testing.T) {
	require.Equal(t, "@alice", spaceActivityActorLabel(" alice "))
	require.Equal(t, "A friend", spaceActivityActorLabel(" "))
	require.Equal(t, "/app/messages/space_id", conversationURL("space_id"))

	privateKey, err := ecdh.P256().GenerateKey(rand.Reader)
	require.NoError(t, err)
	p256dh := base64.RawURLEncoding.EncodeToString(privateKey.PublicKey().Bytes())
	auth := base64.RawURLEncoding.EncodeToString(make([]byte, 16))
	require.NoError(t, validateWebPushSubscription("https://push.example/subscription", p256dh, auth))
	require.Error(t, validateWebPushSubscription("http://push.example/subscription", p256dh, auth))
	require.Error(t, validateWebPushSubscription("https://user@push.example/subscription", p256dh, auth))
	require.Error(t, validateWebPushSubscription("https://push.example/subscription#fragment", p256dh, auth))
	require.Error(t, validateWebPushSubscription("https://push.example/subscription", "invalid", auth))
	require.Error(t, validateWebPushSubscription("https://push.example/subscription", p256dh, "invalid"))
}

func TestSpaceWebPushAddressMustBePublic(t *testing.T) {
	require.True(t, isPublicWebPushAddress(net.ParseIP("8.8.8.8")))
	require.True(t, isPublicWebPushAddress(net.ParseIP("2606:4700:4700::1111")))
	require.False(t, isPublicWebPushAddress(net.ParseIP("127.0.0.1")))
	require.False(t, isPublicWebPushAddress(net.ParseIP("10.0.0.1")))
	require.False(t, isPublicWebPushAddress(net.ParseIP("100.64.0.1")))
	require.False(t, isPublicWebPushAddress(net.ParseIP("192.0.2.1")))
	require.False(t, isPublicWebPushAddress(net.ParseIP("::1")))
	require.False(t, isPublicWebPushAddress(net.ParseIP("2001:db8::1")))
}

func TestSpaceWebPushConfigRequiresMatchingKeysAndBareSubscriber(t *testing.T) {
	privateKey, publicKey, err := webpush.GenerateVAPIDKeys()
	require.NoError(t, err)
	config := NewSpaceWebPushConfig(publicKey, privateKey, "security@ente.io")
	require.NotNil(t, config)
	require.Equal(t, publicKey, config.publicKey)

	otherPrivateKey, _, err := webpush.GenerateVAPIDKeys()
	require.NoError(t, err)
	require.Nil(t, NewSpaceWebPushConfig(publicKey, otherPrivateKey, "security@ente.io"))
	require.Nil(t, NewSpaceWebPushConfig(publicKey, privateKey, "mailto:security@ente.io"))
	require.Nil(t, NewSpaceWebPushConfig("", "", ""))
}

func newSpaceWebPushTestConfig(t *testing.T) *SpaceWebPushConfig {
	t.Helper()
	privateKey, publicKey, err := webpush.GenerateVAPIDKeys()
	require.NoError(t, err)
	config := NewSpaceWebPushConfig(publicKey, privateKey, "security@ente.io")
	require.NotNil(t, config)
	return config
}

func TestUnconfiguredSpaceWebPushSenderIsUnavailable(t *testing.T) {
	sender := NewSpaceWebPushSender(&repo.WebPushRepository{}, nil)
	require.False(t, sender.available())
	sender.OnSpacePostReplied(SpaceActivityActor{UserID: 1, SpaceID: "alice_space", Slug: "alice"}, 2)
}

func TestSpaceWebPushDeduplicatesSharedEndpointForAccount(t *testing.T) {
	subscriptions := deduplicateSpaceWebPushSubscriptions([]repo.SpaceWebPushSubscriptionRecord{
		{Endpoint: "https://push.example/shared", TargetID: "public", Public: true},
		{Endpoint: "https://push.example/shared", TargetID: "account"},
		{Endpoint: "https://push.example/other", TargetID: "other", Public: true},
	})
	require.Equal(t, []repo.SpaceWebPushSubscriptionRecord{
		{Endpoint: "https://push.example/shared", TargetID: "account"},
		{Endpoint: "https://push.example/other", TargetID: "other", Public: true},
	}, subscriptions)
}

func TestNewPostNotifiesWithNoAccountFriends(t *testing.T) {
	_, repos, _ := setupPostsControllerTest(t)
	notifier := newRecordingSpaceActivityNotifier()
	posts := NewModule(repos, nil, notifier, nil).Posts

	posts.notifyFriendsOfNewPost(SpaceActivityActor{UserID: 1, SpaceID: "space_id", Slug: "alice"})

	require.Equal(t, recordedSpaceActivity{
		event:        spaceActivityPostCreated,
		actorUserID:  1,
		actorSpaceID: "space_id",
		actorSlug:    "alice",
	}, requireSpaceActivity(t, notifier))
}

func TestPostLikeSendsActivityOnlyOnLikeTransition(t *testing.T) {
	_, repos, ctx := setupPostsControllerTest(t)
	notifier := newRecordingSpaceActivityNotifier()
	posts := NewModule(repos, nil, notifier, nil).Posts
	aliceID := insertSpaceControllerUser(t, repos, "alice-post-like-push@example.com", "alice-public")
	bobID := insertSpaceControllerUser(t, repos, "bob-post-like-push@example.com", "bob-public")
	aliceSpace, err := testCreateSpace(ctx, repos, aliceID, "alice_post_like_push", "alice-space-key", "alice-post-public", "alice-post-secret", "nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, repos, bobID, "bob_post_like_push", "bob-space-key", "bob-post-public", "bob-post-secret", "nonce", "bob-profile")
	require.NoError(t, err)
	require.NoError(t, testAddFriend(ctx, repos, bobID, bobSpace.SpaceID, aliceSpace.SpaceID, "alice-share-key", aliceSpace.CurrentVersion, "bob-share-key", bobSpace.CurrentVersion))
	postID, err := testCreatePost(ctx, repos, aliceID, aliceSpace.SpaceID, "post-key", nil, aliceSpace.CurrentVersion, nil)
	require.NoError(t, err)

	_, err = posts.SetLike(ctx, bobSpace, postID, true)
	require.NoError(t, err)
	expected := recordedSpaceActivity{
		event:        spaceActivityPostLiked,
		actorUserID:  bobID,
		actorSpaceID: bobSpace.SpaceID,
		actorSlug:    bobSpace.SpaceSlug,
		recipientIDs: []int64{aliceID},
	}
	require.Equal(t, expected, requireSpaceActivity(t, notifier))

	_, err = posts.SetLike(ctx, bobSpace, postID, true)
	require.NoError(t, err)
	requireNoSpaceActivity(t, notifier)
	_, err = posts.SetLike(ctx, bobSpace, postID, false)
	require.NoError(t, err)
	requireNoSpaceActivity(t, notifier)
	_, err = posts.SetLike(ctx, bobSpace, postID, true)
	require.NoError(t, err)
	require.Equal(t, expected, requireSpaceActivity(t, notifier))
}

func TestMessageActivitiesAndLikeTransition(t *testing.T) {
	_, repos, ctx := setupMessagesControllerTest(t)
	notifier := newRecordingSpaceActivityNotifier()
	messages := NewModule(repos, nil, notifier, nil).Messages
	aliceID, aliceSpace := createMessageControllerUserAndSpace(t, repos, "alice-message-push", "alice-public")
	bobID, bobSpace := createMessageControllerUserAndSpace(t, repos, "bob-message-push", "bob-public")
	require.NoError(t, testAddFriend(ctx, repos, bobID, bobSpace.SpaceID, aliceSpace.SpaceID, "alice-share-key", aliceSpace.CurrentVersion, "bob-share-key", bobSpace.CurrentVersion))
	request := models.CreateMessageRequest{
		MessageCipher:                spaceTestB64("cipher"),
		SenderEncryptedMessageKey:    spaceTestB64("sender-key"),
		RecipientEncryptedMessageKey: spaceTestB64("recipient-key"),
	}

	message, err := messages.Create(ctx, aliceSpace, bobSpace.SpaceID, request)
	require.NoError(t, err)
	require.Equal(t, recordedSpaceActivity{
		event:        spaceActivityMessageSent,
		actorUserID:  aliceID,
		actorSpaceID: aliceSpace.SpaceID,
		actorSlug:    aliceSpace.SpaceSlug,
		recipientIDs: []int64{bobID},
	}, requireSpaceActivity(t, notifier))

	_, err = messages.SetLike(ctx, bobSpace, message.MessageID, true)
	require.NoError(t, err)
	expectedLike := recordedSpaceActivity{
		event:        spaceActivityMessageLiked,
		actorUserID:  bobID,
		actorSpaceID: bobSpace.SpaceID,
		actorSlug:    bobSpace.SpaceSlug,
		recipientIDs: []int64{aliceID},
	}
	require.Equal(t, expectedLike, requireSpaceActivity(t, notifier))
	_, err = messages.SetLike(ctx, bobSpace, message.MessageID, true)
	require.NoError(t, err)
	requireNoSpaceActivity(t, notifier)
	_, err = messages.SetLike(ctx, bobSpace, message.MessageID, false)
	require.NoError(t, err)
	requireNoSpaceActivity(t, notifier)

	postID, err := testCreatePost(ctx, repos, aliceID, aliceSpace.SpaceID, "post-key", nil, aliceSpace.CurrentVersion, nil)
	require.NoError(t, err)
	_, err = messages.ReplyToPost(ctx, bobSpace, postID, request)
	require.NoError(t, err)
	require.Equal(t, recordedSpaceActivity{
		event:        spaceActivityPostReplied,
		actorUserID:  bobID,
		actorSpaceID: bobSpace.SpaceID,
		actorSlug:    bobSpace.SpaceSlug,
		recipientIDs: []int64{aliceID},
	}, requireSpaceActivity(t, notifier))
}

func TestFriendActivitiesOnlyOnRelationshipTransitions(t *testing.T) {
	_, repos, ctx := setupFriendsControllerTest(t)
	notifier := newRecordingSpaceActivityNotifier()
	friends := NewModule(repos, nil, notifier, nil).Friends
	aliceID := insertSpaceControllerUser(t, repos, "alice-friend-push@example.com", "alice-public")
	bobID := insertSpaceControllerUser(t, repos, "bob-friend-push@example.com", "bob-public")
	aliceSpace, err := testCreateSpace(ctx, repos, aliceID, "alice_friend_push", "alice-space-key", "alice-public", "alice-secret", "nonce", "alice-profile")
	require.NoError(t, err)
	bobSpace, err := testCreateSpace(ctx, repos, bobID, "bob_friend_push", "bob-space-key", "bob-public", "bob-secret", "nonce", "bob-profile")
	require.NoError(t, err)
	request := models.AddFriendPayload{
		TargetSpaceID:                 aliceSpace.SpaceID,
		RequesterFriendSealedSpaceKey: base64.StdEncoding.EncodeToString([]byte("bob-requester-key")),
		RequesterKeyVersion:           bobSpace.CurrentVersion,
	}

	_, err = friends.Add(ctx, bobSpace, request)
	require.NoError(t, err)
	require.Equal(t, recordedSpaceActivity{
		event:        spaceActivityFriendRequested,
		actorUserID:  bobID,
		actorSpaceID: bobSpace.SpaceID,
		actorSlug:    bobSpace.SpaceSlug,
		recipientIDs: []int64{aliceID},
	}, requireSpaceActivity(t, notifier))
	_, err = friends.Add(ctx, bobSpace, request)
	require.NoError(t, err)
	requireNoSpaceActivity(t, notifier)

	requests, err := friends.ListRequests(ctx, aliceSpace)
	require.NoError(t, err)
	require.Len(t, requests, 1)
	_, err = friends.ConfirmRequest(ctx, aliceSpace, requests[0].RequestID, models.ConfirmFriendRequestPayload{
		TargetFriendSealedSpaceKey: base64.StdEncoding.EncodeToString([]byte("alice-target-key")),
		TargetKeyVersion:           aliceSpace.CurrentVersion,
	})
	require.NoError(t, err)
	require.Equal(t, recordedSpaceActivity{
		event:        spaceActivityFriendAdded,
		actorUserID:  aliceID,
		actorSpaceID: aliceSpace.SpaceID,
		actorSlug:    aliceSpace.SpaceSlug,
		recipientIDs: []int64{bobID},
	}, requireSpaceActivity(t, notifier))
}

func TestSpaceWebPushSenderUsesGenericPayloadAndPrunesDeadEndpoint(t *testing.T) {
	_, repos, ctx := setupPostsControllerTest(t)
	recipientID := insertSpaceControllerUser(t, repos, "space-push-recipient@example.com", "recipient-public")
	sessionHash := []byte("space-push-session-hash")
	require.NoError(t, repos.Sessions.CreateBrowserSession(ctx, sessionHash, recipientID, "wrap-key", timeutil.NDaysFromNow(1)))
	_, err := repos.WebPush.UpsertAccountSubscription(ctx, sessionHash, "https://push.example/subscription", "p256dh", "auth")
	require.NoError(t, err)

	config := newSpaceWebPushTestConfig(t)

	originalSend := sendSpaceWebPush
	t.Cleanup(func() { sendSpaceWebPush = originalSend })
	var payload spaceWebPushPayload
	sendSpaceWebPush = func(_ context.Context, message []byte, subscription *webpush.Subscription, options *webpush.Options) (*http.Response, error) {
		require.Equal(t, "https://push.example/subscription", subscription.Endpoint)
		require.Equal(t, uint32(spaceWebPushRecordSize), options.RecordSize)
		require.Equal(t, spaceWebPushTTLSeconds, options.TTL)
		require.Equal(t, webpush.UrgencyNormal, options.Urgency)
		require.Equal(t, "security@ente.io", options.Subscriber)
		require.NoError(t, json.Unmarshal(message, &payload))
		return &http.Response{StatusCode: http.StatusGone, Body: io.NopCloser(strings.NewReader(""))}, nil
	}

	sender := NewSpaceWebPushSender(repos.WebPush, config)
	sender.OnSpacePostReplied(SpaceActivityActor{UserID: 1, SpaceID: "alice_space", Slug: "alice"}, recipientID)
	require.Equal(t, spaceWebPushPayload{
		Title:  "Ente Space",
		Body:   "@alice replied to your post",
		Action: "Check it out",
		URL:    "/app/messages/alice_space",
	}, payload)
	var count int
	require.NoError(t, repos.WebPush.DB.QueryRow(`SELECT COUNT(*) FROM space_web_push_subscriptions`).Scan(&count))
	require.Zero(t, count)
}

func TestPublicPostPushCarriesOnlyOpaqueLocalRouteTarget(t *testing.T) {
	config := newSpaceWebPushTestConfig(t)

	originalSend := sendSpaceWebPush
	t.Cleanup(func() { sendSpaceWebPush = originalSend })
	var payload spaceWebPushPayload
	sendSpaceWebPush = func(_ context.Context, message []byte, _ *webpush.Subscription, _ *webpush.Options) (*http.Response, error) {
		require.NoError(t, json.Unmarshal(message, &payload))
		return &http.Response{StatusCode: http.StatusCreated, Body: io.NopCloser(strings.NewReader(""))}, nil
	}

	sender := NewSpaceWebPushSender(nil, config)
	sender.send(
		SpaceActivityActor{UserID: 2, Slug: "alice"},
		"posted a new photo",
		"Check it out",
		spaceActivityPostCreated,
		"/app",
		[]repo.SpaceWebPushSubscriptionRecord{{
			Endpoint: "https://push.example/public",
			P256dh:   "p256dh",
			Auth:     "auth",
			TargetID: "wpt_public_target",
			Public:   true,
		}},
	)
	require.Equal(t, spaceWebPushPayload{
		Title:    "Ente Space",
		Body:     "@alice posted a new photo",
		Action:   "Check it out",
		TargetID: "wpt_public_target",
	}, payload)
}

func TestSpaceWebPushSendRateAppliesOncePerActivity(t *testing.T) {
	config := newSpaceWebPushTestConfig(t)

	originalSend := sendSpaceWebPush
	t.Cleanup(func() { sendSpaceWebPush = originalSend })
	sent := make(chan struct{}, 51)
	sendSpaceWebPush = func(_ context.Context, _ []byte, _ *webpush.Subscription, _ *webpush.Options) (*http.Response, error) {
		sent <- struct{}{}
		return &http.Response{StatusCode: http.StatusCreated, Body: io.NopCloser(strings.NewReader(""))}, nil
	}

	subscriptions := make([]repo.SpaceWebPushSubscriptionRecord, 51)
	for index := range subscriptions {
		subscriptions[index] = repo.SpaceWebPushSubscriptionRecord{
			Endpoint: fmt.Sprintf("https://push.example/%d", index),
			P256dh:   "p256dh",
			Auth:     "auth",
		}
	}
	NewSpaceWebPushSender(nil, config).send(
		SpaceActivityActor{UserID: 3, Slug: "alice"},
		"posted a new photo",
		"Check it out",
		spaceActivityPostCreated,
		"/app",
		subscriptions,
	)
	require.Equal(t, len(subscriptions), len(sent))
}
