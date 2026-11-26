package middleware

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/ente/jwt"
	usercontroller "github.com/ente/museum/pkg/controller/user"
	"github.com/patrickmn/go-cache"
	"github.com/stretchr/testify/require"
)

func TestSuspensionRejectsSessionsAndJWTsAfterCacheEviction(t *testing.T) {
	for _, instance := range []string{"same instance", "other instance"} {
		t.Run(instance, func(t *testing.T) {
			router, tokens, controller := setupAuthRouteTest(t)
			suspender := controller
			if instance == "other instance" {
				suspender = &usercontroller.UserController{UserAuthRepo: controller.UserAuthRepo, Cache: cache.New(time.Minute, time.Minute)}
			}
			requests := []struct{ path, token, client string }{
				{"/collections/v2", tokens.photos, "io.ente.photos"},
				{"/collections/v2", tokens.locker, "io.ente.locker"},
				{"/authenticator/entity/diff", tokens.auth, "io.ente.auth"},
				{"/family/test", tokens.family, "io.ente.photos"},
			}
			for _, req := range requests {
				require.Equal(t, http.StatusNoContent, performAuthRouteRequest(router, req.path, req.token, req.client).Code)
			}
			require.NoError(t, suspender.SetSuspended(context.Background(), 91001, true))
			if instance == "same instance" {
				for _, req := range requests {
					require.Equal(t, http.StatusUnauthorized, performAuthRouteRequest(router, req.path, req.token, req.client).Code)
				}
			}
			controller.Cache.Flush()
			for _, req := range requests {
				require.Equal(t, http.StatusUnauthorized, performAuthRouteRequest(router, req.path, req.token, req.client).Code)
			}
			require.NoError(t, suspender.SetSuspended(context.Background(), 91001, false))
			require.NoError(t, controller.UserAuthRepo.AddToken(91001, ente.Photos, "new-session", "", ""))
			require.Equal(t, http.StatusNoContent, performAuthRouteRequest(router, "/collections/v2", "new-session", "io.ente.photos").Code)
			newJWT, err := controller.GetSessionJWTToken(91001, jwt.FAMILIES, "new-session", ente.Photos)
			require.NoError(t, err)
			require.Equal(t, http.StatusNoContent, performAuthRouteRequest(router, "/family/test", newJWT, "io.ente.photos").Code)
		})
	}
}
