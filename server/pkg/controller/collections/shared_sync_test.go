package collections

import (
	"database/sql"
	"errors"
	"testing"

	"github.com/ente/museum/ente"
)

func TestSharedCollectionSyncUsesShareAndCollectionChanges(t *testing.T) {
	db, collectionRepo, ownerID, shareeID := setupCollectionShareTest(t)
	collectionID := createShareTestCollection(t, collectionRepo, ownerID)
	addShareTestShare(t, collectionRepo, collectionID, ownerID, shareeID, ente.VIEWER)

	sharedMetadata := ente.MagicMetadata{
		Version: 1,
		Count:   1,
		Data:    "sharee-metadata",
		Header:  "sharee-header",
	}
	if _, err := db.Exec(
		`UPDATE collection_shares SET magic_metadata = $1, updation_time = 2
		 WHERE collection_id = $2 AND to_user_id = $3`,
		sharedMetadata,
		collectionID,
		shareeID,
	); err != nil {
		t.Fatal(err)
	}

	limit := int64(10)
	changes, err := collectionRepo.GetCollectionsSharedWithUser(shareeID, 1, ente.Photos, &limit)
	if err != nil {
		t.Fatal(err)
	}
	if len(changes) != 1 {
		t.Fatalf("share-only changes = %d, want 1", len(changes))
	}
	if changes[0].UpdationTime != 2 {
		t.Fatalf("share-only updationTime = %d, want 2", changes[0].UpdationTime)
	}
	if changes[0].SharedMagicMetadata == nil || changes[0].SharedMagicMetadata.Data != sharedMetadata.Data {
		t.Fatalf("share-only metadata = %+v, want %+v", changes[0].SharedMagicMetadata, sharedMetadata)
	}

	if _, err := db.Exec(
		`UPDATE collections SET name = 'renamed collection', updation_time = 3
		 WHERE collection_id = $1`,
		collectionID,
	); err != nil {
		t.Fatal(err)
	}
	changes, err = collectionRepo.GetCollectionsSharedWithUser(shareeID, 2, ente.Photos, &limit)
	if err != nil {
		t.Fatal(err)
	}
	if len(changes) != 1 {
		t.Fatalf("collection-only changes = %d, want 1", len(changes))
	}
	if changes[0].UpdationTime != 3 || changes[0].Name != "renamed collection" {
		t.Fatalf("collection-only change = %+v", changes[0])
	}
}

func TestUnshareEmitsOneRedactedTombstone(t *testing.T) {
	db, collectionRepo, ownerID, shareeID := setupCollectionShareTest(t)
	collectionID := createShareTestCollection(t, collectionRepo, ownerID)
	addShareTestShare(t, collectionRepo, collectionID, ownerID, shareeID, ente.VIEWER)

	metadata := ente.MagicMetadata{Version: 1, Count: 1, Data: "secret", Header: "header"}
	if _, err := db.Exec(
		`UPDATE collections
		 SET encrypted_name = 'encrypted-name', name_decryption_nonce = 'name-nonce',
		     magic_metadata = $1, pub_magic_metadata = $1
		 WHERE collection_id = $2`,
		metadata,
		collectionID,
	); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(
		`UPDATE collection_shares SET magic_metadata = $1
		 WHERE collection_id = $2 AND to_user_id = $3`,
		metadata,
		collectionID,
		shareeID,
	); err != nil {
		t.Fatal(err)
	}

	status, err := collectionRepo.UnShareContext(t.Context(), collectionID, shareeID)
	if err != nil || status != ente.CollectionUnshared {
		t.Fatalf("UnShareContext() = %q, %v", status, err)
	}
	var deletionTime int64
	if err := db.QueryRow(
		`SELECT updation_time FROM collection_shares
		 WHERE collection_id = $1 AND to_user_id = $2`,
		collectionID,
		shareeID,
	).Scan(&deletionTime); err != nil {
		t.Fatal(err)
	}

	if _, err := db.Exec(`UPDATE users SET encrypted_email = NULL, email_decryption_nonce = NULL WHERE user_id = $1`, ownerID); err != nil {
		t.Fatal(err)
	}

	changes, err := collectionRepo.GetCollectionsSharedWithUser(shareeID, deletionTime-1, ente.Photos, nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(changes) != 1 {
		t.Fatalf("changes after unshare = %d, want 1", len(changes))
	}
	tombstone := changes[0]
	if !tombstone.IsDeleted || tombstone.UpdationTime != deletionTime {
		t.Fatalf("tombstone deletion state = %+v, want time %d", tombstone, deletionTime)
	}
	if tombstone.ID != collectionID || tombstone.Owner.ID != ownerID || tombstone.EncryptedKey != "share-key" || tombstone.Type != "album" {
		t.Fatalf("tombstone compatibility fields = %+v", tombstone)
	}
	if tombstone.Owner.Email != "" || tombstone.Name != "" || tombstone.EncryptedName != "" || tombstone.NameDecryptionNonce != "" || tombstone.KeyDecryptionNonce != "" || tombstone.App != "" || tombstone.SharedAt != nil || tombstone.MagicMetadata != nil || tombstone.PublicMagicMetadata != nil || tombstone.SharedMagicMetadata != nil || len(tombstone.Sharees) != 0 || len(tombstone.PublicURLs) != 0 {
		t.Fatalf("tombstone contains live collection data: %+v", tombstone)
	}

	changes, err = collectionRepo.GetCollectionsSharedWithUser(shareeID, deletionTime, ente.Photos, nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(changes) != 0 {
		t.Fatalf("replayed tombstones = %d, want 0", len(changes))
	}

	if _, err := db.Exec(`UPDATE collections SET name = 'post-unshare secret', updation_time = $1 WHERE collection_id = $2`, deletionTime+1, collectionID); err != nil {
		t.Fatal(err)
	}
	changes, err = collectionRepo.GetCollectionsSharedWithUser(shareeID, deletionTime, ente.Photos, nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(changes) != 0 {
		t.Fatalf("post-unshare collection changes = %d, want 0", len(changes))
	}

	controller := newBatchShareTestController(db, collectionRepo)
	_, _, err = controller.GetDiffV2(newBatchShareTestContext(shareeID), collectionID, shareeID, 0)
	if !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("GetDiffV2() error = %v, want sql.ErrNoRows", err)
	}
}
