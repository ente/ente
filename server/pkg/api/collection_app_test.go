package api

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/controller/access"
	castctrl "github.com/ente/museum/pkg/controller/cast"
	"github.com/ente/museum/pkg/controller/collections"
	"github.com/ente/museum/pkg/controller/public"
	"github.com/ente/museum/pkg/middleware"
	"github.com/ente/museum/pkg/repo"
	castrepo "github.com/ente/museum/pkg/repo/cast"
	publicrepo "github.com/ente/museum/pkg/repo/public"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/gin-gonic/gin"
	"github.com/patrickmn/go-cache"
	"github.com/stretchr/testify/require"
)

func TestCollectionAppIsolation(t *testing.T) {
	for _, app := range []ente.App{ente.Photos, ente.Locker} {
		t.Run(string(app), func(t *testing.T) {
			testutil.WithServerRoot(t)
			db := testutil.RequireTestDB(t)
			testutil.ResetTables(t, db)
			_, err := db.Exec(`DELETE FROM queue WHERE queue_name = $1`, repo.TrashCollectionQueueV3)
			require.NoError(t, err)
			t.Cleanup(func() {
				_, err := db.Exec(`DELETE FROM queue WHERE queue_name = $1`, repo.TrashCollectionQueueV3)
				require.NoError(t, err)
				testutil.ResetTables(t, db)
			})
			ownerID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1, Email: "owner@ente.com", CreationTime: 1})
			otherID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 2, Email: "other@ente.com", CreationTime: 1})
			linkRepo := publicrepo.NewCollectionLinkRepository(db, "")
			collectionRepo := &repo.CollectionRepository{
				DB: db, CollectionLinkRepo: linkRepo, QueueRepo: &repo.QueueRepository{DB: db},
				SecretEncryptionKey: testutil.SecretEncryptionKey(),
			}
			castRepo := &castrepo.Repository{DB: db}
			accessCtrl := access.NewAccessController(collectionRepo, nil)
			owned := make(map[ente.App]int64)
			shared := make(map[ente.App]int64)
			for _, collectionApp := range []ente.App{ente.Photos, ente.Locker} {
				for _, userID := range []int64{ownerID, otherID} {
					collection, err := collectionRepo.Create(ente.Collection{
						Owner: ente.CollectionUser{ID: userID}, App: string(collectionApp), Type: "album",
						EncryptedKey: "key", KeyDecryptionNonce: "nonce", Name: "collection", UpdationTime: 1,
					})
					require.NoError(t, err)
					if userID == ownerID {
						owned[collectionApp] = collection.ID
						require.NoError(t, linkRepo.Insert(t.Context(), collection.ID, string(collectionApp), 0, 0, false, false, nil))
						code, err := castRepo.AddCode(t.Context(), "key", nil, "127.0.0.1", "device")
						require.NoError(t, err)
						_, err = castRepo.InsertCastData(t.Context(), ownerID, code, collection.ID, string(collectionApp), "payload")
						require.NoError(t, err)
					} else {
						shared[collectionApp] = collection.ID
						_, err = db.Exec(`INSERT INTO collection_shares(collection_id, from_user_id, to_user_id, encrypted_key, updation_time, role_type, shared_at)
							VALUES ($1, $2, $3, 'shared-key', 1, $4, 1)`, collection.ID, otherID, ownerID, ente.VIEWER)
						require.NoError(t, err)
					}
				}
			}
			userAuthRepo := &repo.UserAuthRepository{DB: db}
			const token = "collection-app-test-token"
			require.NoError(t, userAuthRepo.AddToken(ownerID, app, token, "127.0.0.1", "test"))
			authMiddleware := &middleware.AuthMiddleware{UserAuthRepo: userAuthRepo, Cache: cache.New(time.Minute, time.Minute)}
			collectionHandler := &CollectionHandler{Controller: &collections.CollectionController{
				AccessCtrl: accessCtrl, CollectionRepo: collectionRepo, CastRepo: castRepo,
				CollectionLinkCtrl: &public.CollectionLinkController{CollectionLinkRepo: linkRepo},
			}}
			gin.SetMode(gin.TestMode)
			router := gin.New()
			storage := router.Group("/", authMiddleware.TokenAuthMiddleware(nil), middleware.RejectAuthApp())
			storage.GET("/collections/:collectionID", collectionHandler.GetCollectionByID)
			storage.DELETE("/collections/v3/:collectionID", collectionHandler.TrashV3)
			request := func(method, path string, clientApp ente.App) *httptest.ResponseRecorder {
				req := httptest.NewRequest(method, path, nil)
				req.Header.Set("X-Auth-Token", token)
				req.Header.Set("X-Client-Package", "io.ente."+string(clientApp))
				recorder := httptest.NewRecorder()
				router.ServeHTTP(recorder, req)
				return recorder
			}
			otherApp := ente.Photos
			if app == ente.Photos {
				otherApp = ente.Locker
			}
			t.Run("point_access", func(t *testing.T) {
				for _, ids := range []map[ente.App]int64{owned, shared} {
					for _, targetApp := range []ente.App{app, otherApp} {
						response := request(http.MethodGet, fmt.Sprintf("/collections/%d", ids[targetApp]), app)
						wantStatus := http.StatusForbidden
						if targetApp == app {
							wantStatus = http.StatusOK
						}
						require.Equal(t, wantStatus, response.Code, response.Body.String())
					}
				}
			})
			t.Run("cross_app_delete", func(t *testing.T) {
				id := owned[otherApp]
				path := fmt.Sprintf("/collections/v3/%d?collectionID=%d&keepFiles=false", id, id)
				response := request(http.MethodDelete, path, app)
				require.Equal(t, http.StatusForbidden, response.Code, response.Body.String())
				response = request(http.MethodDelete, path, otherApp)
				require.Equal(t, http.StatusUnauthorized, response.Code, response.Body.String())
				collection, err := collectionRepo.Get(id)
				require.NoError(t, err)
				require.False(t, collection.IsDeleted)
				require.Len(t, collection.PublicURLs, 1)
				_, _, err = castRepo.GetCollectionAndCasterIDForToken(t.Context(), string(otherApp))
				require.NoError(t, err)
				var queued bool
				require.NoError(t, db.QueryRow(`SELECT EXISTS (SELECT 1 FROM queue WHERE queue_name = $1 AND item = $2)`, repo.TrashCollectionQueueV3, strconv.FormatInt(id, 10)).Scan(&queued))
				require.False(t, queued)
			})
			t.Run("same_app_delete", func(t *testing.T) {
				id := owned[app]
				response := request(http.MethodDelete, fmt.Sprintf("/collections/v3/%d?collectionID=%d&keepFiles=false", id, id), app)
				require.Equal(t, http.StatusOK, response.Code, response.Body.String())
				collection, err := collectionRepo.Get(id)
				require.NoError(t, err)
				require.True(t, collection.IsDeleted)
				var queued bool
				require.NoError(t, db.QueryRow(`SELECT EXISTS (SELECT 1 FROM queue WHERE queue_name = $1 AND item = $2)`, repo.TrashCollectionQueueV3, strconv.FormatInt(id, 10)).Scan(&queued))
				require.True(t, queued)
			})
			t.Run("cast_access", func(t *testing.T) {
				ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
				ctx.Request = httptest.NewRequest(http.MethodGet, "/cast/collection", nil)
				ctx.Request.Header.Set("X-Client-Package", "io.ente."+string(app))
				_, present := auth.GetAuthenticatedApp(ctx)
				require.False(t, present)
				castCtrl := castctrl.NewController(castRepo, accessCtrl)
				castCtx, err := castCtrl.GetCollectionAndCasterIDForToken(ctx, string(otherApp))
				require.NoError(t, err)
				require.Equal(t, owned[otherApp], castCtx.CollectionID)
				require.Equal(t, ownerID, castCtx.UserID)
			})
			t.Run("non_member_access", func(t *testing.T) {
				_, err := db.Exec(`DELETE FROM collection_shares WHERE to_user_id = $1`, ownerID)
				require.NoError(t, err)
				for _, id := range shared {
					response := request(http.MethodGet, fmt.Sprintf("/collections/%d", id), app)
					require.Equal(t, http.StatusNotFound, response.Code, response.Body.String())
				}
			})
		})
	}
}
