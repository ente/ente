package api

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/ente/museum/ente"
	model "github.com/ente/museum/ente/userentity"
	"github.com/ente/museum/internal/testutil"
	userentitycontroller "github.com/ente/museum/pkg/controller/userentity"
	userentityrepo "github.com/ente/museum/pkg/repo/userentity"
	"github.com/gin-gonic/gin"
)

func TestCreateUserEntityKeyIsIdempotentForReplay(t *testing.T) {
	handler, db := setupUserEntityHandlerTest(t)

	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       201,
		Email:        "userentity-key-conflict@ente.com",
		CreationTime: 1,
	})

	body := map[string]any{
		"type":         "memory",
		"encryptedKey": "encrypted-key",
		"header":       "header",
	}

	first := performCreateUserEntityKeyRequest(t, handler, userID, body)
	if first.Code != http.StatusOK {
		t.Fatalf("unexpected status code on first create: got %d want %d; body=%s", first.Code, http.StatusOK, first.Body.String())
	}

	second := performCreateUserEntityKeyRequest(t, handler, userID, body)
	if second.Code != http.StatusOK {
		t.Fatalf("unexpected status code on duplicate replay: got %d want %d; body=%s", second.Code, http.StatusOK, second.Body.String())
	}
}

func TestCreateUserEntityKeyReturnsAlreadyExistsForConflictingCreate(t *testing.T) {
	handler, db := setupUserEntityHandlerTest(t)

	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       202,
		Email:        "userentity-key-already-exists@ente.com",
		CreationTime: 1,
	})

	firstBody := map[string]any{
		"type":         "memory",
		"encryptedKey": "encrypted-key",
		"header":       "header",
	}
	secondBody := map[string]any{
		"type":         "memory",
		"encryptedKey": "different-encrypted-key",
		"header":       "different-header",
	}

	first := performCreateUserEntityKeyRequest(t, handler, userID, firstBody)
	if first.Code != http.StatusOK {
		t.Fatalf("unexpected status code on first create: got %d want %d; body=%s", first.Code, http.StatusOK, first.Body.String())
	}

	second := performCreateUserEntityKeyRequest(t, handler, userID, secondBody)
	assertAPIErrorResponse(t, second, http.StatusConflict, ente.AlreadyExists, "Key already exists")
}

func TestEnsureUserEntityKeyReturnsExistingKeyForConflict(t *testing.T) {
	handler, db := setupUserEntityHandlerTest(t)

	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       203,
		Email:        "userentity-key-ensure@ente.io",
		CreationTime: 1,
	})

	firstBody := map[string]any{
		"type":         "space",
		"encryptedKey": "encrypted-key",
		"header":       "header",
	}
	secondBody := map[string]any{
		"type":         "space",
		"encryptedKey": "different-encrypted-key",
		"header":       "different-header",
	}

	first := performEnsureUserEntityKeyRequest(t, handler, userID, firstBody)
	if first.Code != http.StatusOK {
		t.Fatalf("unexpected status code on first ensure: got %d want %d; body=%s", first.Code, http.StatusOK, first.Body.String())
	}
	if first.Header().Get("Cache-Control") != "no-store" {
		t.Fatalf("missing no-store cache header on first ensure: %q", first.Header().Get("Cache-Control"))
	}
	second := performEnsureUserEntityKeyRequest(t, handler, userID, secondBody)
	if second.Code != http.StatusOK {
		t.Fatalf("unexpected status code on duplicate ensure: got %d want %d; body=%s", second.Code, http.StatusOK, second.Body.String())
	}
	if second.Header().Get("Cache-Control") != "no-store" {
		t.Fatalf("missing no-store cache header on duplicate ensure: %q", second.Header().Get("Cache-Control"))
	}
	var response map[string]any
	if err := json.Unmarshal(second.Body.Bytes(), &response); err != nil {
		t.Fatalf("failed to decode ensure response: %v", err)
	}
	if response["encryptedKey"] != firstBody["encryptedKey"] || response["header"] != firstBody["header"] {
		t.Fatalf("ensure returned wrong key: got %v", response)
	}
}

func TestCreateSmartAlbumEntityRestoresDeletedEntry(t *testing.T) {
	handler, db := setupUserEntityHandlerTest(t)

	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       204,
		Email:        "smart-album-restore@ente.com",
		CreationTime: 1,
	})

	ctx := context.Background()
	id := "sa_204_12345"
	if err := handler.Controller.Repo.CreateKey(ctx, userID, model.EntityKeyRequest{
		Type:         model.SmartAlbum,
		EncryptedKey: "encrypted-key",
		Header:       "key-header",
	}); err != nil {
		t.Fatalf("failed to create entity key: %v", err)
	}
	if _, err := handler.Controller.Repo.Create(ctx, userID, model.EntityDataRequest{
		ID:            &id,
		Type:          model.SmartAlbum,
		EncryptedData: "old-data",
		Header:        "old-header",
	}); err != nil {
		t.Fatalf("failed to create smart album entity: %v", err)
	}
	if deleted, err := handler.Controller.Repo.Delete(ctx, userID, id); err != nil || !deleted {
		t.Fatalf("failed to delete smart album entity: deleted=%t err=%v", deleted, err)
	}

	recorder := performCreateUserEntityRequest(t, handler, userID, map[string]any{
		"id":            id,
		"type":          string(model.SmartAlbum),
		"encryptedData": "new-data",
		"header":        "new-header",
	})
	if recorder.Code != http.StatusOK {
		t.Fatalf("unexpected status code on recreate: got %d want %d; body=%s", recorder.Code, http.StatusOK, recorder.Body.String())
	}

	var entity model.EntityData
	if err := json.Unmarshal(recorder.Body.Bytes(), &entity); err != nil {
		t.Fatalf("failed to decode entity response %q: %v", recorder.Body.String(), err)
	}
	if entity.ID != id || entity.UserID != userID || entity.Type != model.SmartAlbum || entity.IsDeleted {
		t.Fatalf("unexpected restored entity: %+v", entity)
	}
	if entity.EncryptedData == nil || *entity.EncryptedData != "new-data" {
		t.Fatalf("unexpected encryptedData: got %v want %q", entity.EncryptedData, "new-data")
	}
	if entity.Header == nil || *entity.Header != "new-header" {
		t.Fatalf("unexpected header: got %v want %q", entity.Header, "new-header")
	}
}

func setupUserEntityHandlerTest(t *testing.T) (*UserEntityHandler, *sql.DB) {
	t.Helper()

	testutil.WithServerRoot(t)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	return &UserEntityHandler{
		Controller: &userentitycontroller.Controller{
			Repo: &userentityrepo.Repository{DB: db},
		},
	}, db
}

func performCreateUserEntityKeyRequest(
	t *testing.T,
	handler *UserEntityHandler,
	userID int64,
	body map[string]any,
) *httptest.ResponseRecorder {
	t.Helper()

	gin.SetMode(gin.TestMode)

	payload, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("failed to marshal request body: %v", err)
	}

	recorder := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/user-entity/key", bytes.NewReader(payload))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Auth-User-ID", strconv.FormatInt(userID, 10))

	router := gin.New()
	router.POST("/user-entity/key", handler.CreateKey)
	router.ServeHTTP(recorder, req)

	return recorder
}

func performEnsureUserEntityKeyRequest(
	t *testing.T,
	handler *UserEntityHandler,
	userID int64,
	body map[string]any,
) *httptest.ResponseRecorder {
	t.Helper()

	gin.SetMode(gin.TestMode)

	payload, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("failed to marshal request body: %v", err)
	}

	recorder := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/user-entity/key/ensure", bytes.NewReader(payload))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Auth-User-ID", strconv.FormatInt(userID, 10))

	router := gin.New()
	router.POST("/user-entity/key/ensure", handler.EnsureKey)
	router.ServeHTTP(recorder, req)

	return recorder
}

func performCreateUserEntityRequest(
	t *testing.T,
	handler *UserEntityHandler,
	userID int64,
	body map[string]any,
) *httptest.ResponseRecorder {
	t.Helper()

	gin.SetMode(gin.TestMode)

	payload, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("failed to marshal request body: %v", err)
	}

	recorder := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/user-entity/entity", bytes.NewReader(payload))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Auth-User-ID", strconv.FormatInt(userID, 10))

	router := gin.New()
	router.POST("/user-entity/entity", handler.CreateEntity)
	router.ServeHTTP(recorder, req)

	return recorder
}
