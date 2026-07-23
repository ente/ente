package controller

import (
	"context"
	"crypto/sha256"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	baserepo "github.com/ente/museum/pkg/repo"
	timeutil "github.com/ente/museum/pkg/utils/time"
	"github.com/ente/museum/space/models"
	spacerepo "github.com/ente/museum/space/repo"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func setupSpaceAuthControllerTest(t *testing.T) (*Module, *spacerepo.Module, *baserepo.UserAuthRepository, context.Context) {
	t.Helper()
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})
	gin.SetMode(gin.TestMode)
	repos := spacerepo.NewModule(db, nil)
	userAuthRepo := &baserepo.UserAuthRepository{DB: db}
	return NewModule(repos, userAuthRepo), repos, userAuthRepo, context.Background()
}

func newPublicSpaceContext() *gin.Context {
	recorder := httptest.NewRecorder()
	ctx, _ := gin.CreateTestContext(recorder)
	ctx.Request = httptest.NewRequest("GET", "/", nil)
	return ctx
}

func TestResolveViewerRejectsForgedUserHeaderWithoutToken(t *testing.T) {
	module, repos, _, ctx := setupSpaceAuthControllerTest(t)
	aliceID := insertSpaceControllerUser(t, repos, "alice@example.com", "alice-public")
	space, err := testCreateSpace(ctx, repos, aliceID, "alice", "alice-space-key", "alice-public", "alice-secret", "alice-secret-nonce", "alice-profile")
	require.NoError(t, err)
	ginCtx := newPublicSpaceContext()
	ginCtx.Request.Header.Set("X-Auth-User-ID", strconv.FormatInt(aliceID, 10))

	resp, err := module.Spaces.GetProfile(ginCtx, models.GetSpaceProfileRequest{SpaceID: space.SpaceID})

	require.Nil(t, resp)
	require.ErrorIs(t, err, ente.ErrAuthenticationRequired)
}

func TestResolveViewerEnforcesTokenAppPolicy(t *testing.T) {
	module, repos, userAuthRepo, ctx := setupSpaceAuthControllerTest(t)
	aliceID := insertSpaceControllerUser(t, repos, "alice@example.com", "alice-public")
	space, err := testCreateSpace(ctx, repos, aliceID, "alice", "alice-space-key", "alice-public", "alice-secret", "alice-secret-nonce", "alice-profile")
	require.NoError(t, err)
	require.NoError(t, userAuthRepo.AddToken(aliceID, ente.Photos, "alice-token", "127.0.0.1", "space-test"))
	ginCtx := newPublicSpaceContext()
	ginCtx.Request.Header.Set("X-Auth-Token", "alice-token")
	ginCtx.Request.Header.Set("X-Client-Package", "io.ente.space.web")
	ginCtx.Request.Header.Set("X-Auth-User-ID", "999999")

	resp, err := module.Spaces.GetProfile(ginCtx, models.GetSpaceProfileRequest{SpaceID: space.SpaceID})

	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, space.SpaceID, resp.SpaceID)

	for _, app := range []ente.App{ente.Auth, ente.Locker} {
		token := "alice-" + string(app) + "-token"
		require.NoError(t, userAuthRepo.AddToken(aliceID, app, token, "127.0.0.1", "space-test"))
		deniedCtx := newPublicSpaceContext()
		deniedCtx.Request.Header.Set("X-Auth-Token", token)
		deniedCtx.Request.Header.Set("X-Client-Package", "io.ente."+string(app))

		resp, err = module.Spaces.GetProfile(deniedCtx, models.GetSpaceProfileRequest{SpaceID: space.SpaceID})

		require.Nil(t, resp)
		require.ErrorIs(t, err, ente.ErrPermissionDenied)
	}
}

func TestResolveViewerAcceptsSpaceBrowserSessionHeader(t *testing.T) {
	module, repos, _, ctx := setupSpaceAuthControllerTest(t)
	aliceID := insertSpaceControllerUser(t, repos, "alice@example.com", "alice-public")
	space, err := testCreateSpace(ctx, repos, aliceID, "alice", "alice-space-key", "alice-public", "alice-secret", "alice-secret-nonce", "alice-profile")
	require.NoError(t, err)
	sessionHash := sha256.Sum256([]byte("space-session-token"))
	require.NoError(t, repos.Sessions.CreateBrowserSession(ctx, sessionHash[:], aliceID, "session-wrap-key", timeutil.MicrosecondsAfterMinutes(5)))
	ginCtx := newPublicSpaceContext()
	ginCtx.Request.Header.Set(SpaceBrowserSessionTokenHeader, "space-session-token")
	ginCtx.Request.Header.Set("X-Auth-User-ID", "999999")

	resp, err := module.Spaces.GetProfile(ginCtx, models.GetSpaceProfileRequest{SpaceID: space.SpaceID})

	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, space.SpaceID, resp.SpaceID)
}
