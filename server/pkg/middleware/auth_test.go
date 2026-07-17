package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/ente/jwt"
	"github.com/ente/museum/internal/testutil"
	usercontroller "github.com/ente/museum/pkg/controller/user"
	"github.com/ente/museum/pkg/repo"
	"github.com/gin-gonic/gin"
	"github.com/patrickmn/go-cache"
)

type authRouteTestTokens struct {
	auth    string
	photos  string
	locker  string
	family  string
	payment string
}

func TestRejectAuthAppKeepsAuthRoutesAndBlocksStorageRoutes(t *testing.T) {
	router, tokens := setupAuthRouteTest(t)

	tests := []struct {
		name       string
		path       string
		token      string
		clientPkg  string
		wantStatus int
	}{
		{
			name:       "auth token can access auth route",
			path:       "/authenticator/entity/diff?sinceTime=0&limit=1",
			token:      tokens.auth,
			clientPkg:  "io.ente.auth",
			wantStatus: http.StatusNoContent,
		},
		{
			name:       "auth token cannot access storage route",
			path:       "/collections/v2",
			token:      tokens.auth,
			clientPkg:  "io.ente.auth",
			wantStatus: http.StatusForbidden,
		},
		{
			name:       "auth token cannot access user entity route",
			path:       "/user-entity/entity/diff?type=contact&sinceTime=0&limit=1",
			token:      tokens.auth,
			clientPkg:  "io.ente.auth",
			wantStatus: http.StatusForbidden,
		},
		{
			name:       "auth token cannot access contact route",
			path:       "/contacts/diff?sinceTime=0&limit=1",
			token:      tokens.auth,
			clientPkg:  "io.ente.auth",
			wantStatus: http.StatusForbidden,
		},
		{
			name:       "auth token cannot access contact attachment route",
			path:       "/attachments/profile_picture/ua_test",
			token:      tokens.auth,
			clientPkg:  "io.ente.auth",
			wantStatus: http.StatusForbidden,
		},
		{
			name:       "photos token can access storage route",
			path:       "/collections/v2",
			token:      tokens.photos,
			clientPkg:  "io.ente.photos",
			wantStatus: http.StatusNoContent,
		},
		{
			name:       "photos token can access user or JWT route",
			path:       "/family/test",
			token:      tokens.photos,
			clientPkg:  "io.ente.photos",
			wantStatus: http.StatusNoContent,
		},
		{
			name:       "family JWT can access user or JWT route",
			path:       "/family/test",
			token:      tokens.family,
			clientPkg:  "io.ente.photos",
			wantStatus: http.StatusNoContent,
		},
		{
			name:       "wrong scope JWT cannot access user or JWT route",
			path:       "/family/test",
			token:      tokens.payment,
			clientPkg:  "io.ente.photos",
			wantStatus: http.StatusUnauthorized,
		},
		{
			name:       "malformed JWT cannot access user or JWT route",
			path:       "/family/test",
			token:      "not.a.jwt",
			clientPkg:  "io.ente.photos",
			wantStatus: http.StatusUnauthorized,
		},
		{
			name:       "locker token can access storage route",
			path:       "/collections/v2",
			token:      tokens.locker,
			clientPkg:  "io.ente.locker",
			wantStatus: http.StatusNoContent,
		},
		{
			name:       "auth token with photos header remains invalid",
			path:       "/collections/v2",
			token:      tokens.auth,
			clientPkg:  "io.ente.photos",
			wantStatus: http.StatusUnauthorized,
		},
		{
			name:       "auth token still blocked when header changes after token auth",
			path:       "/files/download/123",
			token:      tokens.auth,
			clientPkg:  "io.ente.auth",
			wantStatus: http.StatusForbidden,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			recorder := performAuthRouteRequest(router, tt.path, tt.token, tt.clientPkg)
			if recorder.Code != tt.wantStatus {
				t.Fatalf("status = %d, want %d; body=%s", recorder.Code, tt.wantStatus, recorder.Body.String())
			}
		})
	}
}

func setupAuthRouteTest(t *testing.T) (*gin.Engine, authRouteTestTokens) {
	t.Helper()

	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       91001,
		Email:        "auth-route-test@ente.com",
		CreationTime: 1,
	})
	userAuthRepo := &repo.UserAuthRepository{DB: db}
	tokens := authRouteTestTokens{
		auth:   "auth-route-test-auth-token",
		photos: "auth-route-test-photos-token",
		locker: "auth-route-test-locker-token",
	}
	userController := &usercontroller.UserController{JwtSecret: []byte("auth-route-test-jwt-secret")}
	var err error
	tokens.family, err = userController.GetJWTToken(userID, jwt.FAMILIES)
	if err != nil {
		t.Fatalf("failed to create family JWT: %v", err)
	}
	tokens.payment, err = userController.GetJWTToken(userID, jwt.PAYMENT)
	if err != nil {
		t.Fatalf("failed to create payment JWT: %v", err)
	}
	addTokenForTest(t, userAuthRepo, userID, ente.Auth, tokens.auth)
	addTokenForTest(t, userAuthRepo, userID, ente.Photos, tokens.photos)
	addTokenForTest(t, userAuthRepo, userID, ente.Locker, tokens.locker)

	gin.SetMode(gin.TestMode)
	router := gin.New()
	authMiddleware := &AuthMiddleware{
		UserAuthRepo:   userAuthRepo,
		Cache:          cache.New(time.Minute, time.Minute),
		UserController: userController,
	}
	privateAPI := router.Group("/")
	privateAPI.Use(authMiddleware.TokenAuthMiddleware(nil))
	privateAPI.GET("/authenticator/entity/diff", func(c *gin.Context) {
		c.Status(http.StatusNoContent)
	})
	familyAPI := router.Group("/")
	familyAPI.Use(authMiddleware.TokenOrJWTAuthMiddleware(jwt.FAMILIES))
	familyAPI.GET("/family/test", func(c *gin.Context) {
		c.Status(http.StatusNoContent)
	})

	storageAPI := privateAPI.Group("/")
	storageAPI.Use(RejectAuthApp())
	storageAPI.GET("/collections/v2", func(c *gin.Context) {
		c.Status(http.StatusNoContent)
	})
	storageAPI.GET("/user-entity/entity/diff", func(c *gin.Context) {
		c.Status(http.StatusNoContent)
	})
	storageAPI.GET("/contacts/diff", func(c *gin.Context) {
		c.Status(http.StatusNoContent)
	})
	storageAPI.GET("/attachments/:type/:attachmentID", func(c *gin.Context) {
		c.Status(http.StatusNoContent)
	})

	headerMutatingStorageAPI := privateAPI.Group("/")
	headerMutatingStorageAPI.Use(func(c *gin.Context) {
		c.Request.Header.Set("X-Client-Package", "io.ente.photos")
		c.Next()
	}, RejectAuthApp())
	headerMutatingStorageAPI.GET("/files/download/:fileID", func(c *gin.Context) {
		c.Status(http.StatusNoContent)
	})

	return router, tokens
}

func addTokenForTest(t *testing.T, userAuthRepo *repo.UserAuthRepository, userID int64, app ente.App, token string) {
	t.Helper()
	if err := userAuthRepo.AddToken(userID, app, token, "127.0.0.1", "auth-route-test"); err != nil {
		t.Fatalf("failed to add %s token: %v", app, err)
	}
}

func performAuthRouteRequest(router *gin.Engine, path string, token string, clientPkg string) *httptest.ResponseRecorder {
	recorder := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, path, nil)
	req.Header.Set("X-Auth-Token", token)
	req.Header.Set("X-Client-Package", clientPkg)
	router.ServeHTTP(recorder, req)
	return recorder
}
