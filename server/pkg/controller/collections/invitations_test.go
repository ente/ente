package collections

import (
	"database/sql"
	"errors"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	"github.com/spf13/viper"
)

func setShareAcceptanceEnabled(t *testing.T, enabled bool) {
	t.Helper()
	previous := viper.Get("photos.share-acceptance.enabled")
	viper.Set("photos.share-acceptance.enabled", enabled)
	t.Cleanup(func() { viper.Set("photos.share-acceptance.enabled", previous) })
}

func TestShareAcceptanceCreationPaths(t *testing.T) {
	for _, tc := range []struct {
		name    string
		path    string
		enabled bool
		app     ente.App
		family  bool
		pending bool
	}{
		{name: "before activation", path: "single", app: ente.Photos},
		{name: "direct admin invitation", path: "single", enabled: true, app: ente.Photos, pending: true},
		{name: "batch admin invitation", path: "batch", enabled: true, app: ente.Photos, pending: true},
		{name: "bulk admin invitation", path: "bulk", enabled: true, app: ente.Photos, pending: true},
		{name: "family automatic share", path: "automatic", enabled: true, app: ente.Photos, family: true},
		{name: "other apps retain immediate access", path: "single", enabled: true, app: ente.Locker},
	} {
		t.Run(tc.name, func(t *testing.T) {
			db, collectionRepo, ownerID, recipientID := setupCollectionShareTest(t)
			setShareAcceptanceEnabled(t, tc.enabled)
			adminID := testutil.InsertUser(t, db, testutil.UserFixture{
				UserID: 3, Email: "admin@example.com", CreationTime: 1,
			})
			collectionID := createShareTestCollection(t, collectionRepo, ownerID)
			if _, err := db.Exec(`UPDATE collections SET app = $1 WHERE collection_id = $2`, tc.app, collectionID); err != nil {
				t.Fatal(err)
			}
			addShareTestShare(t, collectionRepo, collectionID, ownerID, adminID, ente.ADMIN)
			actorID := adminID
			if tc.family {
				actorID = ownerID
				setShareTestFamilyAdmin(t, db, ownerID, ownerID)
				setShareTestFamilyAdmin(t, db, recipientID, ownerID)
			}
			controller := newBatchShareTestController(db, collectionRepo)
			controller.UserRepo = &repo.UserRepository{DB: db}
			ctx := newBatchShareTestContext(actorID)
			request := ente.AlterShareRequest{
				CollectionID: collectionID,
				Email:        "sharee@example.com",
				EncryptedKey: b64OfLen(sealedCollectionKeyLen),
			}
			var err error
			switch tc.path {
			case "single":
				_, err = controller.Share(ctx, request)
			case "batch":
				_, err = controller.BatchShare(ctx, []ente.AlterShareRequest{request})
			default:
				source := ente.ManualShare
				if tc.path == "automatic" {
					source = ente.AutomaticShare
				}
				var results []ente.BulkCollectionShareResult
				results, err = controller.BulkShare(ctx, ente.BulkCollectionShareRequest{
					RecipientUserID: recipientID,
					RecipientEmail:  request.Email,
					Source:          source,
					Collections: []ente.BulkCollectionShareItem{{
						CollectionID: collectionID, EncryptedKey: request.EncryptedKey, Role: ente.VIEWER,
					}},
				})
				if err == nil && (len(results) != 1 || results[0].Status != ente.CollectionShared) {
					t.Fatalf("bulk results = %+v", results)
				}
			}
			if err != nil {
				t.Fatal(err)
			}
			var status ente.CollectionAcceptanceStatus
			var inviter sql.NullInt64
			if err := db.QueryRow(`SELECT acceptance_status, invited_by_user_id FROM collection_shares
				WHERE collection_id = $1 AND to_user_id = $2`, collectionID, recipientID).Scan(&status, &inviter); err != nil {
				t.Fatal(err)
			}
			wantStatus := ente.CollectionAccepted
			if tc.pending {
				wantStatus = ente.CollectionPending
			}
			if status != wantStatus {
				t.Fatalf("status = %s, want %s", status, wantStatus)
			}
			wantInviter := tc.enabled && tc.app == ente.Photos
			if inviter.Valid != wantInviter || (wantInviter && inviter.Int64 != actorID) {
				t.Fatalf("inviter = %+v, want recorded=%v actor=%d", inviter, wantInviter, actorID)
			}
		})
	}
}

func TestPendingAdminCanBeManagedButCannotShare(t *testing.T) {
	db, collectionRepo, ownerID, recipientID := setupCollectionShareTest(t)
	setShareAcceptanceEnabled(t, true)
	adminID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID: 3, Email: "admin@example.com", CreationTime: 1,
	})
	collectionID := createShareTestCollection(t, collectionRepo, ownerID)
	addShareTestShare(t, collectionRepo, collectionID, ownerID, adminID, ente.ADMIN)
	controller := newBatchShareTestController(db, collectionRepo)
	role := ente.ADMIN
	request := ente.AlterShareRequest{CollectionID: collectionID, Email: "sharee@example.com", EncryptedKey: b64OfLen(sealedCollectionKeyLen), Role: &role}
	if _, err := controller.Share(newBatchShareTestContext(adminID), request); err != nil {
		t.Fatal(err)
	}
	if _, err := controller.collectionForShareMutation(collectionID, recipientID); !errors.Is(err, ente.ErrPermissionDenied) {
		t.Fatalf("pending admin authorization = %v, want permission denied", err)
	}
	if err := collectionRepo.UpdateShareeMetadata(collectionID, ownerID, recipientID, ente.MagicMetadata{}, 100); err == nil {
		t.Fatal("pending recipient changed sharee metadata")
	}
	role = ente.VIEWER
	sharees, err := controller.Share(newBatchShareTestContext(ownerID), request)
	if err != nil {
		t.Fatal(err)
	}
	found := false
	for _, sharee := range sharees {
		if sharee.ID != recipientID {
			continue
		}
		found = true
		if sharee.Role != ente.VIEWER || sharee.AcceptanceStatus != ente.CollectionPending || sharee.InvitedByUserID == nil || *sharee.InvitedByUserID != adminID {
			t.Fatalf("role edit changed invitation identity or status: %+v", sharee)
		}
	}
	if !found {
		t.Fatal("pending recipient missing from management response")
	}
}
