package middleware

import (
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	publicctrl "github.com/ente/museum/pkg/controller/public"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/repo/public"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/gin-gonic/gin"
	"github.com/patrickmn/go-cache"
	"github.com/spf13/viper"
	"github.com/stretchr/testify/require"
)

var workerRequests = []struct {
	name, configuredSecret, suppliedSecret, ip string
	trusted                                    bool
}{
	{"missing", "worker-secret", "", "2a06:98c0:3600::103", false},
	{"incorrect", "worker-secret", "wrong-secret", "2a06:98c0:3600::103", false},
	{"unconfigured", "", "worker-secret", "2a06:98c0:3600::103", false},
	{"empty", "", "", "2a06:98c0:3600::103", false},
	{"valid", "worker-secret", "worker-secret", "2a06:98c0:3600::103", true},
	{"valid_other_ip", "worker-secret", "worker-secret", "192.0.2.2", true},
	{"direct_client", "worker-secret", "", "192.0.2.2", false},
}

func TestWorkerLinkAdmission(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	previous := viper.Get("workers.shared-secret")
	t.Cleanup(func() { viper.Set("workers.shared-secret", previous) })
	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "worker@ente.com", CreationTime: 1})
	var collectionID, linkID int64
	err := db.QueryRow(`INSERT INTO collections (owner_id, encrypted_key, key_decryption_nonce, name, type, attributes, updation_time, app)
		VALUES ($1, 'key', 'nonce', 'album', 'album', '{}', 1, 'photos') RETURNING collection_id`, ownerID).Scan(&collectionID)
	require.NoError(t, err)
	err = db.QueryRow(`INSERT INTO public_collection_tokens (collection_id, access_token) VALUES ($1, 'collection-token') RETURNING id`, collectionID).Scan(&linkID)
	require.NoError(t, err)
	_, err = db.Exec(`INSERT INTO public_file_tokens (id, file_id, owner_id, app, access_token) VALUES ('file-link', 1, $1, 'photos', 'file-token')`, ownerID)
	require.NoError(t, err)
	collectionRepo := public.NewCollectionLinkRepository(db, "")
	fileRepo := public.NewFileLinkRepo(db)
	collectionMiddleware := &CollectionLinkMiddleware{CollectionLinkRepo: collectionRepo, PublicCollectionCtrl: &publicctrl.CollectionLinkController{JwtSecret: []byte("jwt-secret")}}
	fileMiddleware := &FileLinkMiddleware{FileLinkRepo: fileRepo, FileLinkCtrl: &publicctrl.FileLinkController{JwtSecret: []byte("jwt-secret")}}

	for _, tc := range workerRequests {
		for _, limit := range []int{1, 2} {
			t.Run(fmt.Sprintf("%s/limit_%d", tc.name, limit), func(t *testing.T) {
				viper.Set("workers.shared-secret", tc.configuredSecret)
				_, err := db.Exec(`DELETE FROM public_collection_access_history; DELETE FROM public_file_tokens_access_history`)
				require.NoError(t, err)
				require.NoError(t, collectionRepo.RecordAccessHistory(t.Context(), linkID, "192.0.2.1", "existing"))
				require.NoError(t, fileRepo.RecordAccessHistory(t.Context(), "file-link", "192.0.2.1", "existing"))
				c, _ := gin.CreateTestContext(httptest.NewRecorder())
				c.Request = httptest.NewRequest(http.MethodGet, "/", nil)
				c.Request.Header.Set("X-Ente-Worker-Secret", tc.suppliedSecret)
				wantReached := !tc.trusted && limit == 1
				wantCount := int64(1)
				if !tc.trusted && !wantReached {
					wantCount++
				}

				token, reached, err := collectionMiddleware.checkDeviceLimit(c, "collection-token", ente.PublicCollectionSummary{ID: linkID, DeviceLimit: limit}, tc.ip, "new-client")
				require.NoError(t, err)
				require.Equal(t, wantReached, reached)
				require.Equal(t, wantReached, token == "", "rejected clients must not receive device tokens")
				count, err := collectionRepo.GetUniqueAccessCount(t.Context(), linkID)
				require.NoError(t, err)
				require.Equal(t, wantCount, count)

				token, reached, err = fileMiddleware.checkDeviceLimit(c, "file-token", &ente.FileLinkRow{LinkID: "file-link", DeviceLimit: limit}, tc.ip, "new-client")
				require.NoError(t, err)
				require.Equal(t, wantReached, reached)
				require.Equal(t, wantReached, token == "", "rejected clients must not receive device tokens")
				count, err = fileRepo.GetUniqueAccessCount(t.Context(), "file-link")
				require.NoError(t, err)
				require.Equal(t, wantCount, count)
			})
		}
	}
}

func TestWorkerSessionTracking(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	previous := viper.Get("workers.shared-secret")
	t.Cleanup(func() { viper.Set("workers.shared-secret", previous) })
	userID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "worker-session@ente.com", CreationTime: 1})
	userAuthRepo := &repo.UserAuthRepository{DB: db}
	router := gin.New()
	m := &AuthMiddleware{UserAuthRepo: userAuthRepo, Cache: cache.New(time.Minute, time.Minute)}
	router.GET("/", m.TokenAuthMiddleware(nil), func(c *gin.Context) { c.Status(http.StatusNoContent) })
	for _, tc := range workerRequests {
		t.Run(tc.name, func(t *testing.T) {
			viper.Set("workers.shared-secret", tc.configuredSecret)
			token := "session-" + tc.name
			require.NoError(t, userAuthRepo.AddToken(userID, ente.Photos, token, "192.0.2.1", "original"))
			tokenHash := auth.HashToken(token)
			var lastUsedBefore int64
			require.NoError(t, db.QueryRow(`SELECT last_used_at FROM tokens WHERE token_hash = $1`, tokenHash[:]).Scan(&lastUsedBefore))
			req := httptest.NewRequest(http.MethodGet, "/", nil)
			req.RemoteAddr = net.JoinHostPort(tc.ip, "1234")
			req.Header.Set("X-Auth-Token", token)
			req.Header.Set("X-Client-Package", "io.ente.photos")
			req.Header.Set("X-Ente-Worker-Secret", tc.suppliedSecret)
			req.Header.Set("User-Agent", "new-client")
			response := httptest.NewRecorder()
			router.ServeHTTP(response, req)
			require.Equal(t, http.StatusNoContent, response.Code)
			updated := func() bool {
				var ua string
				if err := db.QueryRow(`SELECT user_agent FROM tokens WHERE token_hash = $1`, tokenHash[:]).Scan(&ua); err != nil {
					t.Error(err)
					return false
				}
				return ua == "new-client"
			}
			if tc.trusted {
				require.Never(t, updated, 100*time.Millisecond, 10*time.Millisecond)
			} else {
				require.Eventually(t, updated, time.Second, 10*time.Millisecond)
			}
			var ip string
			var lastUsedAfter int64
			require.NoError(t, db.QueryRow(`SELECT ip, last_used_at FROM tokens WHERE token_hash = $1`, tokenHash[:]).Scan(&ip, &lastUsedAfter))
			wantIP := "192.0.2.1"
			if tc.name == "direct_client" {
				wantIP = tc.ip
			}
			require.Equal(t, wantIP, ip)
			if tc.trusted {
				require.Equal(t, lastUsedBefore, lastUsedAfter)
			} else {
				require.Greater(t, lastUsedAfter, lastUsedBefore)
			}
		})
	}
	request := httptest.NewRequest(http.MethodGet, "/", nil)
	request.Header.Set("X-Ente-Worker-Secret", "worker-secret")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	require.Equal(t, http.StatusUnauthorized, response.Code)
}
