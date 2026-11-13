package api

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/controller/discord"
	"github.com/ente/museum/pkg/controller/user"
	"github.com/ente/museum/pkg/middleware"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/gin-gonic/gin"
	"github.com/patrickmn/go-cache"
	"github.com/spf13/viper"
	"github.com/stretchr/testify/require"
)

func TestAdminSuspensionAPIs(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	adminID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "admin@example.com", CreationTime: 1})
	userID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "user@example.com", CreationTime: 1})
	oldAdmins, oldAdmin := viper.Get("internal.admins"), viper.Get("internal.admin")
	viper.Set("internal.admins", []int{int(adminID)})
	t.Cleanup(func() {
		viper.Set("internal.admins", oldAdmins)
		viper.Set("internal.admin", oldAdmin)
	})
	userAuthRepo := &repo.UserAuthRepository{DB: db}
	for token, ownerID := range map[string]int64{"admin": adminID, "old-admin": adminID, "user": userID} {
		require.NoError(t, userAuthRepo.AddToken(ownerID, ente.Photos, token, "", ""))
	}
	oldHash := auth.HashToken("old-admin")
	_, err := db.Exec(`UPDATE tokens SET creation_time = $1 WHERE token_hash = $2`, time.Now().Add(-11*time.Minute).UnixMicro(), oldHash[:])
	require.NoError(t, err)
	userRepo := &repo.UserRepository{DB: db, SecretEncryptionKey: testutil.SecretEncryptionKey()}
	authCache := cache.New(time.Minute, time.Minute)
	controller := &user.UserController{UserAuthRepo: userAuthRepo, Cache: authCache}
	h := &AdminHandler{UserAuthRepo: userAuthRepo, UserRepo: userRepo, UserController: controller, DiscordController: &discord.DiscordController{}}
	m := &middleware.AuthMiddleware{UserAuthRepo: userAuthRepo, Cache: authCache, UserController: controller}
	router := gin.New()
	admin := router.Group("/admin", m.TokenAuthMiddleware(nil), m.AdminAuthMiddleware())
	admin.POST("/user/suspend", h.SuspendUser)
	admin.POST("/user/unsuspend", h.UnsuspendUser)

	request := func(action, token, body string) *httptest.ResponseRecorder {
		req := httptest.NewRequest(http.MethodPost, "/admin/user/"+action, strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Auth-Token", token)
		req.Header.Set("X-Auth-User-ID", fmt.Sprint(adminID))
		response := httptest.NewRecorder()
		router.ServeHTTP(response, req)
		return response
	}
	body := fmt.Sprintf(`{"userID":%d}`, userID)
	for _, action := range []string{"suspend", "unsuspend"} {
		for _, token := range []string{"", "invalid", "user"} {
			require.Equal(t, http.StatusUnauthorized, request(action, token, body).Code)
		}
		require.Equal(t, http.StatusBadRequest, request(action, "old-admin", body).Code)
		for _, invalid := range []string{`{}`, `{"userID":-1}`, `{"userID":0}`, `invalid`} {
			require.Equal(t, http.StatusBadRequest, request(action, "admin", invalid).Code)
		}
		require.Equal(t, http.StatusNotFound, request(action, "admin", `{"userID":999999}`).Code)
	}
	for _, action := range []string{"suspend", "suspend", "unsuspend", "unsuspend"} {
		response := request(action, "admin", body)
		require.Equal(t, http.StatusOK, response.Code, response.Body.String())
		account, err := userRepo.GetUserByIDInternal(userID)
		require.NoError(t, err)
		require.Equal(t, action == "suspend", account.IsSuspended)
		byEmail, err := userRepo.GetUserByEmailHash(account.Hash)
		require.NoError(t, err)
		require.Equal(t, account.IsSuspended, byEmail.IsSuspended)
	}
	require.NoError(t, userAuthRepo.AddToken(userID, ente.Photos, "after-unsuspend", "", ""))
}

func TestAdminCannotSuspendSelf(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	for _, config := range []string{"admins", "admin", "first-user"} {
		t.Run(config, func(t *testing.T) {
			testutil.ResetTables(t, db)
			t.Cleanup(func() { testutil.ResetTables(t, db) })
			adminID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "admin@example.com", CreationTime: 1})
			userID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "user@example.com", CreationTime: 1})
			oldAdmins, oldAdmin := viper.Get("internal.admins"), viper.Get("internal.admin")
			viper.Set("internal.admins", []int{})
			viper.Set("internal.admin", 0)
			if config == "admins" {
				viper.Set("internal.admins", []int{int(adminID)})
			} else if config == "admin" {
				viper.Set("internal.admin", int(adminID))
			}
			t.Cleanup(func() {
				viper.Set("internal.admins", oldAdmins)
				viper.Set("internal.admin", oldAdmin)
			})
			userAuthRepo := &repo.UserAuthRepository{DB: db}
			require.NoError(t, userAuthRepo.AddToken(adminID, ente.Photos, "admin", "", ""))
			authCache := cache.New(time.Minute, time.Minute)
			controller := &user.UserController{UserAuthRepo: userAuthRepo, Cache: authCache}
			userRepo := &repo.UserRepository{DB: db, SecretEncryptionKey: testutil.SecretEncryptionKey()}
			h := &AdminHandler{UserAuthRepo: userAuthRepo, UserRepo: userRepo, UserController: controller, DiscordController: &discord.DiscordController{}}
			m := &middleware.AuthMiddleware{UserAuthRepo: userAuthRepo, Cache: authCache, UserController: controller}
			router := gin.New()
			admin := router.Group("/admin", m.TokenAuthMiddleware(nil), m.AdminAuthMiddleware())
			admin.POST("/user/suspend", h.SuspendUser)
			admin.POST("/user/unsuspend", h.UnsuspendUser)
			request := func(action string, targetID int64) *httptest.ResponseRecorder {
				req := httptest.NewRequest(http.MethodPost, "/admin/user/"+action, strings.NewReader(fmt.Sprintf(`{"userID":%d}`, targetID)))
				req.Header.Set("Content-Type", "application/json")
				req.Header.Set("X-Auth-Token", "admin")
				response := httptest.NewRecorder()
				router.ServeHTTP(response, req)
				return response
			}
			require.Equal(t, http.StatusOK, request("suspend", userID).Code)
			response := request("suspend", adminID)
			require.Equal(t, http.StatusBadRequest, response.Code)
			require.Contains(t, response.Body.String(), "You cannot suspend your own account")
			account, err := userRepo.GetUserByIDInternal(adminID)
			require.NoError(t, err)
			require.False(t, account.IsSuspended)
			authCache.Flush()
			require.Equal(t, http.StatusOK, request("unsuspend", userID).Code)
		})
	}
}
