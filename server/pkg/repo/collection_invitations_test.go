package repo

import (
	"context"
	"database/sql"
	"fmt"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo/public"
	"github.com/lib/pq"
)

func TestInvitationTrustFollowsInviterAndActiveMemberships(t *testing.T) {
	repository, db := setupInvitationTest(t)
	first := insertObjectTestCollection(t, db, 1)
	grantInvitationAdmin(t, db, first, 1, 3)
	inviteCollection(t, repository, first, 1, 3, 2)
	assertInvitationState(t, db, first, 2, ente.CollectionPending, false, 3)
	if _, err := repository.AcceptInvitations(t.Context(), 2, []int64{first}); err != nil {
		t.Fatal(err)
	}

	second := insertObjectTestCollection(t, db, 4)
	grantInvitationAdmin(t, db, second, 4, 3)
	inviteCollection(t, repository, second, 4, 3, 2)
	assertInvitationState(t, db, second, 2, ente.CollectionAccepted, false, 3)
	ownerInvite := insertObjectTestCollection(t, db, 4)
	inviteCollection(t, repository, ownerInvite, 4, 4, 2)
	assertInvitationState(t, db, ownerInvite, 2, ente.CollectionPending, false, 4)
	if err := repository.Share(second, 4, 2, "ignored-key", ente.COLLABORATOR, 200,
		ShareAcceptanceOptions{Enabled: true, InviterUserID: 4}); err != nil {
		t.Fatal(err)
	}
	assertInvitationState(t, db, second, 2, ente.CollectionAccepted, false, 3)
	for _, id := range []int64{first, second} {
		if err := repository.UnShare(id, 2); err != nil {
			t.Fatal(err)
		}
	}
	inviteCollection(t, repository, second, 4, 4, 2)
	assertInvitationState(t, db, second, 2, ente.CollectionPending, false, 4)
	third := insertObjectTestCollection(t, db, 1)
	grantInvitationAdmin(t, db, third, 1, 3)
	inviteCollection(t, repository, third, 1, 3, 2)
	assertInvitationState(t, db, third, 2, ente.CollectionPending, false, 3)
}

func TestInvitationTrustOwnerFallbackAndFamily(t *testing.T) {
	for _, test := range []struct {
		name       string
		setup      string
		wantStatus ente.CollectionAcceptanceStatus
	}{
		{"legacy_or_public", "", ente.CollectionAccepted},
		{"removed", "UPDATE collection_shares SET is_deleted = TRUE", ente.CollectionPending},
		{"deleted_album", "UPDATE collections SET is_deleted = TRUE", ente.CollectionPending},
		{"other_app", "UPDATE collections SET app = 'locker'", ente.CollectionPending},
		{"family", "UPDATE collection_shares SET is_deleted = TRUE; UPDATE users SET family_admin_id = 1 WHERE user_id IN (1, 2)", ente.CollectionAccepted},
	} {
		t.Run(test.name, func(t *testing.T) {
			repository, db := setupInvitationTest(t)
			legacy := insertObjectTestCollection(t, db, 1)
			insertObjectTestCollectionShare(t, db, legacy, 1, 2)
			if test.setup != "" {
				if _, err := db.Exec(test.setup); err != nil {
					t.Fatal(err)
				}
			}
			incoming := insertObjectTestCollection(t, db, 1)
			inviteCollection(t, repository, incoming, 1, 1, 2)
			assertInvitationState(t, db, incoming, 2, test.wantStatus, false, 1)
		})
	}
}

func TestInvitationAcceptUsesExactAtomicBatchAndRetryStates(t *testing.T) {
	repository, db := setupInvitationTest(t)
	ids := make([]int64, 4)
	for index := range ids {
		ids[index] = insertObjectTestCollection(t, db, 1)
		inviteCollection(t, repository, ids[index], 1, 1, 2)
	}
	otherInviter := insertObjectTestCollection(t, db, 3)
	inviteCollection(t, repository, otherInviter, 3, 3, 2)
	if _, err := repository.AcceptInvitations(t.Context(), 2, []int64{ids[0], otherInviter}); err == nil {
		t.Fatal("mixed inviter batch succeeded")
	}
	if err := repository.RejectInvitation(t.Context(), 2, ids[1]); err != nil {
		t.Fatal(err)
	}
	if _, err := repository.AcceptInvitations(t.Context(), 2, ids[:2]); err == nil {
		t.Fatal("batch containing rejected invitation succeeded")
	}
	assertInvitationState(t, db, ids[0], 2, ente.CollectionPending, false, 1)
	if _, err := repository.AcceptInvitations(t.Context(), 2, []int64{ids[0], ids[2]}); err != nil {
		t.Fatal(err)
	}
	assertInvitationState(t, db, ids[3], 2, ente.CollectionPending, false, 1)
	if _, err := repository.AcceptInvitations(t.Context(), 2, []int64{ids[0], ids[2]}); err != nil {
		t.Fatalf("accepted retry failed: %v", err)
	}
	if err := repository.RejectInvitation(t.Context(), 2, ids[1]); err != nil {
		t.Fatalf("rejected retry failed: %v", err)
	}
	if err := repository.RejectInvitation(t.Context(), 2, ids[0]); err == nil {
		t.Fatal("rejection of accepted membership succeeded")
	}
	if err := repository.UnShare(ids[3], 2); err != nil {
		t.Fatal(err)
	}
	if _, err := repository.AcceptInvitations(t.Context(), 2, []int64{ids[3]}); err == nil {
		t.Fatal("withdrawn invitation was accepted")
	}

	adminAlbum := insertObjectTestCollection(t, db, 4)
	grantInvitationAdmin(t, db, adminAlbum, 4, 3)
	inviteCollection(t, repository, adminAlbum, 4, 3, 2)
	if _, err := repository.AcceptInvitations(t.Context(), 2, []int64{adminAlbum}); err != nil {
		t.Fatal(err)
	}
	if err := (&UserRepository{DB: db}).Delete(3); err != nil {
		t.Fatal(err)
	}
	if _, err := repository.AcceptInvitations(t.Context(), 2, []int64{adminAlbum}); err != nil {
		t.Fatalf("accepted retry depended on deleted inviter: %v", err)
	}
}

func TestPublicJoinChangesProvenanceAndAcceptsOnlyEligibleInvitations(t *testing.T) {
	repository, db := setupInvitationTest(t)
	joined := insertObjectTestCollection(t, db, 1)
	grantInvitationAdmin(t, db, joined, 1, 3)
	inviteCollection(t, repository, joined, 1, 3, 2)
	ids := make([]int64, 4)
	for index := range ids {
		ids[index] = insertObjectTestCollection(t, db, 1)
		inviteCollection(t, repository, ids[index], 1, 1, 2)
	}
	if err := repository.RejectInvitation(t.Context(), 2, ids[1]); err != nil {
		t.Fatal(err)
	}
	if err := repository.UnShare(ids[2], 2); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`UPDATE collections SET is_deleted = TRUE WHERE collection_id = $1`, ids[3]); err != nil {
		t.Fatal(err)
	}
	accepted, err := repository.JoinPublicCollection(t.Context(), joined, 1, 2, "public-key", ente.VIEWER, 300)
	if err != nil {
		t.Fatal(err)
	}
	if len(accepted) != 2 || !containsInvitationID(accepted, joined) || !containsInvitationID(accepted, ids[0]) {
		t.Fatalf("accepted IDs = %v", accepted)
	}
	assertInvitationState(t, db, joined, 2, ente.CollectionAccepted, false, 0)
	assertInvitationState(t, db, ids[0], 2, ente.CollectionAccepted, false, 1)
	assertInvitationState(t, db, ids[1], 2, ente.CollectionRejected, true, 1)
	assertInvitationState(t, db, ids[2], 2, ente.CollectionPending, true, 1)
	assertInvitationState(t, db, ids[3], 2, ente.CollectionPending, false, 1)
	if _, err := repository.AcceptInvitations(t.Context(), 2, []int64{joined}); err != nil {
		t.Fatalf("accepted public membership retry failed: %v", err)
	}
	if _, err := repository.JoinPublicCollection(t.Context(), ids[0], 1, 2, "retry-key", ente.VIEWER, 400); err != nil {
		t.Fatal(err)
	}
	assertInvitationState(t, db, ids[0], 2, ente.CollectionAccepted, false, 1)
	future := insertObjectTestCollection(t, db, 1)
	inviteCollection(t, repository, future, 1, 1, 2)
	assertInvitationState(t, db, future, 2, ente.CollectionAccepted, false, 1)
	if _, err := repository.JoinPublicCollection(t.Context(), ids[3], 1, 2, "key", ente.VIEWER, 500); err == nil {
		t.Fatal("joined deleted album")
	}
}

func TestPublicJoinRollsBackMembershipWhenRelatedAcceptanceFails(t *testing.T) {
	repository, db := setupInvitationTest(t)
	joined := insertObjectTestCollection(t, db, 1)
	pending := insertObjectTestCollection(t, db, 1)
	inviteCollection(t, repository, pending, 1, 1, 2)
	_, err := db.Exec(fmt.Sprintf(`CREATE FUNCTION fail_related_invitation_acceptance() RETURNS trigger AS $$
		BEGIN
			IF NEW.collection_id = %d AND NEW.acceptance_status = 'accepted' THEN
				RAISE EXCEPTION 'acceptance failure';
			END IF;
			RETURN NEW;
		END;
		$$ LANGUAGE plpgsql;
		CREATE TRIGGER fail_related_invitation_acceptance BEFORE UPDATE ON collection_shares
		FOR EACH ROW EXECUTE FUNCTION fail_related_invitation_acceptance()`, pending))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if _, err := db.Exec(`DROP TRIGGER fail_related_invitation_acceptance ON collection_shares;
			DROP FUNCTION fail_related_invitation_acceptance()`); err != nil {
			t.Error(err)
		}
	})
	if _, err := repository.JoinPublicCollection(t.Context(), joined, 1, 2, "public-key", ente.VIEWER, 300); err == nil {
		t.Fatal("public join succeeded despite related acceptance failure")
	}
	var count int
	if err := db.QueryRow(`SELECT COUNT(*) FROM collection_shares WHERE collection_id = $1 AND to_user_id = 2`, joined).Scan(&count); err != nil {
		t.Fatal(err)
	}
	if count != 0 {
		t.Fatal("failed public join left an accepted membership")
	}
	assertInvitationState(t, db, pending, 2, ente.CollectionPending, false, 1)
	assertCollectionMembershipTestUpdationTime(t, db, joined, 1)
	assertCollectionMembershipTestUpdationTime(t, db, pending, 100)
}

func TestInvitationSyncRemovesPreviousAlbumAndPreservesTimestampTies(t *testing.T) {
	repository, db := setupInvitationTest(t)
	collectionID := insertObjectTestCollection(t, db, 1)
	if err := repository.Share(collectionID, 1, 2, "recipient-key", ente.VIEWER, 100); err != nil {
		t.Fatal(err)
	}
	const cursor int64 = 9000000000000000
	if _, err := db.Exec(`UPDATE collections SET updation_time = $1 WHERE collection_id = $2`, cursor, collectionID); err != nil {
		t.Fatal(err)
	}
	if err := repository.UnShare(collectionID, 2); err != nil {
		t.Fatal(err)
	}
	inviteCollection(t, repository, collectionID, 1, 1, 2)
	if _, err := db.Exec(`UPDATE collections SET name = '', encrypted_name = 'cipher-title', name_decryption_nonce = 'title-nonce' WHERE collection_id = $1`, collectionID); err != nil {
		t.Fatal(err)
	}
	pending, err := repository.GetPendingInvitations(t.Context(), 2)
	if err != nil || len(pending) != 1 {
		t.Fatalf("pending = %v, err = %v", pending, err)
	}
	if pending[0].Inviter.ID != 1 || pending[0].Inviter.Email != "invite-1@ente.com" || pending[0].EncryptedName != "cipher-title" || pending[0].EncryptedKey != "recipient-key" {
		t.Fatalf("unexpected pending metadata: %+v", pending[0])
	}
	deltas, err := repository.GetCollectionsSharedWithUser(2, cursor, ente.Photos, nil)
	if err != nil || len(deltas) != 1 || !deltas[0].IsDeleted || deltas[0].EncryptedName != "" {
		t.Fatalf("pending did not produce stripped tombstone: %+v, %v", deltas, err)
	}
	if _, err := repository.GetCollectionShareeRole(collectionID, 2); err == nil {
		t.Fatal("pending membership granted a role")
	}
	if err := repository.RejectInvitation(t.Context(), 2, collectionID); err != nil {
		t.Fatal(err)
	}
	pending, err = repository.GetPendingInvitations(t.Context(), 2)
	if err != nil || pending == nil || len(pending) != 0 {
		t.Fatalf("empty snapshot = %#v, err = %v", pending, err)
	}

	ids := make([]int64, 3)
	for index := range ids {
		ids[index] = insertObjectTestCollection(t, db, 1)
		insertObjectTestCollectionShare(t, db, ids[index], 1, 2)
		insertObjectTestCollectionShare(t, db, ids[index], 1, 3)
	}
	if _, err := db.Exec(`UPDATE collections SET updation_time = 900 WHERE collection_id = ANY($1)`, pq.Array(ids)); err != nil {
		t.Fatal(err)
	}
	limit := int64(1)
	shared, err := repository.GetCollectionsSharedWithUser(2, 800, ente.Photos, &limit)
	if err != nil {
		t.Fatal(err)
	}
	if len(shared) != 3 {
		t.Fatalf("timestamp tie split across pages: %d rows", len(shared))
	}
	owned, err := repository.GetCollectionsOwnedByUserV2(1, 800, ente.Photos, &limit)
	if err != nil {
		t.Fatal(err)
	}
	if len(owned) != 3 {
		t.Fatalf("owned timestamp tie split across pages: %d rows", len(owned))
	}
	for _, collection := range owned {
		if len(collection.Sharees) != 2 {
			t.Fatalf("pagination truncated sharees: %+v", collection.Sharees)
		}
	}
}

func TestUnsharePreservesMembershipBeforeCollectionLockOrder(t *testing.T) {
	repository, db := setupInvitationTest(t)
	collectionID := insertObjectTestCollection(t, db, 1)
	insertObjectTestCollectionShare(t, db, collectionID, 1, 2)
	fileID := insertObjectTestFile(t, db, 2)
	if _, err := db.Exec(`INSERT INTO collection_files
		(collection_id, file_id, encrypted_key, key_decryption_nonce, updation_time, c_owner_id, f_owner_id)
		VALUES ($1, $2, 'key', 'nonce', 1, 1, 2)`, collectionID, fileID); err != nil {
		t.Fatal(err)
	}

	ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
	defer cancel()
	mutation, err := db.BeginTx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer mutation.Rollback()
	var mutationPID int
	if err := mutation.QueryRowContext(ctx, `SELECT pg_backend_pid()`).Scan(&mutationPID); err != nil {
		t.Fatal(err)
	}
	// Pause a file mutation between its membership and collection updates.
	const cursor int64 = 9000000000000000
	if _, err := mutation.ExecContext(ctx, `UPDATE collection_files SET action = $1, updation_time = $4
		WHERE collection_id = $2 AND file_id = $3`, ente.ActionRemove, collectionID, fileID, cursor); err != nil {
		t.Fatal(err)
	}
	var status ente.CollectionShareStatus
	var unshareErr error
	done := make(chan struct{})
	go func() {
		defer close(done)
		status, unshareErr = repository.UnShareContext(ctx, collectionID, 2)
	}()
	defer func() {
		cancel()
		_ = mutation.Rollback()
		<-done
	}()
	for {
		var waiting bool
		if err := db.QueryRowContext(ctx, `SELECT EXISTS (
			SELECT 1 FROM pg_stat_activity WHERE datname = current_database()
			AND $1 = ANY(pg_blocking_pids(pid))
		)`, mutationPID).Scan(&waiting); err != nil {
			t.Fatal(err)
		}
		if waiting {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if _, err := mutation.ExecContext(ctx, `UPDATE collections SET updation_time = $1
		WHERE collection_id = $2`, cursor, collectionID); err != nil {
		t.Fatalf("file mutation could not finish while unsharing waited: %v", err)
	}
	if err := mutation.Commit(); err != nil {
		t.Fatal(err)
	}
	<-done
	if unshareErr != nil || status != ente.CollectionUnshared {
		t.Fatalf("UnShareContext() = %s, %v", status, unshareErr)
	}
	assertInvitationState(t, db, collectionID, 2, ente.CollectionAccepted, true, 0)
	if state := readCollectionMembershipState(t, db, collectionID, fileID); !state.isDeleted || state.updationTime <= cursor {
		t.Fatalf("unsharing did not produce a file tombstone after the concurrent mutation: %+v", state)
	}
	var timestampsMatch bool
	if err := db.QueryRow(`SELECT cs.updation_time = c.updation_time
		FROM collection_shares cs JOIN collections c USING (collection_id)
		WHERE cs.collection_id = $1 AND cs.to_user_id = 2`, collectionID).Scan(&timestampsMatch); err != nil {
		t.Fatal(err)
	}
	if !timestampsMatch {
		t.Fatal("share and collection sync timestamps differ")
	}
}

func setupInvitationTest(t *testing.T) (*CollectionRepository, *sql.DB) {
	t.Helper()
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	for id := int64(1); id <= 4; id++ {
		testutil.InsertUser(t, db, testutil.UserFixture{UserID: id, Email: fmt.Sprintf("invite-%d@ente.com", id), CreationTime: 1})
	}
	return &CollectionRepository{DB: db, SecretEncryptionKey: testutil.SecretEncryptionKey(), CollectionLinkRepo: &public.CollectionLinkRepo{DB: db}}, db
}

func grantInvitationAdmin(t *testing.T, db *sql.DB, collectionID, ownerID, adminID int64) {
	t.Helper()
	insertObjectTestCollectionShare(t, db, collectionID, ownerID, adminID)
	if _, err := db.Exec(`UPDATE collection_shares SET role_type = 'ADMIN' WHERE collection_id = $1 AND to_user_id = $2`, collectionID, adminID); err != nil {
		t.Fatal(err)
	}
}

func inviteCollection(t *testing.T, repository *CollectionRepository, collectionID, ownerID, inviterID, recipientID int64) {
	t.Helper()
	if err := repository.Share(collectionID, ownerID, recipientID, "share-key", ente.VIEWER, 100,
		ShareAcceptanceOptions{Enabled: true, InviterUserID: inviterID}); err != nil {
		t.Fatal(err)
	}
}

func assertInvitationState(t *testing.T, db *sql.DB, collectionID, recipientID int64, status ente.CollectionAcceptanceStatus, deleted bool, inviterID int64) {
	t.Helper()
	var actual invitationMembership
	if err := db.QueryRow(`SELECT acceptance_status, is_deleted, invited_by_user_id FROM collection_shares
		WHERE collection_id = $1 AND to_user_id = $2`, collectionID, recipientID).Scan(&actual.Status, &actual.Deleted, &actual.InviterID); err != nil {
		t.Fatal(err)
	}
	if actual.Status != status || actual.Deleted != deleted || actual.InviterID.Int64 != inviterID || actual.InviterID.Valid != (inviterID != 0) {
		t.Fatalf("membership %d/%d = %+v, want %s deleted=%v inviter=%d", collectionID, recipientID, actual, status, deleted, inviterID)
	}
}
