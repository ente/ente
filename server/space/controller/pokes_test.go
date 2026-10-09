package controller

import (
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/space/models"
	"github.com/stretchr/testify/require"
)

func TestPokesRequireFriendshipAndNotifyOnlyOnce(t *testing.T) {
	_, repos, ctx := setupMessagesControllerTest(t)
	notifier := newRecordingSpaceActivityNotifier()
	controller := NewModule(repos, nil, notifier, nil).Pokes
	aliceID, alice := createMessageControllerUserAndSpace(t, repos, "alice-pokes", "alice-pokes-public")
	bobID, bob := createMessageControllerUserAndSpace(t, repos, "bob-pokes", "bob-pokes-public")
	require.Error(t, controller.Create(ctx, alice, alice.SpaceID, models.CreatePokeRequest{ClientRequestID: "self"}))
	require.ErrorIs(t, controller.Create(ctx, alice, bob.SpaceID, models.CreatePokeRequest{ClientRequestID: "stranger"}), ente.ErrPermissionDenied)
	require.NoError(t, testAddFriend(ctx, repos, bobID, bob.SpaceID, alice.SpaceID, "alice-share-key", 1, "bob-share-key", 1))
	require.Error(t, controller.Create(ctx, alice, bob.SpaceID, models.CreatePokeRequest{}))
	requireNoSpaceActivity(t, notifier)
	request := models.CreatePokeRequest{ClientRequestID: "poke-request-1"}
	require.NoError(t, controller.Create(ctx, alice, bob.SpaceID, request))
	event := requireSpaceActivity(t, notifier)
	require.Equal(t, spaceActivityPokeSent, event.event)
	require.Equal(t, aliceID, event.actorUserID)
	require.Equal(t, []int64{bobID}, event.recipientIDs)
	require.NoError(t, controller.Create(ctx, alice, bob.SpaceID, request))
	requireNoSpaceActivity(t, notifier)
}
