package collections

import (
	"errors"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	museumcontroller "github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/controller/public"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/auth"
)

func TestJoinViaLinkRejectsCrossAppSessionBeforeChangingMemberships(t *testing.T) {
	db, collectionRepo, ownerID, recipientID := setupCollectionShareTest(t)
	joinedID := createShareTestCollection(t, collectionRepo, ownerID)
	pendingID := createShareTestCollection(t, collectionRepo, ownerID)
	if err := collectionRepo.Share(pendingID, ownerID, recipientID, "pending-key", ente.VIEWER, 100,
		repo.ShareAcceptanceOptions{Enabled: true, InviterUserID: ownerID}); err != nil {
		t.Fatal(err)
	}
	const token = "photos-public-link"
	if err := collectionRepo.CollectionLinkRepo.Insert(t.Context(), joinedID, token, 0, 0, false, false, nil); err != nil {
		t.Fatal(err)
	}
	testutil.InsertSubscription(t, db, testutil.SubscriptionFixture{
		UserID: ownerID, Storage: 1 << 30, ExpiryTime: time.Now().Add(time.Hour).UnixMicro(),
	})
	controller := newBatchShareTestController(db, collectionRepo)
	controller.CollectionLinkCtrl = &public.CollectionLinkController{CollectionLinkRepo: collectionRepo.CollectionLinkRepo}
	controller.BillingCtrl = &museumcontroller.BillingController{
		UserRepo: &repo.UserRepository{DB: db}, BillingRepo: &repo.BillingRepository{DB: db},
	}
	ctx := newBatchShareTestContext(recipientID)
	ctx.Set(auth.AppContextKey, ente.Locker)
	ctx.Request.Header.Set("X-Client-Package", "io.ente.photos")
	ctx.Request.Header.Set("X-Auth-Access-Token", token)

	type membershipState struct {
		joinedShares     int
		pendingStatus    ente.CollectionAcceptanceStatus
		pendingDeleted   bool
		pendingUpdated   int64
		pendingAlbumTime int64
		joinedAlbumTime  int64
	}
	read := func() membershipState {
		t.Helper()
		var state membershipState
		if err := db.QueryRow(`SELECT
			(SELECT COUNT(*) FROM collection_shares WHERE collection_id = $1 AND to_user_id = $3),
			cs.acceptance_status, cs.is_deleted, cs.updation_time, c.updation_time,
			(SELECT updation_time FROM collections WHERE collection_id = $1)
			FROM collection_shares cs JOIN collections c USING (collection_id)
			WHERE cs.collection_id = $2 AND cs.to_user_id = $3`, joinedID, pendingID, recipientID).
			Scan(&state.joinedShares, &state.pendingStatus, &state.pendingDeleted,
				&state.pendingUpdated, &state.pendingAlbumTime, &state.joinedAlbumTime); err != nil {
			t.Fatal(err)
		}
		return state
	}
	before := read()
	if _, err := controller.JoinViaLink(ctx, ente.JoinCollectionViaLinkRequest{
		CollectionID: joinedID, EncryptedKey: b64OfLen(sealedCollectionKeyLen),
	}); !errors.Is(err, ente.ErrPermissionDenied) {
		t.Fatalf("cross-app join error = %v, want permission denied", err)
	}
	if after := read(); after != before {
		t.Fatalf("denied join changed memberships: before=%+v after=%+v", before, after)
	}
}
