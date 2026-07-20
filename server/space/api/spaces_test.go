package api

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/ente/museum/internal/testutil"
	baserepo "github.com/ente/museum/pkg/repo"
	timeutil "github.com/ente/museum/pkg/utils/time"
	"github.com/ente/museum/space/controller"
	spacerepo "github.com/ente/museum/space/repo"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestSpaceSlugAvailabilityRouteReturnsOK(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})
	gin.SetMode(gin.TestMode)
	repos := spacerepo.NewModule(db, nil)
	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		Email:        "alice-availability-route@example.com",
		CreationTime: timeutil.Microseconds(),
	})
	_, err := testCreateSpace(context.Background(), repos, userID, "alice", "alice-space-key", "alice-public", "alice-secret", "alice-secret-nonce", "alice-profile")
	require.NoError(t, err)
	router := gin.New()
	Register(router.Group(""), router.Group(""), NewHandlers(controller.NewModule(
		repos,
		&baserepo.UserAuthRepository{DB: db},
	)))

	existing := httptest.NewRecorder()
	router.ServeHTTP(existing, httptest.NewRequest(http.MethodGet, "/space/public/slug-availability/alice", nil))
	require.Equal(t, http.StatusOK, existing.Code)
	require.Equal(t, "no-store", existing.Header().Get("Cache-Control"))
	require.JSONEq(t, `{"available": false}`, existing.Body.String())

	free := httptest.NewRecorder()
	router.ServeHTTP(free, httptest.NewRequest(http.MethodGet, "/space/public/slug-availability/new_person", nil))
	require.Equal(t, http.StatusOK, free.Code)
	require.Equal(t, "no-store", free.Header().Get("Cache-Control"))
	require.JSONEq(t, `{"available": true}`, free.Body.String())
}
