package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller/collections"
	"github.com/gin-gonic/gin"
)

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
