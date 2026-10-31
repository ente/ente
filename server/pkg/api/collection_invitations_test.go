package api

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/controller/access"
	"github.com/ente/museum/pkg/controller/collections"
	"github.com/ente/museum/pkg/repo"
	publicrepo "github.com/ente/museum/pkg/repo/public"
	"github.com/gin-gonic/gin"
)

func TestCollectionSyncSeparatesPendingInvitationsFromAlbumChanges(t *testing.T) {
	db, collectionRepo, router := setupInvitationAPITest(t)
	collectionID := insertInvitationAPIFixture(t, db, collectionRepo)

	for _, endpoint := range []struct {
		path       string
		collection string
	}{
		{"/collections/v2", "collections"},
		{"/collections/v3", "shared"},
	} {
		t.Run(endpoint.path, func(t *testing.T) {
			response := invitationAPIRequest(t, router, http.MethodGet, endpoint.path, "", 2)
			if response.Code != http.StatusOK {
				t.Fatalf("sync status = %d; body=%s", response.Code, response.Body.String())
			}
			var body map[string]json.RawMessage
			decodeInvitationAPIResponse(t, response, &body)
			var changes []map[string]json.RawMessage
			if err := json.Unmarshal(body[endpoint.collection], &changes); err != nil {
				t.Fatal(err)
			}
			if len(changes) != 1 || string(changes[0]["isDeleted"]) != "true" {
				t.Fatalf("pending collection changes = %s, want one removal", body[endpoint.collection])
			}
			for _, field := range []string{"encryptedName", "name", "sharees", "publicURLs", "pubMagicMetadata"} {
				if _, present := changes[0][field]; present {
					t.Errorf("pending removal exposed %s", field)
				}
			}
			var invitations []ente.CollectionInvitation
			if err := json.Unmarshal(body["pendingInvitations"], &invitations); err != nil {
				t.Fatal(err)
			}
			if len(invitations) != 1 {
				t.Fatalf("invitations = %s, want one", body["pendingInvitations"])
			}
			invitation := invitations[0]
			if invitation.CollectionID != collectionID || invitation.Inviter.ID != 3 || invitation.Inviter.Email != "inviter@example.com" {
				t.Errorf("invitation identity = %+v", invitation)
			}
			if invitation.EncryptedKey != "recipient-wrapped-key" || invitation.EncryptedName != "encrypted-title" || invitation.NameDecryptionNonce != "title-nonce" || invitation.SharedAt != 10 {
				t.Errorf("invitation preview = %+v", invitation)
			}

			response = invitationAPIRequest(t, router, http.MethodGet, endpoint.path+"?sinceTime=10000000000000000&sharedSinceTime=10000000000000000", "", 2)
			decodeInvitationAPIResponse(t, response, &body)
			if string(body[endpoint.collection]) != "[]" {
				t.Errorf("collection changes beyond cursor = %s, want []", body[endpoint.collection])
			}
			if err := json.Unmarshal(body["pendingInvitations"], &invitations); err != nil || len(invitations) != 1 {
				t.Fatalf("snapshot was coupled to collection cursor: %s; err=%v", body["pendingInvitations"], err)
			}
		})
	}

	if _, err := db.Exec(`UPDATE collection_shares SET is_deleted = TRUE WHERE collection_id = $1`, collectionID); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{"/collections/v2", "/collections/v3"} {
		response := invitationAPIRequest(t, router, http.MethodGet, path, "", 2)
		var body map[string]json.RawMessage
		decodeInvitationAPIResponse(t, response, &body)
		if string(body["pendingInvitations"]) != "[]" {
			t.Errorf("withdrawn invitation snapshot = %s, want explicit []", body["pendingInvitations"])
		}
	}
}

func TestAcceptInvitationsAPIValidatesWholeBatchAndReturnsOnlySelectedAlbums(t *testing.T) {
	db, collectionRepo, router := setupInvitationAPITest(t)
	firstID := insertInvitationAPIFixture(t, db, collectionRepo)
	secondID := insertInvitationAPIFixture(t, db, collectionRepo)
	omittedID := insertInvitationAPIFixture(t, db, collectionRepo)

	response := invitationAPIRequest(t, router, http.MethodGet, fmt.Sprintf("/collections/%d", firstID), "", 2)
	if response.Code != http.StatusForbidden && response.Code != http.StatusNotFound {
		t.Fatalf("pending album access = %d, want denied", response.Code)
	}
	response = invitationAPIRequest(t, router, http.MethodPost, "/collections/accept", fmt.Sprintf(`{"collectionIDs":[%d,%d]}`, firstID, secondID), 3)
	if response.Code < 400 || response.Code >= 500 {
		t.Fatalf("non-recipient acceptance = %d; body=%s", response.Code, response.Body.String())
	}
	response = invitationAPIRequest(t, router, http.MethodPost, "/collections/accept", fmt.Sprintf(`{"collectionIDs":[%d,999999999]}`, firstID), 2)
	if response.Code < 400 || response.Code >= 500 {
		t.Fatalf("invalid batch status = %d; body=%s", response.Code, response.Body.String())
	}
	requireInvitationAPIState(t, db, firstID, "pending", false)

	body := fmt.Sprintf(`{"collectionIDs":[%d,%d]}`, firstID, secondID)
	for attempt := 0; attempt < 2; attempt++ {
		response = invitationAPIRequest(t, router, http.MethodPost, "/collections/accept", body, 2)
		if response.Code != http.StatusOK {
			t.Fatalf("accept attempt %d = %d; body=%s", attempt, response.Code, response.Body.String())
		}
		var result ente.AcceptCollectionInvitationsResponse
		decodeInvitationAPIResponse(t, response, &result)
		if len(result.AcceptedCollectionIDs) != 2 || len(result.Collections) != 2 {
			t.Fatalf("accepted result = %+v, want two IDs and collections", result)
		}
		seen := make(map[int64]bool)
		for _, collection := range result.Collections {
			seen[collection.ID] = true
			if collection.EncryptedKey != "recipient-wrapped-key" || collection.EncryptedName != "encrypted-title" || collection.IsDeleted {
				t.Errorf("accepted album cannot be opened from returned metadata: %+v", collection)
			}
		}
		if !seen[firstID] || !seen[secondID] {
			t.Errorf("returned collection IDs = %v", seen)
		}
		for _, collectionID := range result.AcceptedCollectionIDs {
			if !seen[collectionID] {
				t.Errorf("accepted ID %d does not identify a returned album", collectionID)
			}
		}
	}
	requireInvitationAPIState(t, db, omittedID, "pending", false)
	response = invitationAPIRequest(t, router, http.MethodGet, fmt.Sprintf("/collections/%d", firstID), "", 2)
	if response.Code != http.StatusOK {
		t.Fatalf("accepted album access = %d; body=%s", response.Code, response.Body.String())
	}
}

func TestRejectInvitationAPIIsRecipientScopedAndRetryable(t *testing.T) {
	db, collectionRepo, router := setupInvitationAPITest(t)
	selectedID := insertInvitationAPIFixture(t, db, collectionRepo)
	otherID := insertInvitationAPIFixture(t, db, collectionRepo)
	body := fmt.Sprintf(`{"collectionID":%d}`, selectedID)
	response := invitationAPIRequest(t, router, http.MethodPost, "/collections/reject", body, 3)
	if response.Code < 400 || response.Code >= 500 {
		t.Fatalf("non-recipient rejection = %d; body=%s", response.Code, response.Body.String())
	}
	requireInvitationAPIState(t, db, selectedID, "pending", false)
	for attempt := 0; attempt < 2; attempt++ {
		response = invitationAPIRequest(t, router, http.MethodPost, "/collections/reject", body, 2)
		if response.Code != http.StatusOK {
			t.Fatalf("reject attempt %d = %d; body=%s", attempt, response.Code, response.Body.String())
		}
	}
	requireInvitationAPIState(t, db, selectedID, "rejected", true)
	requireInvitationAPIState(t, db, otherID, "pending", false)
}

func setupInvitationAPITest(t *testing.T) (*sql.DB, *repo.CollectionRepository, http.Handler) {
	t.Helper()
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	for index, email := range []string{"owner@example.com", "recipient@example.com", "inviter@example.com"} {
		testutil.InsertUser(t, db, testutil.UserFixture{UserID: int64(index + 1), Email: email, CreationTime: 1})
	}
	collectionRepo := &repo.CollectionRepository{
		DB:                  db,
		CollectionLinkRepo:  publicrepo.NewCollectionLinkRepository(db, ""),
		SecretEncryptionKey: testutil.SecretEncryptionKey(),
	}
	controller := &collections.CollectionController{
		CollectionRepo: collectionRepo,
		AccessCtrl:     access.NewAccessController(collectionRepo, nil),
	}
	handler := &CollectionHandler{Controller: controller}
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.GET("/collections/v2", handler.GetV2)
	router.GET("/collections/v3", handler.GetWithLimit)
	router.GET("/collections/:collectionID", handler.GetCollectionByID)
	router.POST("/collections/accept", handler.AcceptInvitations)
	router.POST("/collections/reject", handler.RejectInvitation)
	return db, collectionRepo, router
}

func insertInvitationAPIFixture(t *testing.T, db *sql.DB, collectionRepo *repo.CollectionRepository) int64 {
	t.Helper()
	collection, err := collectionRepo.Create(ente.Collection{
		Owner:               ente.CollectionUser{ID: 1},
		EncryptedKey:        "owner-wrapped-key",
		KeyDecryptionNonce:  "owner-key-nonce",
		EncryptedName:       "encrypted-title",
		NameDecryptionNonce: "title-nonce",
		Type:                "album",
		App:                 string(ente.Photos),
		UpdationTime:        10,
	})
	if err != nil {
		t.Fatal(err)
	}
	_, err = db.Exec(`INSERT INTO collection_shares
		(collection_id, from_user_id, to_user_id, encrypted_key, updation_time, role_type, shared_at, acceptance_status, invited_by_user_id)
		VALUES ($1, 1, 2, 'recipient-wrapped-key', 10, 'VIEWER', 10, 'pending', 3)`, collection.ID)
	if err != nil {
		t.Fatal(err)
	}
	return collection.ID
}

func invitationAPIRequest(t *testing.T, router http.Handler, method, path, body string, userID int64) *httptest.ResponseRecorder {
	t.Helper()
	request := httptest.NewRequest(method, path, strings.NewReader(body))
	request.Header.Set("X-Auth-User-ID", strconv.FormatInt(userID, 10))
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	return response
}

func decodeInvitationAPIResponse(t *testing.T, response *httptest.ResponseRecorder, result any) {
	t.Helper()
	if response.Code != http.StatusOK {
		t.Fatalf("response status = %d; body=%s", response.Code, response.Body.String())
	}
	if err := json.Unmarshal(response.Body.Bytes(), result); err != nil {
		t.Fatal(err)
	}
}

func requireInvitationAPIState(t *testing.T, db *sql.DB, collectionID int64, status string, deleted bool) {
	t.Helper()
	var actualStatus string
	var actualDeleted bool
	if err := db.QueryRow(`SELECT acceptance_status, is_deleted FROM collection_shares WHERE collection_id = $1 AND to_user_id = 2`, collectionID).Scan(&actualStatus, &actualDeleted); err != nil {
		t.Fatal(err)
	}
	if actualStatus != status || actualDeleted != deleted {
		t.Fatalf("collection %d membership = (%s, %v), want (%s, %v)", collectionID, actualStatus, actualDeleted, status, deleted)
	}
}
