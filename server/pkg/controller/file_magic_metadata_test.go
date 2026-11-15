package controller

import (
	"database/sql"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestUpdateMagicMetadataValidation(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1, Email: "owner@ente.io", CreationTime: 1})
	otherID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 2, Email: "other@ente.io", CreationTime: 1})
	insertFile := func(ownerID int64, privateVersion, publicVersion int) int64 {
		t.Helper()
		metadata := func(version int) any {
			if version == 0 {
				return nil
			}
			return ente.MagicMetadata{Version: version, Count: 3, Data: "data", Header: "header"}
		}
		var fileID int64
		require.NoError(t, db.QueryRow(`INSERT INTO files(owner_id, file_decryption_header, thumbnail_decryption_header,
				metadata_decryption_header, encrypted_metadata, updation_time, magic_metadata, pub_magic_metadata)
			VALUES ($1, 'header', 'header', 'header', 'metadata', 1, $2, $3) RETURNING file_id`,
			ownerID, metadata(privateVersion), metadata(publicVersion)).Scan(&fileID))
		return fileID
	}
	fileID := insertFile(ownerID, 3, 1)
	secondFileID := insertFile(ownerID, 0, 0)
	otherFileID := insertFile(otherID, 1, 1)
	missingFileID := otherFileID + 1000

	c := &FileController{FileRepo: &repo.FileRepository{DB: db}}
	ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
	ctx.Request = httptest.NewRequest("PUT", "/files/magic-metadata", nil)
	ctx.Request.Header.Set("X-Auth-User-ID", strconv.FormatInt(ownerID, 10))
	update := func(id int64, version, count int) ente.UpdateMagicMetadata {
		return ente.UpdateMagicMetadata{ID: id, MagicMetadata: ente.MagicMetadata{Version: version, Count: count, Data: "new", Header: "header"}}
	}

	for _, tc := range []struct {
		name    string
		public  bool
		updates []ente.UpdateMagicMetadata
		want    error
	}{
		{name: "missing file", updates: []ente.UpdateMagicMetadata{update(fileID, 3, 3), update(missingFileID, 1, 1)}, want: sql.ErrNoRows},
		{name: "other owner", updates: []ente.UpdateMagicMetadata{update(fileID, 3, 3), update(otherFileID, 1, 1)}, want: ente.ErrPermissionDenied},
		{name: "other owner before missing file", updates: []ente.UpdateMagicMetadata{update(otherFileID, 1, 1), update(missingFileID, 1, 1)}, want: ente.ErrPermissionDenied},
		{name: "public version checked against private metadata", updates: []ente.UpdateMagicMetadata{update(fileID, 1, 3)}, want: ente.ErrVersionMismatch},
		{name: "private version checked against public metadata", public: true, updates: []ente.UpdateMagicMetadata{update(fileID, 3, 3)}, want: ente.ErrVersionMismatch},
		{name: "too many keys dropped", updates: []ente.UpdateMagicMetadata{update(fileID, 3, 0)}, want: ente.ErrVersionMismatch},
		{name: "private metadata", updates: []ente.UpdateMagicMetadata{update(fileID, 3, 3), update(secondFileID, 7, 1)}},
		{name: "public metadata", public: true, updates: []ente.UpdateMagicMetadata{update(fileID, 1, 3), update(secondFileID, 1, 1)}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			err := c.validateUpdateMetadataRequest(ctx, ente.UpdateMultipleMagicMetadataRequest{MetadataList: tc.updates}, tc.public)
			if tc.want == nil {
				require.NoError(t, err)
			} else {
				require.ErrorIs(t, err, tc.want)
			}
		})
	}
}
