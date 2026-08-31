package api

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	museumcontroller "github.com/ente/museum/pkg/controller"
	usercontroller "github.com/ente/museum/pkg/controller/user"
	"github.com/ente/museum/pkg/repo"
	"github.com/gin-gonic/gin"
)

func TestGetPublicKeyHandlerUsesEmailLookup(t *testing.T) {
	handler, db := setupUserHandlerTest(t)
	requesterUserID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       102,
		Email:        "public-key-requester@ente.com",
		CreationTime: 1,
	})

	targetUserID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       103,
		Email:        "public-key-target@ente.com",
		CreationTime: 1,
	})
	keyAttributes := setPublicKeyTestAttributes(t, handler, targetUserID)

	router := gin.New()
	router.GET("/users/public-key", handler.GetPublicKey)

	recorder := httptest.NewRecorder()
	req := httptest.NewRequest(
		http.MethodGet,
		"/users/public-key?email=public-key-target%40ente.com",
		nil,
	)
	req.Header.Set("X-Auth-User-ID", strconv.FormatInt(requesterUserID, 10))
	router.ServeHTTP(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf("unexpected status code: got %d want %d; body=%s", recorder.Code, http.StatusOK, recorder.Body.String())
	}
	var response struct {
		PublicKey string `json:"publicKey"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatalf("failed to decode response body: %v", err)
	}
	if response.PublicKey != keyAttributes.PublicKey {
		t.Fatalf("unexpected public key: got %q want %q", response.PublicKey, keyAttributes.PublicKey)
	}
}

func TestGetPublicKeyHandlerDoesNotLookupByUserID(t *testing.T) {
	handler, db := setupUserHandlerTest(t)
	requesterUserID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       101,
		Email:        "public-key-requester@ente.com",
		CreationTime: 1,
	})
	targetUserID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       102,
		Email:        "public-key-target@ente.com",
		CreationTime: 1,
	})
	setPublicKeyTestAttributes(t, handler, targetUserID)

	recorder := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/users/public-key?userID=102", nil)
	req.Header.Set("X-Auth-User-ID", strconv.FormatInt(requesterUserID, 10))
	router := gin.New()
	router.GET("/users/public-key", handler.GetPublicKey)
	router.ServeHTTP(recorder, req)

	if recorder.Code != http.StatusNotFound {
		t.Fatalf("unexpected status code: got %d want %d; body=%s", recorder.Code, http.StatusNotFound, recorder.Body.String())
	}
}

func setPublicKeyTestAttributes(t *testing.T, handler *UserHandler, userID int64) ente.KeyAttributes {
	t.Helper()
	keyAttributes := ente.KeyAttributes{
		KEKSalt:                  "kek-salt",
		KEKHash:                  "kek-hash",
		EncryptedKey:             "encrypted-key",
		KeyDecryptionNonce:       "key-decryption-nonce",
		PublicKey:                "target-public-key",
		EncryptedSecretKey:       "encrypted-secret-key",
		SecretKeyDecryptionNonce: "secret-key-decryption-nonce",
		MemLimit:                 128 * 1024 * 1024,
		OpsLimit:                 32,
	}
	if err := handler.UserController.UserRepo.SetKeyAttributes(userID, keyAttributes); err != nil {
		t.Fatalf("failed to set key attributes: %v", err)
	}
	return keyAttributes
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
			UserRepo:   userRepo,
			UserLookup: museumcontroller.NewUserLookupController(userRepo, nil),
		},
	}, db
}
