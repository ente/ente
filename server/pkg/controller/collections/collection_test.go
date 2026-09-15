package collections

import (
	"net/http/httptest"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller/access"
	"github.com/gin-gonic/gin"
)

func TestGetCollectionForViewer(t *testing.T) {
	db, collectionRepo, ownerID, shareeID := setupCollectionShareTest(t)
	collectionID := createShareTestCollection(t, collectionRepo, ownerID)
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

	collection, err := controller.GetCollection(ctx, shareeID, collectionID)
	if err != nil {
		t.Fatal(err)
	}
	if collection.EncryptedKey != "share-key" {
		t.Fatalf("encrypted key = %q, want recipient's key", collection.EncryptedKey)
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
}
