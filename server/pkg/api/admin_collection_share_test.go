package api

import (
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestRepairDeletedCollectionShare(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1, Email: "owner@example.com", CreationTime: 1})
	shareeID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 2, Email: "sharee@example.com", CreationTime: 1})

	var collectionID int64
	err := db.QueryRow(`INSERT INTO collections(owner_id, encrypted_key, key_decryption_nonce, name, type, attributes, updation_time, app)
		VALUES($1, 'collection-key', 'nonce', 'album', 'album', '{}', 1, 'photos') RETURNING collection_id`, ownerID).Scan(&collectionID)
	require.NoError(t, err)
	_, err = db.Exec(`INSERT INTO collection_shares(collection_id, from_user_id, to_user_id, encrypted_key, updation_time, role_type, shared_at)
		VALUES($1, $2, $3, 'share-key', 2, 'VIEWER', 2)`, collectionID, ownerID, shareeID)
	require.NoError(t, err)

	h := &AdminHandler{CollectionRepo: &repo.CollectionRepository{DB: db}}
	router := gin.New()
	router.POST("/admin/collection/repair-deleted-share", h.RepairDeletedCollectionShare)
	request := func(toUserID int64) *httptest.ResponseRecorder {
		body := `{"collectionID":` + strconv.FormatInt(collectionID, 10) + `,"toUserID":` + strconv.FormatInt(toUserID, 10) + `}`
		req := httptest.NewRequest(http.MethodPost, "/admin/collection/repair-deleted-share", strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Auth-User-ID", "9")
		response := httptest.NewRecorder()
		router.ServeHTTP(response, req)
		require.Equal(t, http.StatusOK, response.Code, response.Body.String())
		return response
	}

	require.JSONEq(t, `{"updated":0}`, request(shareeID).Body.String())
	_, err = db.Exec(`UPDATE collections SET is_deleted = TRUE, updation_time = 3 WHERE collection_id = $1`, collectionID)
	require.NoError(t, err)
	require.JSONEq(t, `{"updated":0}`, request(shareeID+1).Body.String())
	const sinceTime int64 = 100
	changes, err := h.CollectionRepo.GetCollectionsSharedWithUser(shareeID, sinceTime, ente.Photos, nil)
	require.NoError(t, err)
	require.Empty(t, changes)

	require.JSONEq(t, `{"updated":1}`, request(shareeID).Body.String())

	var deleted bool
	var updatedAt int64
	err = db.QueryRow(`SELECT is_deleted, updation_time FROM collection_shares WHERE collection_id = $1 AND to_user_id = $2`, collectionID, shareeID).Scan(&deleted, &updatedAt)
	require.NoError(t, err)
	require.True(t, deleted)
	require.Greater(t, updatedAt, sinceTime)
	require.JSONEq(t, `{"updated":0}`, request(shareeID).Body.String())

	changes, err = h.CollectionRepo.GetCollectionsSharedWithUser(shareeID, sinceTime, ente.Photos, nil)
	require.NoError(t, err)
	require.Len(t, changes, 1)
	require.Equal(t, collectionID, changes[0].ID)
	require.True(t, changes[0].IsDeleted)
	require.Equal(t, updatedAt, changes[0].UpdationTime)

	changes, err = h.CollectionRepo.GetCollectionsSharedWithUser(shareeID, updatedAt, ente.Photos, nil)
	require.NoError(t, err)
	require.Empty(t, changes)
}
