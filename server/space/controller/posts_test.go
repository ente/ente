package controller

import (
	"crypto/sha256"
	"database/sql"
	"fmt"
	"net/http"
	"net/http/httptest"
	"slices"
	"strconv"
	"sync/atomic"
	"testing"

	"github.com/ente/museum/pkg/utils/config"
	"github.com/ente/museum/pkg/utils/s3config"
	timeutil "github.com/ente/museum/pkg/utils/time"
	"github.com/ente/museum/space/models"
	spacerepo "github.com/ente/museum/space/repo"
	"github.com/spf13/viper"
	"github.com/stretchr/testify/require"
)

func TestPostLikeRejectsOwnPost(t *testing.T) {
	controller, repos, ctx := setupPostsControllerTest(t)
	aliceID := insertSpaceControllerUser(t, repos, "alice-own-post-like@example.com", "alice-public")
	aliceSpace, err := testCreateSpace(ctx, repos, aliceID, "alice_own_post_like", "alice-space-key", "alice-own-post-like-public", "alice-own-post-like-secret", "alice-own-post-like-secret-nonce", "alice-profile")
	require.NoError(t, err)
	postID, err := testCreatePost(ctx, repos, aliceID, aliceSpace.SpaceID, "post-key", nil, aliceSpace.CurrentVersion, nil)
	require.NoError(t, err)

	_, err = controller.SetLike(ctx, aliceSpace, postID, true)
	require.Error(t, err)
	require.Contains(t, err.Error(), "cannot like your own post")
}

func TestCreatePostRequiresAssetMetadataCipher(t *testing.T) {
	controller, repos, ctx := setupPostsControllerTest(t)
	aliceID := insertSpaceControllerUser(t, repos, "alice-metadata-post@example.com", "alice-public")
	aliceSpace, err := testCreateSpace(ctx, repos, aliceID, "alice_metadata_post", "alice-space-key", "alice-metadata-post-public", "alice-metadata-post-secret", "alice-metadata-post-secret-nonce", "alice-profile")
	require.NoError(t, err)

	_, err = controller.Create(ctx, aliceSpace, models.CreatePostRequest{
		EncryptedPostKey: "cG9zdC1rZXk=",
		KeyVersion:       aliceSpace.CurrentVersion,
		Objects: []models.PostObjectPayload{{
			ObjectKey: "space/alice-metadata-post/posts/object",
		}},
	})

	require.Error(t, err)
	require.Contains(t, err.Error(), "metadataCipher is required")
}

func TestCreatePostAcceptsUpToTenObjects(t *testing.T) {
	for _, test := range []struct {
		count      int
		videos     int
		abandoned  int
		concurrent bool
		legacy     bool
	}{
		{count: 1},
		{count: 1, videos: 1},
		{count: 1, legacy: true},
		{count: 1, videos: 1, legacy: true},
		{count: 2},
		{count: 2, videos: 1, concurrent: true},
		{count: 10},
		{count: 10, abandoned: 1},
		{count: 10, abandoned: 10},
		{count: 10, videos: 5},
		{count: 10, videos: 10, abandoned: 20},
	} {
		t.Run(fmt.Sprintf("%d_items_%d_videos_after_%d_abandoned_concurrent_%t_legacy_%t", test.count, test.videos, test.abandoned, test.concurrent, test.legacy), func(t *testing.T) {
			controller, repos, ctx := setupPostsControllerTest(t)
			notifier := newRecordingSpaceActivityNotifier()
			controller.ActivityNotifier = notifier
			firstHead := make(chan struct{})
			releaseFirstHead := make(chan struct{})
			var headCount atomic.Int32
			storage := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.Method != http.MethodHead {
					w.WriteHeader(http.StatusMethodNotAllowed)
					return
				}
				if test.concurrent && headCount.Add(1) == 1 {
					close(firstHead)
					<-releaseFirstHead
				}
				w.Header().Set("Content-Length", "123")
			}))
			t.Cleanup(storage.Close)
			viper.Reset()
			t.Cleanup(viper.Reset)
			require.NoError(t, config.ConfigureViper("local"))
			viper.Set("s3.b2-eu-cen.key", "test-key")
			viper.Set("s3.b2-eu-cen.secret", "test-secret")
			viper.Set("s3.b2-eu-cen.endpoint", storage.URL)
			viper.Set("s3.b2-eu-cen.region", "us-east-1")
			viper.Set("s3.b2-eu-cen.bucket", "test-bucket")
			viper.Set("s3.b2-eu-cen.use_path_style_urls", true)
			viper.Set(spaceAssetsPrimaryBucketConfigKey, "b2-eu-cen")
			repos.Assets.S3Config = s3config.NewS3Config()
			ownerID := insertSpaceControllerUser(t, repos, "multi-photo@example.com", "public")
			space, err := testCreateSpace(ctx, repos, ownerID, "multi_photo", "space-key", "public", "secret", "nonce", "profile")
			require.NoError(t, err)

			assets := &AssetsController{AssetsRepo: repos.Assets}
			reserve := func() string {
				response, err := assets.PresignUpload(ctx, space, models.PresignUploadRequest{
					Size:       123,
					ContentMD5: "XUFAKrxLKna5cZ2REBfFkg==",
				}, "space-test")
				require.NoError(t, err)
				return response.ObjectKey
			}
			abandoned := make([]string, test.abandoned)
			for i := range abandoned {
				abandoned[i] = reserve()
			}
			objects := make([]models.PostObjectPayload, test.count)
			for position := range test.count {
				objects[position] = models.PostObjectPayload{
					ObjectKey:      reserve(),
					Size:           123,
					Position:       position,
					MetadataCipher: "bWV0YWRhdGE=",
				}
				if position < test.videos {
					objects[position].Video = &models.PostObjectPayload{ObjectKey: reserve(), Size: 123, Position: position, MetadataCipher: "bWV0YWRhdGE="}
				}
			}
			requestObjects := slices.Clone(objects)
			slices.Reverse(requestObjects)
			caption := "Y2FwdGlvbg=="
			request := models.CreatePostRequest{
				ClientRequestID:  "retry-this-post",
				EncryptedPostKey: "cG9zdC1rZXk=",
				CaptionCipher:    &caption,
				KeyVersion:       space.CurrentVersion,
				Objects:          requestObjects,
			}
			if test.legacy {
				request.ClientRequestID = ""
			}
			var concurrentResponse *models.CreatePostResponse
			var concurrentError error
			concurrentDone := make(chan struct{})
			if test.concurrent {
				go func() {
					concurrentResponse, concurrentError = controller.Create(ctx, space, request)
					close(concurrentDone)
				}()
				<-firstHead
			}
			created, err := controller.Create(ctx, space, request)
			if test.concurrent {
				close(releaseFirstHead)
				<-concurrentDone
				require.NoError(t, concurrentError)
				require.Equal(t, created, concurrentResponse)
			}
			require.NoError(t, err)
			if !test.legacy {
				retried, err := controller.Create(ctx, space, request)
				require.NoError(t, err)
				require.Equal(t, created.PostID, retried.PostID)
			}
			require.Equal(t, created.PostID, requireSpaceActivity(t, notifier).postID)
			requireNoSpaceActivity(t, notifier)
			feed, err := controller.ListFeed(ctx, space, models.ListFeedRequest{Limit: 10})
			require.NoError(t, err)
			require.Len(t, feed.Items, 1)
			require.Equal(t, created.PostID, feed.Items[0].PostID)
			require.Equal(t, caption, feed.Items[0].CaptionCipher)
			require.Equal(t, objects, feed.Items[0].Objects)
			for _, object := range objects {
				if object.Video != nil {
					_, err := repos.Assets.GetTempObject(ctx, object.Video.ObjectKey, spacerepo.TempObjectPurposePost, &space.SpaceID)
					require.ErrorIs(t, err, sql.ErrNoRows)
				}
				_, err := repos.Assets.GetTempObject(ctx, object.ObjectKey, spacerepo.TempObjectPurposePost, &space.SpaceID)
				require.ErrorIs(t, err, sql.ErrNoRows)
			}
			for _, object := range objects {
				parts := []models.PostObjectPayload{object}
				if object.Video != nil {
					parts = append(parts, *object.Video)
				}
				for _, part := range parts {
					bucket, err := repos.Assets.GetAssetBucketID(ctx, space.SpaceID, part.ObjectKey)
					require.NoError(t, err)
					require.Equal(t, "b2-eu-cen", bucket)
				}
			}
			require.NoError(t, controller.Delete(ctx, space, created.PostID))
			for _, object := range objects {
				parts := []models.PostObjectPayload{object}
				if object.Video != nil {
					parts = append(parts, *object.Video)
				}
				for _, part := range parts {
					_, err := repos.Assets.GetAssetBucketID(ctx, space.SpaceID, part.ObjectKey)
					require.ErrorIs(t, err, sql.ErrNoRows)
					var queued bool
					err = repos.Assets.DB.QueryRowContext(ctx, `SELECT EXISTS (
                        SELECT 1 FROM space_temp_objects WHERE object_key = $1 AND purpose = $2
                        AND expires_at <= now_utc_micro_seconds() AND cleanup_after > now_utc_micro_seconds()
                    )`, part.ObjectKey, spacerepo.TempObjectPurposePost).Scan(&queued)
					require.NoError(t, err)
					require.True(t, queued)
				}
			}
			for _, objectKey := range abandoned {
				staged, err := repos.Assets.GetTempObject(ctx, objectKey, spacerepo.TempObjectPurposePost, &space.SpaceID)
				require.NoError(t, err)
				require.Equal(t, staged.ExpiresAt, staged.CleanupAfter)
			}
		})
	}
}

func TestCreatePostRejectsInvalidObjectCount(t *testing.T) {
	for _, test := range []struct {
		count   int
		message string
	}{
		{count: 0, message: "encryptedPostKey and objects are required"},
		{count: 11, message: "too many post objects"},
	} {
		t.Run(strconv.Itoa(test.count), func(t *testing.T) {
			_, err := (&PostsController{}).Create(t.Context(), &spacerepo.SpaceRecord{}, models.CreatePostRequest{
				EncryptedPostKey: "cG9zdC1rZXk=",
				KeyVersion:       1,
				Objects:          make([]models.PostObjectPayload, test.count),
			})
			require.ErrorContains(t, err, test.message)
		})
	}
}

func TestCreatePostRejectsInvalidObjectPosition(t *testing.T) {
	for _, position := range []int{-1, 10} {
		t.Run(strconv.Itoa(position), func(t *testing.T) {
			_, err := (&PostsController{}).Create(t.Context(), &spacerepo.SpaceRecord{}, models.CreatePostRequest{
				EncryptedPostKey: "cG9zdC1rZXk=",
				KeyVersion:       1,
				Objects: []models.PostObjectPayload{{
					ObjectKey: "photo",
					Position:  position,
				}},
			})
			require.ErrorContains(t, err, "invalid object position")
		})
	}
}

func TestCreatePostRejectsNestedVideo(t *testing.T) {
	_, err := (&PostsController{}).Create(t.Context(), &spacerepo.SpaceRecord{}, models.CreatePostRequest{
		EncryptedPostKey: "cG9zdC1rZXk=",
		KeyVersion:       1,
		Objects: []models.PostObjectPayload{{
			ObjectKey: "preview",
			Video: &models.PostObjectPayload{
				ObjectKey: "video",
				Video:     &models.PostObjectPayload{ObjectKey: "nested"},
			},
		}},
	})
	require.ErrorContains(t, err, "invalid nested video")
}

func TestListPostsHydratesPostAssets(t *testing.T) {
	controller, repos, ctx := setupPostsControllerTest(t)
	aliceID := insertSpaceControllerUser(t, repos, "alice-list-assets@example.com", "alice-public")
	aliceSpace, err := testCreateSpace(ctx, repos, aliceID, "alice_list_assets", "alice-space-key", "alice-list-assets-public", "alice-list-assets-secret", "alice-list-assets-secret-nonce", "alice-profile")
	require.NoError(t, err)
	objectKey := "space/alice-list-assets/post/full"
	err = repos.Assets.AddTempObject(ctx, spacerepo.SpaceTempObjectRecord{
		ObjectKey:    objectKey,
		SpaceID:      sql.NullString{String: aliceSpace.SpaceID, Valid: true},
		Purpose:      spacerepo.TempObjectPurposePost,
		BucketID:     "b2-eu-cen",
		ExpectedSize: 123,
		ExpiresAt:    timeutil.MicrosecondsAfterMinutes(30),
	})
	require.NoError(t, err)
	_, err = testCreatePost(ctx, repos, aliceID, aliceSpace.SpaceID, "post-key", nil, aliceSpace.CurrentVersion, []spacerepo.SpacePostAssetRecord{
		{
			ObjectKey:      objectKey,
			BucketID:       "b2-eu-cen",
			Size:           sql.NullInt64{Int64: 123, Valid: true},
			Position:       1,
			MetadataCipher: testSpaceBytes("metadata"),
		},
	})
	require.NoError(t, err)
	sessionHash := sha256.Sum256([]byte("alice-list-assets-session"))
	require.NoError(t, repos.Sessions.CreateBrowserSession(ctx, sessionHash[:], aliceID, "session-wrap-key", timeutil.MicrosecondsAfterMinutes(5)))
	ginCtx := newPublicSpaceContext()
	ginCtx.Request.Header.Set(SpaceBrowserSessionTokenHeader, "alice-list-assets-session")

	page, err := controller.List(ginCtx, models.ListPostsRequest{
		SpaceID: aliceSpace.SpaceID,
		Limit:   10,
	})
	require.NoError(t, err)
	require.Len(t, page.Items, 1)
	require.Len(t, page.Items[0].Objects, 1)
	require.Equal(t, objectKey, page.Items[0].Objects[0].ObjectKey)
	require.Equal(t, int64(123), page.Items[0].Objects[0].Size)
	require.Equal(t, 1, page.Items[0].Objects[0].Position)
	require.Equal(t, "bWV0YWRhdGE=", page.Items[0].Objects[0].MetadataCipher)
	feed, err := controller.ListFeed(ctx, aliceSpace, models.ListFeedRequest{Limit: 10})
	require.NoError(t, err)
	require.Equal(t, page.Items, feed.Items)

}
