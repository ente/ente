package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo/public"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestFileLinkGoneResponsePreservesLegacyError(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)

	for _, tc := range []struct {
		name     string
		disabled bool
		body     string
	}{
		{"expired", false, `{"code":"LINK_EXPIRED","error":"expired token"}`},
		{"disabled", true, `{"code":"LINK_DISABLED","error":"disabled token"}`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			token := "pft_middleware_" + tc.name
			_, err := db.Exec(`INSERT INTO public_file_tokens
				(id, file_id, owner_id, app, access_token, is_disabled, valid_till)
				VALUES ($1, 1, 1, 'photos', $1, $2, 1)`, token, tc.disabled)
			require.NoError(t, err)
			t.Cleanup(func() {
				_, err := db.Exec("DELETE FROM public_file_tokens WHERE id = $1", token)
				require.NoError(t, err)
			})

			middleware := &FileLinkMiddleware{FileLinkRepo: public.NewFileLinkRepo(db)}
			router := gin.New()
			router.GET("/file-link/info", middleware.Authenticate(func(c *gin.Context) string {
				return c.FullPath()
			}), func(c *gin.Context) { c.Status(http.StatusNoContent) })
			req := httptest.NewRequest(http.MethodGet, "/file-link/info", nil)
			req.Header.Set("X-Auth-Access-Token", token)
			response := httptest.NewRecorder()
			router.ServeHTTP(response, req)
			require.Equal(t, http.StatusGone, response.Code)
			require.JSONEq(t, tc.body, response.Body.String())
		})
	}
}

func TestFileLinkMutationsTakeEffectImmediately(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)

	const token = "pft_middleware_mutation"
	_, err := db.Exec(`INSERT INTO public_file_tokens
		(id, file_id, owner_id, app, access_token)
		VALUES ($1, 1, 1, 'photos', $1)`, token)
	require.NoError(t, err)
	t.Cleanup(func() {
		_, err := db.Exec("DELETE FROM public_file_tokens WHERE id = $1", token)
		require.NoError(t, err)
	})

	linkCache := public.NewLinkCache(time.Minute, time.Minute)
	fileLinkRepo := public.NewFileLinkRepo(db)
	fileLinkRepo.Cache = linkCache
	middleware := &FileLinkMiddleware{FileLinkRepo: fileLinkRepo, Cache: linkCache}
	router := gin.New()
	router.GET("/file-link/file", middleware.Authenticate(func(c *gin.Context) string {
		return c.FullPath()
	}), func(c *gin.Context) { c.Status(http.StatusNoContent) })
	request := func() int {
		req := httptest.NewRequest(http.MethodGet, "/file-link/file", nil)
		req.RemoteAddr = "192.0.2.1:1234"
		req.Header.Set("User-Agent", "test-agent")
		req.Header.Set("X-Auth-Access-Token", token)
		response := httptest.NewRecorder()
		router.ServeHTTP(response, req)
		return response.Code
	}

	require.Equal(t, http.StatusNoContent, request())
	_, cached := linkCache.Get(token, computeHashKeyForList([]string{token, "192.0.2.1", "test-agent"}, ":"))
	require.True(t, cached)
	fileLinkRow, err := fileLinkRepo.GetActiveFileUrlToken(t.Context(), 1)
	require.NoError(t, err)
	fileLinkRow.ValidTill = 1
	require.NoError(t, fileLinkRepo.UpdateLink(t.Context(), *fileLinkRow))
	require.Equal(t, http.StatusGone, request())
	fileLinkRow.ValidTill = 0
	passHash := "hash"
	fileLinkRow.PassHash = &passHash
	require.NoError(t, fileLinkRepo.UpdateLink(t.Context(), *fileLinkRow))
	require.Equal(t, http.StatusUnauthorized, request())
	require.NoError(t, fileLinkRepo.DisableLinkForFiles(t.Context(), []int64{1}))
	require.Equal(t, http.StatusGone, request())
}
