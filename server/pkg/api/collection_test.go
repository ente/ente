package api

import (
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller/collections"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestCollectionHandlersRejectInvalidKeys(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	handler := &CollectionHandler{Controller: &collections.CollectionController{}}
	router.POST("/collections", handler.Create)
	router.POST("/collections/share", handler.Share)

	for _, test := range []struct {
		name string
		path string
		body any
	}{
		{"create invalid base64", "/collections", ente.Collection{
			EncryptedKey:       strings.Repeat("!", base64.StdEncoding.EncodedLen(48)),
			KeyDecryptionNonce: base64.StdEncoding.EncodeToString(make([]byte, 24)),
			Type:               "album",
			Attributes:         ente.CollectionAttributes{Version: 1},
		}},
		{"share incorrect length", "/collections/share", ente.AlterShareRequest{
			CollectionID: 1,
			Email:        "sharee@example.com",
			EncryptedKey: base64.StdEncoding.EncodeToString(make([]byte, 79)),
		}},
	} {
		t.Run(test.name, func(t *testing.T) {
			body, err := json.Marshal(test.body)
			require.NoError(t, err)
			request := httptest.NewRequest(http.MethodPost, test.path, strings.NewReader(string(body)))
			request.Header.Set("Content-Type", "application/json")
			request.Header.Set("X-Auth-User-ID", "1")
			recorder := httptest.NewRecorder()
			router.ServeHTTP(recorder, request)
			require.Equal(t, http.StatusBadRequest, recorder.Code, recorder.Body.String())
			var response ente.ApiError
			require.NoError(t, json.Unmarshal(recorder.Body.Bytes(), &response))
			require.Equal(t, ente.BadRequest, response.Code)
		})
	}
}

func TestBatchShareHandlerValidatesEachShare(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	handler := &CollectionHandler{Controller: &collections.CollectionController{}}
	router.POST("/collections/share/batch", handler.BatchShare)

	tests := []struct {
		name string
		body string
	}{
		{"missing collectionID", `{"shares":[{"email":"sharee@example.com","encryptedKey":"a"}]}`},
		{"missing email", `{"shares":[{"collectionID":1,"encryptedKey":"a"}]}`},
		{"one bad item among good ones", `{"shares":[{"collectionID":1,"email":"a@example.com"},{"collectionID":1}]}`},
		{"empty shares list", `{"shares":[]}`},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			recorder := httptest.NewRecorder()
			req := httptest.NewRequest(http.MethodPost, "/collections/share/batch", strings.NewReader(tt.body))
			req.Header.Set("Content-Type", "application/json")
			req.Header.Set("X-Auth-User-ID", "1")
			router.ServeHTTP(recorder, req)
			if recorder.Code != http.StatusBadRequest {
				t.Fatalf("status = %d, want %d; body=%s", recorder.Code, http.StatusBadRequest, recorder.Body.String())
			}
		})
	}
}

func TestDeletedSharedCollectionResponseShape(t *testing.T) {
	collection := ente.Collection{
		ID:                  7,
		Owner:               ente.CollectionUser{ID: 8, Email: "owner@example.com", Name: "Owner", Role: ente.OWNER},
		EncryptedKey:        "share-key",
		KeyDecryptionNonce:  "key-nonce",
		Name:                "secret name",
		EncryptedName:       "encrypted-name",
		NameDecryptionNonce: "name-nonce",
		Type:                "album",
		Attributes:          ente.CollectionAttributes{EncryptedPath: "path", Version: 1},
		Sharees:             []ente.CollectionUser{{ID: 9, Email: "sharee@example.com"}},
		PublicURLs:          []ente.PublicURL{{URL: "https://example.com/secret"}},
		UpdationTime:        10,
		SharedAt:            func() *int64 { value := int64(9); return &value }(),
		IsDeleted:           true,
		MagicMetadata:       &ente.MagicMetadata{Data: "private"},
		PublicMagicMetadata: &ente.MagicMetadata{Data: "public"},
		SharedMagicMetadata: &ente.MagicMetadata{Data: "shared"},
		App:                 string(ente.Photos),
	}

	responses := sharedCollectionResponses([]ente.Collection{collection})
	encoded, err := json.Marshal(responses[0])
	if err != nil {
		t.Fatal(err)
	}
	want := `{"id":7,"owner":{"id":8,"email":""},"encryptedKey":"share-key","type":"album","attributes":{},"updationTime":10,"isDeleted":true}`
	if string(encoded) != want {
		t.Fatalf("deleted shared collection response = %s, want %s", encoded, want)
	}
}
