package api

import (
	"crypto/sha256"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/ente/museum/internal/testutil"
	timeutil "github.com/ente/museum/pkg/utils/time"
	"github.com/ente/museum/space/controller"
	"github.com/ente/museum/space/models"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestNotificationsAPIIsRecipientScoped(t *testing.T) {
	handlers, repos, ownerID := setupSpaceSessionAPITest(t, nil)
	ctx := t.Context()
	owner, err := testCreateSpace(ctx, repos, ownerID, "notification_owner", "root", "public", "secret", "nonce", "profile")
	require.NoError(t, err)
	friendID := testutil.InsertUser(t, repos.Spaces.DB, testutil.UserFixture{Email: "notification-friend@example.com", CreationTime: timeutil.Microseconds()})
	friend, err := testCreateSpace(ctx, repos, friendID, "notification_friend", "root", "public", "secret", "nonce", "profile")
	require.NoError(t, err)
	request, _, _, err := repos.Friends.CreateFriendRequest(ctx, friendID, friend.SpaceID, owner.SpaceID, []byte("share"), 1)
	require.NoError(t, err)
	_, _, err = repos.Friends.ConfirmFriendRequest(ctx, owner.SpaceID, request.RequestID, []byte("share"), 1)
	require.NoError(t, err)
	postID, _, err := repos.Posts.CreatePost(ctx, owner.SpaceID, []byte("key"), nil, 1, nil, "")
	require.NoError(t, err)
	_, err = repos.Posts.SetLikeWithCreated(ctx, postID, friend.SpaceID, true)
	require.NoError(t, err)
	sessionToken := "notification-owner-session"
	sessionHash := sha256.Sum256([]byte(sessionToken))
	require.NoError(t, repos.Sessions.CreateBrowserSession(ctx, sessionHash[:], ownerID, "wrap-key", timeutil.NDaysFromNow(1)))
	router := gin.New()
	private := router.Group("", handlers.RequireSpaceBrowserSession())
	Register(private, router.Group(""), handlers)
	serve := func(method, path, body string) *httptest.ResponseRecorder {
		req := httptest.NewRequest(method, path, strings.NewReader(body))
		req.Header.Set(controller.SpaceBrowserSessionTokenHeader, sessionToken)
		req.Header.Set("Content-Type", "application/json")
		recorder := httptest.NewRecorder()
		router.ServeHTTP(recorder, req)
		return recorder
	}
	response := serve(http.MethodGet, "/spaces/"+owner.SpaceID+"/notifications?limit=1", "")
	require.Equal(t, http.StatusOK, response.Code, response.Body.String())
	var page models.NotificationPage
	require.NoError(t, json.Unmarshal(response.Body.Bytes(), &page))
	require.Len(t, page.Items, 1)
	require.NotNil(t, page.Items[0].PostID)
	require.Equal(t, postID, *page.Items[0].PostID)
	require.Equal(t, friend.SpaceID, page.Items[0].Actors[0].SpaceID)
	require.Equal(t, int64(1), page.Items[0].ActorCount)
	require.True(t, page.Items[0].Unread)
	require.NotEmpty(t, page.NextCursor)
	olderResponse := serve(http.MethodGet, "/spaces/"+owner.SpaceID+"/notifications?cursor="+page.NextCursor, "")
	require.Equal(t, http.StatusOK, olderResponse.Code, olderResponse.Body.String())
	var olderPage models.NotificationPage
	require.NoError(t, json.Unmarshal(olderResponse.Body.Bytes(), &olderPage))
	require.Len(t, olderPage.Items, 1)
	require.Equal(t, "friend_accepted", olderPage.Items[0].Kind)
	require.Equal(t, friend.SpaceID, olderPage.Items[0].Actors[0].SpaceID)
	require.False(t, olderPage.Items[0].Unread)
	require.Nil(t, olderPage.Items[0].FriendRequestID)
	response = serve(http.MethodGet, "/spaces/"+owner.SpaceID+"/notifications/unread", "")
	require.JSONEq(t, `{"unread":true}`, response.Body.String())
	response = serve(http.MethodGet, "/spaces/"+friend.SpaceID+"/notifications", "")
	require.Equal(t, http.StatusForbidden, response.Code)
	response = serve(http.MethodPost, "/spaces/"+friend.SpaceID+"/notifications/read", `{"notificationIds":["`+page.Items[0].NotificationID+`"]}`)
	require.Equal(t, http.StatusForbidden, response.Code)
	response = serve(http.MethodPost, "/spaces/"+owner.SpaceID+"/notifications/read", `{"notificationIds":[]}`)
	require.Equal(t, http.StatusBadRequest, response.Code)
	response = serve(http.MethodPost, "/spaces/"+owner.SpaceID+"/notifications/read", `{"notificationIds":["`+page.Items[0].NotificationID+`"]}`)
	require.Equal(t, http.StatusOK, response.Code)
	response = serve(http.MethodGet, "/spaces/"+owner.SpaceID+"/notifications/unread", "")
	require.JSONEq(t, `{"unread":false}`, response.Body.String())
	require.NoError(t, repos.Friends.DeleteFriendship(ctx, owner.SpaceID, friend.SpaceID))
	_, err = repos.Spaces.DB.ExecContext(ctx, `INSERT INTO space_profile_assets (space_id, asset_type, object_id, bucket_id, key_version) VALUES ($1, 'avatar', 'private-avatar', 'test-bucket', 1)`, friend.SpaceID)
	require.NoError(t, err)
	request, _, _, err = repos.Friends.CreateFriendRequest(ctx, friendID, friend.SpaceID, owner.SpaceID, []byte("share"), 1)
	require.NoError(t, err)
	response = serve(http.MethodGet, "/spaces/"+owner.SpaceID+"/notifications", "")
	require.Equal(t, http.StatusOK, response.Code, response.Body.String())
	page = models.NotificationPage{}
	require.NoError(t, json.Unmarshal(response.Body.Bytes(), &page))
	require.Len(t, page.Items, 1)
	require.Equal(t, "friend_request", page.Items[0].Kind)
	require.NotNil(t, page.Items[0].FriendRequestID)
	require.Equal(t, request.RequestID, *page.Items[0].FriendRequestID)
	require.Nil(t, page.Items[0].PostID)
	require.Empty(t, page.Items[0].Actors[0].EncryptedProfile)
	require.Nil(t, page.Items[0].Actors[0].Avatar)
	response = serve(http.MethodGet, "/spaces/"+owner.SpaceID+"/unread", "")
	require.JSONEq(t, `{"notificationsUnread":false}`, response.Body.String())
	response = serve(http.MethodGet, "/spaces/"+owner.SpaceID+"/conversations", "")
	require.Equal(t, http.StatusOK, response.Code, response.Body.String())
	require.NotContains(t, response.Body.String(), "pendingRequests")
}
