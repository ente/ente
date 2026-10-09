package collections

import (
	"errors"
	"net/http/httptest"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/ente/cast"
	"github.com/ente/museum/pkg/controller/access"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/gin-gonic/gin"
)

func TestGetCollectionPointResponsesForViewer(t *testing.T) {
	db, collectionRepo, ownerID, shareeID := setupCollectionShareTest(t)
	collectionID := createShareTestCollection(t, collectionRepo, ownerID)
	if _, err := db.Exec(
		`UPDATE collections SET
			magic_metadata = '{"version":1,"count":1,"data":"private-collection","header":"private-header"}'::jsonb,
			pub_magic_metadata = '{"version":1,"count":1,"data":"public-collection","header":"public-header"}'::jsonb
		 WHERE collection_id = $1`,
		collectionID,
	); err != nil {
		t.Fatal(err)
	}
	addShareTestShare(t, collectionRepo, collectionID, ownerID, shareeID, ente.VIEWER)
	if _, err := db.Exec(
		`INSERT INTO public_collection_tokens (collection_id, access_token, valid_till, device_limit, min_role)
		 VALUES ($1, 'collaborator-link', 0, 0, $2)`,
		collectionID, ente.COLLABORATOR,
	); err != nil {
		t.Fatal(err)
	}
	controller := &CollectionController{
		AccessCtrl:     access.NewAccessController(collectionRepo, nil),
		CollectionRepo: collectionRepo,
	}
	ctx, _ := gin.CreateTestContext(httptest.NewRecorder())

	ownerCollection, err := controller.GetCollection(ctx, ownerID, collectionID)
	if err != nil {
		t.Fatal(err)
	}
	wantURL := collectionRepo.CollectionLinkRepo.GetAlbumUrl(ente.Photos, "collaborator-link")
	if len(ownerCollection.PublicURLs) != 1 || ownerCollection.PublicURLs[0].URL != wantURL {
		t.Fatalf("owner public URLs = %+v, want %q", ownerCollection.PublicURLs, wantURL)
	}
	if ownerCollection.MagicMetadata == nil || ownerCollection.MagicMetadata.Data != "private-collection" {
		t.Fatalf("owner private magic metadata = %+v", ownerCollection.MagicMetadata)
	}

	collection, err := controller.GetCollection(ctx, shareeID, collectionID)
	if err != nil {
		t.Fatal(err)
	}
	if collection.EncryptedKey != "share-key" {
		t.Fatalf("encrypted key = %q, want recipient's key", collection.EncryptedKey)
	}
	if collection.MagicMetadata != nil {
		t.Fatalf("viewer received owner-private magic metadata: %+v", collection.MagicMetadata)
	}
	if collection.PublicMagicMetadata == nil || collection.PublicMagicMetadata.Data != "public-collection" {
		t.Fatalf("viewer public magic metadata = %+v", collection.PublicMagicMetadata)
	}
	if len(collection.PublicURLs) != 0 {
		t.Fatalf("viewer received restricted public URLs: %+v", collection.PublicURLs)
	}
	if collection.Owner.Email != "owner@example.com" {
		t.Fatalf("owner email = %q", collection.Owner.Email)
	}
	if len(collection.Sharees) != 1 || collection.Sharees[0].ID != shareeID {
		t.Fatalf("unexpected sharees: %+v", collection.Sharees)
	}

	ctx.Set(auth.CastContext, cast.AuthContext{CollectionID: collectionID})
	castCollection, err := controller.GetCastCollection(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if castCollection.MagicMetadata != nil || castCollection.PublicMagicMetadata == nil {
		t.Fatalf("cast metadata = (%+v, %+v)", castCollection.MagicMetadata, castCollection.PublicMagicMetadata)
	}
	if castCollection.PublicURLs == nil || len(castCollection.PublicURLs) != 0 {
		t.Fatalf("cast public URLs = %#v, want empty array", castCollection.PublicURLs)
	}
}

func TestGetFileForViewer(t *testing.T) {
	db, collectionRepo, ownerID, shareeID := setupCollectionShareTest(t)
	collectionID := createShareTestCollection(t, collectionRepo, ownerID)
	addShareTestShare(t, collectionRepo, collectionID, ownerID, shareeID, ente.VIEWER)
	fileID := addShareTestOwnerFile(t, db, collectionID, ownerID)
	if _, err := db.Exec(
		`UPDATE files SET
			magic_metadata = '{"version":1,"count":1,"data":"private-file","header":"private-header"}'::jsonb,
			pub_magic_metadata = '{"version":1,"count":1,"data":"public-file","header":"public-header"}'::jsonb
		 WHERE file_id = $1`,
		fileID,
	); err != nil {
		t.Fatal(err)
	}
	controller := &CollectionController{CollectionRepo: collectionRepo}
	ownerFile, err := controller.GetFile(newBatchShareTestContext(ownerID), collectionID, fileID)
	if err != nil {
		t.Fatal(err)
	}
	if ownerFile.MagicMetadata == nil || ownerFile.MagicMetadata.Data != "private-file" {
		t.Fatalf("owner private magic metadata = %+v", ownerFile.MagicMetadata)
	}
	viewerFile, err := controller.GetFile(newBatchShareTestContext(shareeID), collectionID, fileID)
	if err != nil {
		t.Fatal(err)
	}
	if viewerFile.MagicMetadata != nil || viewerFile.Action != nil || viewerFile.ActionUserID != nil {
		t.Fatalf("viewer received owner-private file fields: %+v", viewerFile)
	}
	if viewerFile.PubicMagicMetadata == nil || viewerFile.PubicMagicMetadata.Data != "public-file" {
		t.Fatalf("viewer public magic metadata = %+v", viewerFile.PubicMagicMetadata)
	}
	if viewerFile.EncryptedKey != "collection-file-key" || viewerFile.Metadata.EncryptedData != "encrypted-metadata" {
		t.Fatalf("viewer shared file fields were not preserved: %+v", viewerFile)
	}

	for _, action := range []string{ente.ActionRemove, ente.ActionDeleteSuggested} {
		if _, err := db.Exec(
			`UPDATE collection_files SET action_user = $1, action = $2
			 WHERE collection_id = $3 AND file_id = $4`,
			ownerID,
			action,
			collectionID,
			fileID,
		); err != nil {
			t.Fatal(err)
		}

		ownerFile, err := controller.GetFile(newBatchShareTestContext(ownerID), collectionID, fileID)
		if err != nil {
			t.Fatal(err)
		}
		if ownerFile.Action == nil || *ownerFile.Action != action || ownerFile.ActionUserID == nil || *ownerFile.ActionUserID != ownerID {
			t.Fatalf("owner action fields = (%v, %v)", ownerFile.Action, ownerFile.ActionUserID)
		}

		viewerFile, err := controller.GetFile(newBatchShareTestContext(shareeID), collectionID, fileID)
		if viewerFile != nil || !errors.Is(err, &ente.ErrFileNotFoundInAlbum) {
			t.Fatalf("viewer lookup with action %q = (%+v, %v), want file not found", action, viewerFile, err)
		}
	}
}
