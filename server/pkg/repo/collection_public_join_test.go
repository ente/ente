package repo

import (
	"database/sql"
	"testing"

	"github.com/ente/museum/ente"
)

func TestPublicJoinUpgradesViewerWithoutReplacingAcceptedMembership(t *testing.T) {
	for _, tc := range []struct {
		name     string
		existing ente.CollectionParticipantRole
		link     ente.CollectionParticipantRole
		want     ente.CollectionParticipantRole
	}{
		{"viewer joins collect link", ente.VIEWER, ente.COLLABORATOR, ente.COLLABORATOR},
		{"collaborator joins view link", ente.COLLABORATOR, ente.VIEWER, ente.COLLABORATOR},
		{"admin joins collect link", ente.ADMIN, ente.COLLABORATOR, ente.ADMIN},
		{"viewer joins view link", ente.VIEWER, ente.VIEWER, ente.VIEWER},
	} {
		t.Run(tc.name, func(t *testing.T) {
			repository, db := setupInvitationTest(t)
			collectionID := insertObjectTestCollection(t, db, 1)
			insertObjectTestCollectionShare(t, db, collectionID, 1, 2)
			if _, err := db.Exec(`UPDATE collection_shares SET role_type = $1,
				invited_by_user_id = 3, encrypted_key = 'original-key', shared_at = 77,
				updation_time = 100 WHERE collection_id = $2`, tc.existing, collectionID); err != nil {
				t.Fatal(err)
			}
			if _, err := db.Exec(`UPDATE collections SET updation_time = 1000 WHERE collection_id = $1`, collectionID); err != nil {
				t.Fatal(err)
			}
			type membership struct {
				role              ente.CollectionParticipantRole
				inviter           sql.NullInt64
				encryptedKey      string
				sharedAt          int64
				shareUpdated      int64
				collectionUpdated int64
				status            ente.CollectionAcceptanceStatus
				deleted           bool
			}
			read := func() membership {
				t.Helper()
				var state membership
				if err := db.QueryRow(`SELECT cs.role_type, cs.invited_by_user_id, cs.encrypted_key,
					cs.shared_at, cs.updation_time, c.updation_time, cs.acceptance_status, cs.is_deleted
					FROM collection_shares cs JOIN collections c USING (collection_id)
					WHERE cs.collection_id = $1 AND cs.to_user_id = 2`, collectionID).
					Scan(&state.role, &state.inviter, &state.encryptedKey, &state.sharedAt,
						&state.shareUpdated, &state.collectionUpdated, &state.status, &state.deleted); err != nil {
					t.Fatal(err)
				}
				return state
			}
			before := read()
			for attempt, updateTime := range []int64{200, 4000} {
				ids, err := repository.JoinPublicCollection(t.Context(), collectionID, 1, 2, "replacement-key", tc.link, updateTime)
				if err != nil {
					t.Fatal(err)
				}
				if len(ids) != 1 || ids[0] != collectionID {
					t.Fatalf("joined IDs = %v, want [%d]", ids, collectionID)
				}
				after := read()
				want := before
				want.role = tc.want
				if attempt == 0 && tc.existing != tc.want {
					if after.shareUpdated <= before.collectionUpdated || after.collectionUpdated != after.shareUpdated {
						t.Fatalf("role upgrade did not advance both sync timestamps: before=%+v after=%+v", before, after)
					}
					want.shareUpdated = after.shareUpdated
					want.collectionUpdated = after.collectionUpdated
				}
				if after != want {
					t.Fatalf("join attempt %d membership = %+v, want %+v", attempt, after, want)
				}
				before = after
			}
		})
	}
}
