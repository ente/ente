package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/ente/museum/ente/cast"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/controller/access"
	castController "github.com/ente/museum/pkg/controller/cast"
	castRepo "github.com/ente/museum/pkg/repo/cast"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

type allowCastCollectionAccess struct {
	access.Controller
}

func (allowCastCollectionAccess) GetCollection(*gin.Context, *access.GetCollectionParams) (*access.GetCollectionResponse, error) {
	return &access.GetCollectionResponse{}, nil
}

func TestCastAuthRejectsRevokedToken(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })

	const userID = int64(92001)
	const collectionID = int64(92002)
	deviceID := uuid.New()
	const token = "cast-auth-test-token"
	_, err := db.Exec(
		`INSERT INTO casting(id, code, public_key, collection_id, cast_user, token, ip)
		 VALUES($1, $2, $3, $4, $5, $6, $7)`,
		deviceID, "CAST01", "key", collectionID, userID, token, "127.0.0.1",
	)
	if err != nil {
		t.Fatalf("insert casting row: %v", err)
	}

	repository := &castRepo.Repository{DB: db}
	controller := castController.NewController(repository, allowCastCollectionAccess{})
	router := gin.New()
	router.Use((&CastMiddleware{CastCtrl: controller}).CastAuthMiddleware())
	router.GET("/", func(c *gin.Context) {
		if got := auth.GetCastCtx(c); got != (cast.AuthContext{UserID: userID, CollectionID: collectionID}) {
			t.Fatalf("cast context = %+v", got)
		}
		c.Status(http.StatusNoContent)
	})

	request := func() *httptest.ResponseRecorder {
		recorder := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodGet, "/", nil)
		req.Header.Set("X-Cast-Access-Token", token)
		router.ServeHTTP(recorder, req)
		return recorder
	}
	if got := request().Code; got != http.StatusNoContent {
		t.Fatalf("active token status = %d", got)
	}
	if err := repository.RevokeForGivenUserAndDevice(t.Context(), userID, deviceID); err != nil {
		t.Fatalf("revoke token: %v", err)
	}
	if got := request().Code; got != http.StatusUnauthorized {
		t.Fatalf("revoked token status = %d", got)
	}
}
