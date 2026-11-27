package collections

import (
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller/access"
	promtestutil "github.com/prometheus/client_golang/prometheus/testutil"
	"github.com/stretchr/testify/require"
)

func TestCollectionMagicMetadataWritesCountVersionOutcomes(t *testing.T) {
	db, collectionRepo, ownerID, shareeID := setupCollectionShareTest(t)
	collectionID := createShareTestCollection(t, collectionRepo, ownerID)
	addShareTestShare(t, collectionRepo, collectionID, ownerID, shareeID, ente.VIEWER)
	controller := &CollectionController{
		CollectionRepo: collectionRepo,
		AccessCtrl:     access.NewAccessController(collectionRepo, nil),
	}

	write := func(route string, version int) {
		t.Helper()
		userID := ownerID
		if route == "sharee" {
			userID = shareeID
		}
		ctx := newBatchShareTestContext(userID)
		ctx.Request.Header.Set("X-Client-Package", "io.ente.photos.web")
		req := ente.UpdateCollectionMagicMetadata{
			ID:            collectionID,
			MagicMetadata: ente.MagicMetadata{Version: version, Count: 1, Data: "data", Header: "header"},
		}
		var err error
		if route == "sharee" {
			err = controller.UpdateShareeMagicMetadata(ctx, req)
		} else {
			err = controller.UpdateMagicMetadata(ctx, req, route == "owner_public")
		}
		require.NoError(t, err)
	}
	expectCount := func(route string, version int, outcome string) {
		t.Helper()
		counter := magicMetadataVersions.WithLabelValues(route, "web", outcome)
		before := promtestutil.ToFloat64(counter)
		write(route, version)
		require.Equal(t, before+1, promtestutil.ToFloat64(counter), "%s v%d", route, version)
	}

	expectCount("owner_private", 1, "match")
	expectCount("owner_private", 1, "stale")
	expectCount("owner_public", 1, "match")
	expectCount("sharee", 1, "match")
	expectCount("sharee", 2, "ahead_one")

	require.NoError(t, collectionRepo.UnShare(collectionID, shareeID))
	before := collectionUpdationTime(t, db, collectionID)
	_, err := collectionRepo.UpdateShareeMetadata(collectionID, ownerID, shareeID,
		ente.MagicMetadata{Version: 2, Count: 1, Data: "data", Header: "header"}, before+1)
	require.ErrorContains(t, err, "invalid number of rows affected 0")
	require.Equal(t, before, collectionUpdationTime(t, db, collectionID))
}
