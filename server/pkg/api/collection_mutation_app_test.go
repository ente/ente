package api

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/controller/access"
	"github.com/ente/museum/pkg/controller/collections"
	"github.com/ente/museum/pkg/controller/email"
	"github.com/ente/museum/pkg/controller/public"
	"github.com/ente/museum/pkg/middleware"
	"github.com/ente/museum/pkg/repo"
	castrepo "github.com/ente/museum/pkg/repo/cast"
	publicrepo "github.com/ente/museum/pkg/repo/public"
	"github.com/gin-gonic/gin"
	"github.com/patrickmn/go-cache"
	"github.com/spf13/viper"
	"github.com/stretchr/testify/require"
)

func TestCollectionMutationAppIsolation(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	silent := viper.GetBool("internal.silent")
	viper.Set("internal.silent", true)
	t.Cleanup(func() { viper.Set("internal.silent", silent) })
	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1, Email: "owner@ente.com", CreationTime: 1})
	memberID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 2, Email: "member@ente.com", CreationTime: 1})
	adminID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 3, Email: "admin@ente.com", CreationTime: 1})
	testutil.InsertSubscription(t, db, testutil.SubscriptionFixture{UserID: ownerID, Storage: 1 << 30, ExpiryTime: 4102444800000000})
	userRepo := &repo.UserRepository{DB: db, HashingKey: testutil.HashingKey(), SecretEncryptionKey: testutil.SecretEncryptionKey()}
	linkRepo := publicrepo.NewCollectionLinkRepository(db, "")
	collectionRepo := &repo.CollectionRepository{DB: db, CollectionLinkRepo: linkRepo, SecretEncryptionKey: testutil.SecretEncryptionKey()}
	h := &CollectionHandler{Controller: &collections.CollectionController{
		AccessCtrl: access.NewAccessController(collectionRepo, nil), CollectionRepo: collectionRepo,
		CastRepo: &castrepo.Repository{DB: db}, CollectionLinkCtrl: &public.CollectionLinkController{CollectionLinkRepo: linkRepo},
		BillingCtrl: &controller.BillingController{UserRepo: userRepo, BillingRepo: &repo.BillingRepository{DB: db}},
		UserLookup:  controller.NewUserLookupController(userRepo, nil), PushCtrl: &controller.PushController{},
		EmailCtrl: &email.EmailNotificationController{UserRepo: userRepo},
	}}
	userAuthRepo := &repo.UserAuthRepository{DB: db}
	authMiddleware := &middleware.AuthMiddleware{UserAuthRepo: userAuthRepo, Cache: cache.New(time.Minute, time.Minute)}
	router := gin.New()
	storage := router.Group("/collections", authMiddleware.TokenAuthMiddleware(nil), middleware.RejectAuthApp())
	storage.POST("/share-url", h.ShareURL)
	storage.PUT("/share-url", h.UpdateShareURL)
	storage.DELETE("/share-url/:collectionID", h.UnShareURL)
	storage.POST("/share", h.Share)
	storage.POST("/share/batch", h.BatchShare)
	storage.POST("/share/bulk", h.BulkShare)
	storage.POST("/unshare", h.UnShare)
	storage.POST("/unshare/bulk", h.BulkUnShare)
	storage.POST("/rename", h.Rename)
	storage.PUT("/magic-metadata", h.PrivateMagicMetadataUpdate)
	storage.PUT("/public-magic-metadata", h.PublicMagicMetadataUpdate)
	storage.POST("/join-link", h.JoinLink)
	storage.POST("/leave/:collectionID", h.Leave)
	storage.GET("/file", h.GetFile)
	actionRepo := &repo.CollectionActionsRepository{DB: db}
	actionHandler := &CollectionActionsHandler{Controller: &controller.CollectionActionsController{Repo: actionRepo}}
	actionsAPI := router.Group("/collection-actions", authMiddleware.TokenAuthMiddleware(nil), middleware.RejectAuthApp())
	actionsAPI.GET("/pending-remove", actionHandler.ListPendingRemove)
	actionsAPI.GET("/delete-suggestions", actionHandler.ListDeleteSuggestions)
	actionsAPI.POST("/reject-delete-suggestions", actionHandler.RejectDeleteSuggestions)
	snapshot := func(id int64) string {
		var state string
		err := db.QueryRow(`SELECT jsonb_build_object('collection', to_jsonb(c),
			'shares', (SELECT jsonb_agg(to_jsonb(s) ORDER BY to_user_id) FROM collection_shares s WHERE s.collection_id = c.collection_id),
			'links', (SELECT jsonb_agg(to_jsonb(l) ORDER BY id) FROM public_collection_tokens l WHERE l.collection_id = c.collection_id))::text FROM collections c WHERE collection_id = $1`, id).Scan(&state)
		require.NoError(t, err)
		return state
	}
	key := base64.StdEncoding.EncodeToString(make([]byte, 80))
	share := `{"collectionID":%[1]d,"email":"member@ente.com","encryptedKey":"` + key + `","role":"ADMIN"}`
	metadata := `{"id":%[1]d,"magicMetadata":{"version":1,"count":1,"data":"data","header":"header"}}`
	cases := []struct {
		name, method, path, body  string
		link, member, admin, bulk bool
	}{
		{name: "create_link", method: "POST", path: "/share-url", body: `{"collectionID":%[1]d}`},
		{name: "edit_link", method: "PUT", path: "/share-url", body: `{"collectionID":%[1]d,"disablePassword":true,"deviceLimit":0}`, link: true},
		{name: "disable_link", method: "DELETE", path: "/share-url/%[1]d", link: true},
		{name: "share", method: "POST", path: "/share", body: share, admin: true},
		{name: "batch_share", method: "POST", path: "/share/batch", body: `{"shares":[` + share + `]}`, admin: true},
		{name: "bulk_share", method: "POST", path: "/share/bulk", body: `{"recipientUserID":2,"recipientEmail":"member@ente.com","source":"manual","collections":[{"collectionID":%[1]d,"encryptedKey":"` + key + `","role":"ADMIN"}]}`, admin: true, bulk: true},
		{name: "unshare", method: "POST", path: "/unshare", body: `{"collectionID":%[1]d,"email":"member@ente.com"}`, admin: true},
		{name: "bulk_unshare", method: "POST", path: "/unshare/bulk", body: `{"recipientUserID":2,"source":"manual","collectionIDs":[%[1]d]}`, admin: true, bulk: true},
		{name: "rename", method: "POST", path: "/rename", body: `{"collectionID":%[1]d,"encryptedName":"renamed","nameDecryptionNonce":"nonce"}`},
		{name: "private_metadata", method: "PUT", path: "/magic-metadata", body: metadata},
		{name: "public_metadata", method: "PUT", path: "/public-magic-metadata", body: metadata},
		{name: "join", method: "POST", path: "/join-link", body: `{"collectionID":%[1]d,"encryptedKey":"` + key + `"}`, link: true, member: true},
		{name: "leave", method: "POST", path: "/leave/%[1]d", member: true},
		{name: "file", method: "GET", path: "/file?collectionID=%[1]d&fileID=%[2]d"},
		{name: "shared_file", method: "GET", path: "/file?collectionID=%[1]d&fileID=%[2]d", member: true},
	}
	for _, app := range []ente.App{ente.Photos, ente.Locker} {
		for _, userID := range []int64{ownerID, memberID, adminID} {
			require.NoError(t, userAuthRepo.AddToken(userID, app, fmt.Sprintf("%s-%d", app, userID), "127.0.0.1", "test"))
		}
		for _, tc := range cases {
			actors := []int64{ownerID}
			if tc.member {
				actors = []int64{memberID}
			}
			if tc.admin {
				actors = append(actors, adminID)
			}
			for _, actorID := range actors {
				for _, targetApp := range []ente.App{ente.Photos, ente.Locker} {
					t.Run(fmt.Sprintf("%s/%s/actor_%d/%s", app, tc.name, actorID, targetApp), func(t *testing.T) {
						collection, err := collectionRepo.Create(ente.Collection{Owner: ente.CollectionUser{ID: ownerID}, App: string(targetApp), Type: "album", EncryptedKey: "key", KeyDecryptionNonce: "nonce", Name: "album", UpdationTime: 1})
						require.NoError(t, err)
						id := collection.ID
						if tc.name != "join" {
							require.NoError(t, collectionRepo.Share(id, ownerID, memberID, "original-key", ente.VIEWER, 1))
						}
						require.NoError(t, collectionRepo.Share(id, ownerID, adminID, "admin-key", ente.ADMIN, 1))
						linkToken := fmt.Sprintf("link-%d", id)
						if tc.link {
							enableJoin := true
							require.NoError(t, linkRepo.Insert(t.Context(), id, linkToken, 0, 1, false, false, &enableJoin))
							if tc.name == "edit_link" {
								_, err = db.Exec(`UPDATE public_collection_tokens SET pw_hash = 'password', pw_nonce = 'nonce', mem_limit = 67108864, ops_limit = 2 WHERE collection_id = $1`, id)
								require.NoError(t, err)
							}
						}
						var fileID int64
						if tc.method == "GET" {
							err = db.QueryRow(`WITH f AS (INSERT INTO files(owner_id, file_decryption_header, thumbnail_decryption_header, metadata_decryption_header, encrypted_metadata, updation_time, info) VALUES ($1, 'file', 'thumb', 'meta', 'data', 1, '{}') RETURNING file_id)
								INSERT INTO collection_files(collection_id, file_id, encrypted_key, key_decryption_nonce, updation_time, c_owner_id, f_owner_id) SELECT $2, file_id, 'key', 'nonce', 1, $1, $1 FROM f RETURNING file_id`, ownerID, id).Scan(&fileID)
							require.NoError(t, err)
						}

						before := snapshot(id)
						format := func(s string) string {
							if strings.Contains(s, "%[") {
								return fmt.Sprintf(s, id, fileID)
							}
							return s
						}
						req := httptest.NewRequest(tc.method, "/collections"+format(tc.path), strings.NewReader(format(tc.body)))
						req.Header.Set("Content-Type", "application/json")
						req.Header.Set("X-Auth-Token", fmt.Sprintf("%s-%d", app, actorID))
						req.Header.Set("X-Client-Package", "io.ente."+string(app))
						req.Header.Set("X-Auth-Access-Token", linkToken)
						response := httptest.NewRecorder()
						router.ServeHTTP(response, req)
						if app != targetApp {
							require.Equal(t, before, snapshot(id), "cross-app request changed persistent state")
							if tc.bulk {
								require.Equal(t, http.StatusOK, response.Code, response.Body.String())
								require.JSONEq(t, fmt.Sprintf(`{"results":[{"collectionID":%d,"status":"failed"}]}`, id), response.Body.String())
							} else {
								require.Equal(t, http.StatusForbidden, response.Code, response.Body.String())
							}
						} else {
							require.Equal(t, http.StatusOK, response.Code, response.Body.String())
							if tc.method != "GET" {
								require.NotEqual(t, before, snapshot(id), "same-app mutation did not persist")
							}
						}
					})
				}
			}
		}
		t.Run(string(app)+"/mixed_bulk", func(t *testing.T) {
			ids := make(map[ente.App]int64)
			for _, targetApp := range []ente.App{ente.Photos, ente.Locker} {
				collection, err := collectionRepo.Create(ente.Collection{Owner: ente.CollectionUser{ID: ownerID}, App: string(targetApp), Type: "album", EncryptedKey: "key", KeyDecryptionNonce: "nonce", Name: "album", UpdationTime: 1})
				require.NoError(t, err)
				ids[targetApp] = collection.ID
				require.NoError(t, collectionRepo.Share(collection.ID, ownerID, memberID, "original-key", ente.VIEWER, 1))
			}
			otherApp := ente.Photos
			if app == ente.Photos {
				otherApp = ente.Locker
			}
			for _, operation := range []string{"share", "unshare"} {
				before := snapshot(ids[otherApp])
				body := fmt.Sprintf(`{"recipientUserID":2,"recipientEmail":"member@ente.com","source":"manual","collections":[{"collectionID":%d,"encryptedKey":"%s","role":"ADMIN"},{"collectionID":%d,"encryptedKey":"%s","role":"ADMIN"}]}`, ids[ente.Photos], key, ids[ente.Locker], key)
				status := "shared"
				if operation == "unshare" {
					body = fmt.Sprintf(`{"recipientUserID":2,"source":"manual","collectionIDs":[%d,%d]}`, ids[ente.Photos], ids[ente.Locker])
					status = "unshared"
				}
				req := httptest.NewRequest("POST", "/collections/"+operation+"/bulk", strings.NewReader(body))
				req.Header.Set("Content-Type", "application/json")
				req.Header.Set("X-Auth-Token", fmt.Sprintf("%s-%d", app, ownerID))
				req.Header.Set("X-Client-Package", "io.ente."+string(app))
				response := httptest.NewRecorder()
				router.ServeHTTP(response, req)
				require.Equal(t, http.StatusOK, response.Code, response.Body.String())
				statuses := map[ente.App]string{app: status, otherApp: "failed"}
				require.JSONEq(t, fmt.Sprintf(`{"results":[{"collectionID":%d,"status":"%s"},{"collectionID":%d,"status":"%s"}]}`, ids[ente.Photos], statuses[ente.Photos], ids[ente.Locker], statuses[ente.Locker]), response.Body.String())
				require.Equal(t, before, snapshot(ids[otherApp]))
			}
		})
		t.Run(string(app)+"/actions", func(t *testing.T) {
			t.Cleanup(func() {
				_, err := db.Exec(`DELETE FROM collection_actions`)
				require.NoError(t, err)
			})
			ids := make(map[ente.App]int64)
			files := make(map[ente.App]int64)
			for _, targetApp := range []ente.App{ente.Photos, ente.Locker} {
				collection, err := collectionRepo.Create(ente.Collection{Owner: ente.CollectionUser{ID: ownerID}, App: string(targetApp), Type: "album", EncryptedKey: "key", KeyDecryptionNonce: "nonce", Name: "album", UpdationTime: 1})
				require.NoError(t, err)
				ids[targetApp] = collection.ID
				var fileID int64
				err = db.QueryRow(`WITH f AS (INSERT INTO files(owner_id, file_decryption_header, thumbnail_decryption_header, metadata_decryption_header, encrypted_metadata, updation_time, info) VALUES ($1, 'file', 'thumb', 'meta', 'data', 1, '{}') RETURNING file_id)
					INSERT INTO collection_files(collection_id, file_id, encrypted_key, key_decryption_nonce, updation_time, c_owner_id, f_owner_id, action) SELECT $2, file_id, 'key', 'nonce', 1, $1, $1, $3 FROM f RETURNING file_id`, ownerID, collection.ID, ente.ActionRemove).Scan(&fileID)
				require.NoError(t, err)
				files[targetApp] = fileID
				for _, action := range []string{ente.ActionRemove, ente.ActionDeleteSuggested} {
					for _, id := range []int64{fileID, -fileID} {
						_, err = actionRepo.Create(t.Context(), ownerID, memberID, collection.ID, targetApp, &id, nil, action, true, 1)
						require.NoError(t, err)
					}
				}
			}
			otherApp := ente.Photos
			if app == ente.Photos {
				otherApp = ente.Locker
			}
			for _, path := range []string{"pending-remove", "delete-suggestions", "reject-delete-suggestions"} {
				method := http.MethodGet
				body := ""
				if path == "reject-delete-suggestions" {
					method = http.MethodPost
					body = fmt.Sprintf(`{"fileIDs":[%d,%d]}`, files[ente.Photos], files[ente.Locker])
				}
				req := httptest.NewRequest(method, "/collection-actions/"+path, strings.NewReader(body))
				req.Header.Set("Content-Type", "application/json")
				req.Header.Set("X-Auth-Token", fmt.Sprintf("%s-%d", app, ownerID))
				req.Header.Set("X-Client-Package", "io.ente."+string(app))
				response := httptest.NewRecorder()
				router.ServeHTTP(response, req)
				require.Equal(t, http.StatusOK, response.Code, response.Body.String())
				if method == http.MethodGet {
					var result struct {
						Actions []ente.CollectionAction `json:"actions"`
					}
					require.NoError(t, json.Unmarshal(response.Body.Bytes(), &result))
					require.Len(t, result.Actions, 1)
					require.Equal(t, ids[app], result.Actions[0].CollectionID)
				} else {
					require.JSONEq(t, `{"updated":1}`, response.Body.String())
				}
				var pending int
				require.NoError(t, db.QueryRow(`SELECT count(*) FROM collection_actions WHERE collection_id = $1 AND is_pending`, ids[otherApp]).Scan(&pending))
				require.Equal(t, 4, pending, "other app's pending actions changed")
			}
		})
	}
}
