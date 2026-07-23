package api

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	usercontroller "github.com/ente/museum/pkg/controller/user"
	"github.com/ente/museum/pkg/repo"
	"github.com/gin-gonic/gin"
)

func TestSetAttributesHandlerRejectsUnexpectedKDFStrength(t *testing.T) {
	handler, db := setupUserHandlerTest(t)

	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       101,
		Email:        "set-attributes-kdf@ente.com",
		CreationTime: 1,
	})

	body := map[string]any{
		"keyAttributes": validSetAttributesPayload(128*1024*1024, 31),
	}

	recorder := performSetAttributesRequest(t, handler, userID, body)

	assertAPIErrorResponse(t, recorder, http.StatusBadRequest, ente.BadRequest, "Unexpected KDF strength")
}

func TestSetAttributesHandlerRejectsLowMemoryLimit(t *testing.T) {
	handler, db := setupUserHandlerTest(t)

	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       102,
		Email:        "set-attributes-low-mem@ente.com",
		CreationTime: 1,
	})

	body := map[string]any{
		"keyAttributes": validSetAttributesPayload(64*1024*1024, 64),
	}

	recorder := performSetAttributesRequest(t, handler, userID, body)

	assertAPIErrorResponse(t, recorder, http.StatusBadRequest, ente.BadRequest, "memory limit must be at least 128MB")
}

func setupUserHandlerTest(t *testing.T) (*UserHandler, *sql.DB) {
	t.Helper()

	testutil.WithServerRoot(t)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	userRepo := &repo.UserRepository{
		DB:                  db,
		SecretEncryptionKey: testutil.SecretEncryptionKey(),
		HashingKey:          testutil.HashingKey(),
	}

	return &UserHandler{
		UserController: &usercontroller.UserController{
			UserRepo: userRepo,
		},
	}, db
}

func performSetAttributesRequest(t *testing.T, handler *UserHandler, userID int64, body map[string]any) *httptest.ResponseRecorder {
	t.Helper()

	gin.SetMode(gin.TestMode)

	payload, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("failed to marshal request body: %v", err)
	}

	recorder := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/user/attributes", bytes.NewReader(payload))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Auth-User-ID", strconv.FormatInt(userID, 10))

	router := gin.New()
	router.POST("/user/attributes", handler.SetAttributes)
	router.ServeHTTP(recorder, req)

	return recorder
}

func validSetAttributesPayload(memLimit, opsLimit int) map[string]any {
	return map[string]any{
		"kekSalt":                  "kek-salt",
		"encryptedKey":             "encrypted-key",
		"keyDecryptionNonce":       "key-nonce",
		"publicKey":                "public-key",
		"encryptedSecretKey":       "encrypted-secret-key",
		"secretKeyDecryptionNonce": "secret-key-nonce",
		"memLimit":                 memLimit,
		"opsLimit":                 opsLimit,
	}
}

func assertAPIErrorResponse(t *testing.T, recorder *httptest.ResponseRecorder, wantStatus int, wantCode ente.ErrorCode, wantMessage string) {
	t.Helper()

	if recorder.Code != wantStatus {
		t.Fatalf("unexpected status code: got %d want %d; body=%s", recorder.Code, wantStatus, recorder.Body.String())
	}

	var apiErr ente.ApiError
	if err := json.Unmarshal(recorder.Body.Bytes(), &apiErr); err != nil {
		t.Fatalf("failed to decode response body %q: %v", recorder.Body.String(), err)
	}

	if apiErr.Code != wantCode {
		t.Fatalf("unexpected error code: got %q want %q", apiErr.Code, wantCode)
	}

	if apiErr.Message != wantMessage {
		t.Fatalf("unexpected error message: got %q want %q", apiErr.Message, wantMessage)
	}
}
