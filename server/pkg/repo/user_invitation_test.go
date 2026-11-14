package repo

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
)

func TestDeleteTxWithdrawsOnlyPendingInvitationsFromDeletedInviter(t *testing.T) {
	_, db := setupAccessibleObjectTest(t)
	for userID := int64(1); userID <= 8; userID++ {
		testutil.InsertUser(t, db, testutil.UserFixture{
			UserID: userID, Email: fmt.Sprintf("inviter-delete-%d@ente.com", userID), CreationTime: 1,
		})
	}
	ownedCollectionID := insertObjectTestCollection(t, db, 2)
	adminCollectionID := insertObjectTestCollection(t, db, 1)
	type membership struct {
		collectionID int64
		ownerID      int64
		recipientID  int64
		inviterID    any
		status       string
		deleted      bool
		withdrawn    bool
	}
	memberships := []membership{
		{ownedCollectionID, 2, 3, int64(2), "pending", false, true},
		{adminCollectionID, 1, 3, int64(2), "pending", false, true},
		{adminCollectionID, 1, 4, int64(2), "accepted", false, false},
		{adminCollectionID, 1, 5, int64(2), "rejected", true, false},
		{adminCollectionID, 1, 6, int64(1), "pending", false, false},
		{adminCollectionID, 1, 7, nil, "accepted", false, false},
		{adminCollectionID, 1, 8, int64(2), "pending", true, false},
	}
	for _, member := range memberships {
		insertObjectTestCollectionShare(t, db, member.collectionID, member.ownerID, member.recipientID)
		if _, err := db.Exec(`UPDATE collection_shares
			SET invited_by_user_id = $1, acceptance_status = $2, is_deleted = $3
			WHERE collection_id = $4 AND to_user_id = $5`, member.inviterID, member.status, member.deleted, member.collectionID, member.recipientID); err != nil {
			t.Fatal(err)
		}
	}
	repository := &UserRepository{DB: db}
	for _, commit := range []bool{false, true} {
		tx, err := db.BeginTx(t.Context(), nil)
		if err != nil {
			t.Fatal(err)
		}
		defer tx.Rollback()
		if _, _, err := repository.DeleteTx(t.Context(), tx, 2); err != nil {
			t.Fatalf("DeleteTx() error = %v", err)
		}
		if commit {
			err = tx.Commit()
		} else {
			err = tx.Rollback()
		}
		if err != nil {
			t.Fatal(err)
		}
		var userDeleted bool
		if err := db.QueryRow(`SELECT encrypted_email IS NULL FROM users WHERE user_id = 2`).Scan(&userDeleted); err != nil {
			t.Fatal(err)
		}
		if userDeleted != commit {
			t.Fatalf("user deleted = %v after commit=%v", userDeleted, commit)
		}
		for _, member := range memberships {
			var deleted bool
			var status string
			var inviterID *int64
			var sharedAt, shareUpdatedAt, collectionUpdatedAt int64
			if err := db.QueryRow(`SELECT cs.is_deleted, cs.acceptance_status, cs.invited_by_user_id,
				cs.shared_at, cs.updation_time, c.updation_time
				FROM collection_shares cs JOIN collections c ON c.collection_id = cs.collection_id
				WHERE cs.collection_id = $1 AND cs.to_user_id = $2`, member.collectionID, member.recipientID).
				Scan(&deleted, &status, &inviterID, &sharedAt, &shareUpdatedAt, &collectionUpdatedAt); err != nil {
				t.Fatal(err)
			}
			shouldWithdraw := commit && member.withdrawn
			if deleted != (member.deleted || shouldWithdraw) || status != member.status || sharedAt != 1 {
				t.Fatalf("unexpected membership after commit=%v: %+v; deleted=%v status=%s sharedAt=%d", commit, member, deleted, status, sharedAt)
			}
			if member.inviterID == nil {
				if inviterID != nil {
					t.Fatalf("historical inviter changed to %v", inviterID)
				}
			} else if inviterID == nil || *inviterID != member.inviterID.(int64) {
				t.Fatalf("original inviter changed: %+v", member)
			}
			if shouldWithdraw {
				if shareUpdatedAt <= 1 || collectionUpdatedAt < shareUpdatedAt {
					t.Fatalf("withdrawal did not update share and parent timestamps: %d, %d", shareUpdatedAt, collectionUpdatedAt)
				}
			} else if shareUpdatedAt != 1 {
				t.Fatalf("unaffected or rolled-back membership changed: %+v", member)
			}
			if !commit && collectionUpdatedAt != 1 {
				t.Fatal("parent timestamp changed despite rollback")
			}
		}
	}
}

func TestDeleteTxSerializesConcurrentInvitationMutations(t *testing.T) {
	for _, operation := range []string{"accept", "share"} {
		t.Run(operation, func(t *testing.T) {
			_, db := setupAccessibleObjectTest(t)
			for userID := int64(1); userID <= 3; userID++ {
				testutil.InsertUser(t, db, testutil.UserFixture{
					UserID: userID, Email: fmt.Sprintf("concurrent-inviter-%d@ente.com", userID), CreationTime: 1,
				})
			}
			collectionID := insertObjectTestCollection(t, db, 1)
			insertObjectTestCollectionShare(t, db, collectionID, 1, 2)
			if _, err := db.Exec(`UPDATE collection_shares SET role_type = 'ADMIN' WHERE collection_id = $1`, collectionID); err != nil {
				t.Fatal(err)
			}
			collectionRepo := &CollectionRepository{DB: db}
			share := func(ctx context.Context) error {
				return collectionRepo.BatchShare(ctx, collectionID, 1,
					[]CollectionShareItem{{ToUserID: 3, EncryptedKey: "share-key", Role: ente.VIEWER}}, 2,
					ShareAcceptanceOptions{Enabled: true, InviterUserID: 2})
			}
			if err := share(t.Context()); err != nil {
				t.Fatal(err)
			}
			tx, err := db.BeginTx(t.Context(), nil)
			if err != nil {
				t.Fatal(err)
			}
			defer tx.Rollback()
			var blockerPID int
			if err := tx.QueryRow(`SELECT pg_backend_pid()`).Scan(&blockerPID); err != nil {
				t.Fatal(err)
			}
			if _, _, err := (&UserRepository{DB: db}).DeleteTx(t.Context(), tx, 2); err != nil {
				t.Fatal(err)
			}
			ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
			defer cancel()
			done := make(chan error, 1)
			go func() {
				if operation == "accept" {
					_, err := collectionRepo.AcceptInvitations(ctx, 3, []int64{collectionID})
					done <- err
				} else {
					done <- share(ctx)
				}
			}()
			ticker := time.NewTicker(10 * time.Millisecond)
			defer ticker.Stop()
			for {
				var waiting bool
				if err := db.QueryRowContext(ctx, `SELECT EXISTS (
					SELECT 1 FROM pg_stat_activity WHERE $1 = ANY(pg_blocking_pids(pid))
				)`, blockerPID).Scan(&waiting); err != nil {
					t.Fatal(err)
				}
				if waiting {
					break
				}
				select {
				case err := <-done:
					t.Fatalf("%s completed before deletion committed: %v", operation, err)
				case <-ctx.Done():
					t.Fatal("invitation mutation never waited for account deletion")
				case <-ticker.C:
				}
			}
			if err := tx.Commit(); err != nil {
				t.Fatal(err)
			}
			select {
			case err := <-done:
				if !errors.Is(err, ente.ErrPermissionDenied) {
					t.Fatalf("%s after inviter deletion: got %v, want permission denied", operation, err)
				}
			case <-ctx.Done():
				t.Fatal("invitation mutation did not finish after deletion committed")
			}
			var deleted bool
			var status string
			if err := db.QueryRow(`SELECT is_deleted, acceptance_status FROM collection_shares
				WHERE collection_id = $1 AND to_user_id = 3`, collectionID).Scan(&deleted, &status); err != nil {
				t.Fatal(err)
			}
			if !deleted || status != "pending" {
				t.Fatalf("concurrent %s restored withdrawn invitation: deleted=%v status=%s", operation, deleted, status)
			}
		})
	}
}
