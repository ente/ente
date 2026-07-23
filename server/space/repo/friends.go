package repo

import (
	"context"
	"database/sql"
	"errors"
	"strings"

	"github.com/ente/museum/ente/base"
	"github.com/ente/stacktrace"
	"github.com/lib/pq"
)

var (
	ErrAlreadyFriends                 = errors.New("space users are already friends")
	ErrSelfFriendship                 = errors.New("space users cannot friend themselves")
	ErrSpaceFriendRequestLimitReached = errors.New("space friend request limit reached")
)

const MaxPendingFriendRequestsPerSpace = 100

type friendShareMutation struct {
	SpaceID              string
	FriendSpaceID        string
	FriendSealedSpaceKey []byte
	KeyVersion           int
}

type friendShareExecer interface {
	ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
}

func areMutualFriendsTx(ctx context.Context, tx *sql.Tx, firstSpaceID string, secondSpaceID string) (bool, error) {
	var alreadyFriends bool
	if err := tx.QueryRowContext(ctx, `
		SELECT EXISTS (
			SELECT 1
			FROM space_friend_shares second_share
			JOIN space_friend_shares first_share
			  ON first_share.space_id = $1
			 AND first_share.friend_space_id = $2
			WHERE second_share.space_id = $2
			  AND second_share.friend_space_id = $1
		)
	`, firstSpaceID, secondSpaceID).Scan(&alreadyFriends); err != nil {
		return false, stacktrace.Propagate(err, "")
	}
	return alreadyFriends, nil
}

func upsertMutualFriendSharesTx(ctx context.Context, tx *sql.Tx, first friendShareMutation, second friendShareMutation) error {
	if err := upsertFriendShare(ctx, tx, first); err != nil {
		return err
	}
	return upsertFriendShare(ctx, tx, second)
}

func upsertFriendShare(ctx context.Context, execer friendShareExecer, share friendShareMutation) error {
	_, err := execer.ExecContext(ctx, `
		INSERT INTO space_friend_shares (space_id, friend_space_id, friend_sealed_space_key, key_version)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (space_id, friend_space_id) DO UPDATE
		SET friend_sealed_space_key = EXCLUDED.friend_sealed_space_key,
		    key_version = EXCLUDED.key_version
	`, share.SpaceID, share.FriendSpaceID, share.FriendSealedSpaceKey, share.KeyVersion)
	return stacktrace.Propagate(err, "")
}

func insertFriendAddedActivityTx(ctx context.Context, tx *sql.Tx, senderSpaceID string, recipientSpaceID string) (int64, error) {
	var createdAt int64
	if err := tx.QueryRowContext(ctx, `
		INSERT INTO space_messages (
			message_id,
			sender_space_id,
			recipient_space_id,
			kind
		)
		VALUES ($1, $2, $3, 'friend_added')
		RETURNING created_at
	`, base.MustNewID("wmsg"), senderSpaceID, recipientSpaceID).Scan(&createdAt); err != nil {
		return 0, stacktrace.Propagate(err, "")
	}
	if err := upsertNotificationReadMarker(ctx, tx, senderSpaceID, recipientSpaceID, createdAt); err != nil {
		return 0, err
	}
	return createdAt, nil
}

func (r *FriendsRepository) CreateFriendRequest(ctx context.Context, requesterID int64, requesterSpaceID string, targetSpaceID string, requesterFriendSealedSpaceKey []byte, requesterKeyVersion int) (*SpaceFriendRequestRecord, bool, bool, error) {
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, false, false, stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()

	var requesterOwnerID int64
	var requesterCurrentVersion int
	if err := tx.QueryRowContext(ctx, `
		SELECT owner_id, current_version
		FROM spaces
		WHERE space_id = $1
		FOR UPDATE
	`, requesterSpaceID).Scan(&requesterOwnerID, &requesterCurrentVersion); err != nil {
		return nil, false, false, stacktrace.Propagate(err, "")
	}
	if requesterOwnerID != requesterID || requesterCurrentVersion != requesterKeyVersion {
		return nil, false, false, sql.ErrNoRows
	}

	var targetOwnerID int64
	var targetCurrentVersion int
	if err := tx.QueryRowContext(ctx, `
		SELECT target_space.owner_id, target_space.current_version
		FROM spaces target_space
		JOIN users target_owner ON target_owner.user_id = target_space.owner_id AND target_owner.encrypted_email IS NOT NULL
		WHERE target_space.space_id = $1
		FOR UPDATE OF target_space
	`, targetSpaceID).Scan(&targetOwnerID, &targetCurrentVersion); err != nil {
		return nil, false, false, stacktrace.Propagate(err, "")
	}
	if targetOwnerID == requesterID {
		return nil, false, false, ErrSelfFriendship
	}

	alreadyFriends, err := areMutualFriendsTx(ctx, tx, requesterSpaceID, targetSpaceID)
	if err != nil {
		return nil, false, false, err
	}
	if alreadyFriends {
		return nil, false, false, ErrAlreadyFriends
	}

	var rec SpaceFriendRequestRecord
	err = tx.QueryRowContext(ctx, `
		SELECT request_id, created_at
		FROM space_friend_requests
		WHERE requester_space_id = $1
		  AND target_space_id = $2
		FOR UPDATE
	`, requesterSpaceID, targetSpaceID).Scan(&rec.RequestID, &rec.CreatedAt)
	switch {
	case err == nil:
		if _, err := tx.ExecContext(ctx, `
			UPDATE space_friend_requests
			SET requester_friend_sealed_space_key = $2,
			    requester_key_version = $3
			WHERE request_id = $1
		`, rec.RequestID, requesterFriendSealedSpaceKey, requesterKeyVersion); err != nil {
			return nil, false, false, stacktrace.Propagate(err, "")
		}
		rec.RequesterID = requesterID
		rec.RequesterSpaceID = requesterSpaceID
		rec.TargetID = targetOwnerID
		rec.TargetSpaceID = targetSpaceID
		rec.RequesterFriendSealedSpaceKey = requesterFriendSealedSpaceKey
		rec.RequesterKeyVersion = requesterKeyVersion
		return &rec, false, false, stacktrace.Propagate(tx.Commit(), "")
	case !errors.Is(err, sql.ErrNoRows):
		return nil, false, false, stacktrace.Propagate(err, "")
	}

	var reverse SpaceFriendRequestRecord
	err = tx.QueryRowContext(ctx, `
		SELECT request_id, requester_friend_sealed_space_key, requester_key_version, created_at
		FROM space_friend_requests
		WHERE requester_space_id = $1
		  AND target_space_id = $2
		FOR UPDATE
	`, targetSpaceID, requesterSpaceID).Scan(
		&reverse.RequestID,
		&reverse.RequesterFriendSealedSpaceKey,
		&reverse.RequesterKeyVersion,
		&reverse.CreatedAt,
	)
	switch {
	case err == nil:
		if targetCurrentVersion != reverse.RequesterKeyVersion {
			return nil, false, false, sql.ErrNoRows
		}
		if err := upsertMutualFriendSharesTx(ctx, tx,
			friendShareMutation{
				SpaceID:              requesterSpaceID,
				FriendSpaceID:        targetSpaceID,
				FriendSealedSpaceKey: requesterFriendSealedSpaceKey,
				KeyVersion:           requesterKeyVersion,
			},
			friendShareMutation{
				SpaceID:              targetSpaceID,
				FriendSpaceID:        requesterSpaceID,
				FriendSealedSpaceKey: reverse.RequesterFriendSealedSpaceKey,
				KeyVersion:           reverse.RequesterKeyVersion,
			},
		); err != nil {
			return nil, false, false, err
		}
		if _, err := tx.ExecContext(ctx, `DELETE FROM space_friend_requests WHERE request_id = $1`, reverse.RequestID); err != nil {
			return nil, false, false, stacktrace.Propagate(err, "")
		}
		if _, err := insertFriendAddedActivityTx(ctx, tx, requesterSpaceID, targetSpaceID); err != nil {
			return nil, false, false, err
		}
		reverse.RequesterID = targetOwnerID
		reverse.RequesterSpaceID = targetSpaceID
		reverse.TargetID = requesterID
		reverse.TargetSpaceID = requesterSpaceID
		return &reverse, false, true, stacktrace.Propagate(tx.Commit(), "")
	case !errors.Is(err, sql.ErrNoRows):
		return nil, false, false, stacktrace.Propagate(err, "")
	}

	var pendingRequestCount int
	if err := tx.QueryRowContext(ctx, `
		SELECT COUNT(*)
		FROM space_friend_requests
		WHERE target_space_id = $1
	`, targetSpaceID).Scan(&pendingRequestCount); err != nil {
		return nil, false, false, stacktrace.Propagate(err, "")
	}
	if pendingRequestCount >= MaxPendingFriendRequestsPerSpace {
		return nil, false, false, ErrSpaceFriendRequestLimitReached
	}

	if err := tx.QueryRowContext(ctx, `
			INSERT INTO space_friend_requests (
				requester_space_id,
				target_space_id,
				requester_friend_sealed_space_key,
				requester_key_version
			)
			VALUES ($1, $2, $3, $4)
			RETURNING request_id, created_at
		`, requesterSpaceID, targetSpaceID, requesterFriendSealedSpaceKey, requesterKeyVersion).Scan(&rec.RequestID, &rec.CreatedAt); err != nil {
		return nil, false, false, stacktrace.Propagate(err, "")
	}
	rec.RequesterID = requesterID
	rec.RequesterSpaceID = requesterSpaceID
	rec.TargetID = targetOwnerID
	rec.TargetSpaceID = targetSpaceID
	rec.RequesterFriendSealedSpaceKey = requesterFriendSealedSpaceKey
	rec.RequesterKeyVersion = requesterKeyVersion
	return &rec, true, false, stacktrace.Propagate(tx.Commit(), "")
}

func (r *FriendsRepository) ListFriendRequestsForSpace(ctx context.Context, targetSpaceID string) ([]SpaceFriendRequestRecord, error) {
	query := `
		SELECT fr.request_id,
		       fr.created_at,
		       ` + spaceActorPublicSelectColumns("requester_space", "requester") + `
		FROM space_friend_requests fr
		JOIN spaces requester_space ON requester_space.space_id = fr.requester_space_id
		JOIN users requester_owner ON requester_owner.user_id = requester_space.owner_id AND requester_owner.encrypted_email IS NOT NULL
		WHERE fr.target_space_id = $1
		ORDER BY fr.created_at DESC, fr.request_id DESC
	`
	rows, err := r.DB.QueryContext(ctx, query, targetSpaceID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()

	var out []SpaceFriendRequestRecord
	for rows.Next() {
		var rec SpaceFriendRequestRecord
		dest := []any{
			&rec.RequestID,
			&rec.CreatedAt,
		}
		dest = append(dest, spaceActorScanDest(&rec.Requester)...)
		if err := rows.Scan(dest...); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		out = append(out, rec)
	}
	return out, stacktrace.Propagate(rows.Err(), "")
}

func (r *FriendsRepository) ConfirmFriendRequest(ctx context.Context, targetSpaceID string, requestID int64, targetFriendSealedSpaceKey []byte, targetKeyVersion int) (int64, bool, error) {
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return 0, false, stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()

	var requesterSpaceID string
	var requesterFriendSealedSpaceKey []byte
	var requesterKeyVersion int
	var requesterCurrentVersion int
	var requesterOwnerID int64
	var targetCurrentVersion int
	if err := tx.QueryRowContext(ctx, `
		SELECT fr.requester_space_id,
		       fr.requester_friend_sealed_space_key,
		       fr.requester_key_version,
		       requester_space.owner_id,
		       requester_space.current_version,
		       target_space.current_version
		FROM space_friend_requests fr
		JOIN spaces requester_space ON requester_space.space_id = fr.requester_space_id
		JOIN users requester_owner ON requester_owner.user_id = requester_space.owner_id AND requester_owner.encrypted_email IS NOT NULL
		JOIN spaces target_space ON target_space.space_id = fr.target_space_id
		WHERE fr.request_id = $1
		  AND fr.target_space_id = $2
		FOR UPDATE OF fr, requester_space, target_space
	`, requestID, targetSpaceID).Scan(
		&requesterSpaceID,
		&requesterFriendSealedSpaceKey,
		&requesterKeyVersion,
		&requesterOwnerID,
		&requesterCurrentVersion,
		&targetCurrentVersion,
	); err != nil {
		return 0, false, stacktrace.Propagate(err, "")
	}
	if targetCurrentVersion != targetKeyVersion || requesterCurrentVersion != requesterKeyVersion {
		return 0, false, sql.ErrNoRows
	}

	alreadyFriends, err := areMutualFriendsTx(ctx, tx, requesterSpaceID, targetSpaceID)
	if err != nil {
		return 0, false, err
	}
	if err := upsertMutualFriendSharesTx(ctx, tx,
		friendShareMutation{
			SpaceID:              targetSpaceID,
			FriendSpaceID:        requesterSpaceID,
			FriendSealedSpaceKey: targetFriendSealedSpaceKey,
			KeyVersion:           targetKeyVersion,
		},
		friendShareMutation{
			SpaceID:              requesterSpaceID,
			FriendSpaceID:        targetSpaceID,
			FriendSealedSpaceKey: requesterFriendSealedSpaceKey,
			KeyVersion:           requesterKeyVersion,
		},
	); err != nil {
		return 0, false, err
	}

	if _, err := tx.ExecContext(ctx, `
		DELETE FROM space_friend_requests
		WHERE request_id = $1
		   OR (requester_space_id = $2 AND target_space_id = $3)
	`, requestID, targetSpaceID, requesterSpaceID); err != nil {
		return 0, false, stacktrace.Propagate(err, "")
	}
	if !alreadyFriends {
		if _, err := insertFriendAddedActivityTx(ctx, tx, targetSpaceID, requesterSpaceID); err != nil {
			return 0, false, err
		}
	}

	if err := tx.Commit(); err != nil {
		return 0, false, stacktrace.Propagate(err, "")
	}
	return requesterOwnerID, !alreadyFriends, nil
}

func (r *FriendsRepository) DeleteFriendRequest(ctx context.Context, targetSpaceID string, requestID int64) error {
	res, err := r.DB.ExecContext(ctx, `
		DELETE FROM space_friend_requests
		WHERE request_id = $1
		  AND target_space_id = $2
	`, requestID, targetSpaceID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	affected, err := res.RowsAffected()
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if affected == 0 {
		return sql.ErrNoRows
	}
	return nil
}

func (r *FriendsRepository) UpdateShares(ctx context.Context, spaceID string, shares []SpaceShareUpdateRecord, keyVersion int) error {
	if len(shares) == 0 {
		return nil
	}
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()

	var currentVersion int
	if err := tx.QueryRowContext(ctx, `
		SELECT current_version
		FROM spaces
		WHERE space_id = $1
		FOR UPDATE
	`, spaceID).Scan(&currentVersion); err != nil {
		return stacktrace.Propagate(err, "")
	}
	if currentVersion != keyVersion {
		return sql.ErrNoRows
	}

	for _, share := range shares {
		friendSpaceID := strings.TrimSpace(share.FriendSpaceID)
		if friendSpaceID == "" {
			return sql.ErrNoRows
		}
		res, err := tx.ExecContext(ctx, `
			UPDATE space_friend_shares
			SET friend_sealed_space_key = $3,
			    key_version = $4
			WHERE space_id = $1 AND friend_space_id = $2
		`, spaceID, friendSpaceID, share.FriendSealedSpaceKey, keyVersion)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
		affected, err := res.RowsAffected()
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
		if affected == 0 {
			return sql.ErrNoRows
		}
	}
	return stacktrace.Propagate(tx.Commit(), "")
}

func (r *FriendsRepository) DeleteFriendship(ctx context.Context, actorSpaceID string, targetSpaceID string) error {
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()

	var actorOwnerID int64
	var targetOwnerID int64
	if err := tx.QueryRowContext(ctx, `
		SELECT actor_space.owner_id, target_space.owner_id
		FROM spaces target_space
		JOIN spaces actor_space ON actor_space.space_id = $2
		WHERE target_space.space_id = $1
	`, targetSpaceID, actorSpaceID).Scan(&actorOwnerID, &targetOwnerID); err != nil {
		return stacktrace.Propagate(err, "")
	}
	if targetOwnerID == actorOwnerID {
		return nil
	}

	if _, err := tx.ExecContext(ctx, `
		DELETE FROM space_friend_shares
		WHERE (space_id = $1 AND friend_space_id = $2)
		   OR (space_id = $2 AND friend_space_id = $1)
	`, targetSpaceID, actorSpaceID); err != nil {
		return stacktrace.Propagate(err, "")
	}
	return stacktrace.Propagate(tx.Commit(), "")
}

func (r *FriendsRepository) GetShareForFriendAndSpace(ctx context.Context, friendSpaceID string, spaceID string) (*SpaceShareRecord, error) {
	return scanShareRecord(r.DB.QueryRowContext(ctx, `
		SELECT s.space_id, w.space_slug, s.friend_sealed_space_key, s.key_version, s.created_at
		FROM space_friend_shares s
		JOIN spaces w ON w.space_id = s.space_id
		JOIN users u ON u.user_id = w.owner_id AND u.encrypted_email IS NOT NULL
		WHERE s.friend_space_id = $1 AND s.space_id = $2
	`, friendSpaceID, spaceID))
}

func (r *FriendsRepository) ListSharesForFriendAndSpace(ctx context.Context, friendSpaceID string) ([]SpaceShareRecord, error) {
	rows, err := r.DB.QueryContext(ctx, `
		SELECT s.space_id, w.space_slug, s.friend_sealed_space_key, s.key_version, s.created_at
		FROM space_friend_shares s
		JOIN spaces w ON w.space_id = s.space_id
		JOIN users u ON u.user_id = w.owner_id AND u.encrypted_email IS NOT NULL
		WHERE s.friend_space_id = $1
		ORDER BY s.created_at ASC
	`, friendSpaceID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	var out []SpaceShareRecord
	for rows.Next() {
		rec, err := scanShareRecord(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *rec)
	}
	return out, stacktrace.Propagate(rows.Err(), "")
}

func (r *FriendsRepository) ListFriendOwnerIDsForSpace(ctx context.Context, spaceID string) ([]int64, error) {
	rows, err := r.DB.QueryContext(ctx, `
		SELECT friend_space.owner_id
		FROM space_friend_shares s
		JOIN spaces friend_space ON friend_space.space_id = s.friend_space_id
		JOIN users friend_owner ON friend_owner.user_id = friend_space.owner_id AND friend_owner.encrypted_email IS NOT NULL
		WHERE s.space_id = $1
	`, spaceID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	var out []int64
	for rows.Next() {
		var ownerID int64
		if err := rows.Scan(&ownerID); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		out = append(out, ownerID)
	}
	return out, stacktrace.Propagate(rows.Err(), "")
}

func (r *FriendsRepository) ListFriendsForSpace(ctx context.Context, spaceID string) ([]SpaceFriendRecord, error) {
	query := `
		SELECT ` + spaceActorSelectColumns("friend_space", "friend_avatar", "friend") + `,
		       s.key_version,
		       s.created_at
		FROM space_friend_shares s
		JOIN spaces friend_space ON friend_space.space_id = s.friend_space_id
		` + spaceActorAvatarJoin("friend_space", "friend_avatar") + `
		JOIN users friend_owner ON friend_owner.user_id = friend_space.owner_id AND friend_owner.encrypted_email IS NOT NULL
		WHERE s.space_id = $1
		ORDER BY lower(friend_space.space_slug) ASC
	`
	rows, err := r.DB.QueryContext(ctx, query, spaceID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	var out []SpaceFriendRecord
	for rows.Next() {
		var rec SpaceFriendRecord
		dest := spaceActorScanDest(&rec.Friend)
		dest = append(dest, &rec.ShareKeyVersion, &rec.CreatedAt)
		if err := rows.Scan(dest...); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		out = append(out, rec)
	}
	return out, stacktrace.Propagate(rows.Err(), "")
}

func (r *FriendsRepository) CountFriendsForSpace(ctx context.Context, spaceID string) (int64, error) {
	var count int64
	if err := r.DB.QueryRowContext(ctx, `
		SELECT COUNT(*)
		FROM space_friend_shares
		WHERE space_id = $1
	`, spaceID).Scan(&count); err != nil {
		return 0, stacktrace.Propagate(err, "")
	}
	return count, nil
}

func (r *FriendsRepository) ListAccessibleSpaceIDs(ctx context.Context, viewerID int64, viewerSpaceID string, spaceIDs []string) (map[string]bool, error) {
	out := make(map[string]bool, len(spaceIDs))
	if viewerID <= 0 || strings.TrimSpace(viewerSpaceID) == "" || len(spaceIDs) == 0 {
		return out, nil
	}
	rows, err := r.DB.QueryContext(ctx, `
		SELECT space_id
		FROM spaces
		WHERE owner_id = $1 AND space_id = ANY($2)
		UNION
		SELECT w.space_id
		FROM space_friend_shares s
		JOIN spaces w ON w.space_id = s.space_id
		JOIN spaces friend_space ON friend_space.space_id = s.friend_space_id
		JOIN users u ON u.user_id = w.owner_id AND u.encrypted_email IS NOT NULL
		WHERE friend_space.owner_id = $1 AND s.friend_space_id = $3 AND s.space_id = ANY($2)
	`, viewerID, pq.Array(spaceIDs), viewerSpaceID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	for rows.Next() {
		var spaceID string
		if err := rows.Scan(&spaceID); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		out[spaceID] = true
	}
	return out, stacktrace.Propagate(rows.Err(), "")
}

func (r *FriendsRepository) GetRelationship(ctx context.Context, viewerSpaceID string, targetSpaceID string) (string, error) {
	var count int64
	if err := r.DB.QueryRowContext(ctx, `
		SELECT COUNT(*)
		FROM space_friend_shares s
		WHERE s.friend_space_id = $1
		  AND s.space_id = $2
	`, viewerSpaceID, targetSpaceID).Scan(&count); err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	if count > 0 {
		return "friend", nil
	}
	return "", nil
}

func scanShareRecord(scanner interface{ Scan(dest ...any) error }) (*SpaceShareRecord, error) {
	var rec SpaceShareRecord
	if err := scanner.Scan(&rec.SpaceID, &rec.SpaceSlug, &rec.FriendSealedSpaceKey, &rec.KeyVersion, &rec.CreatedAt); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &rec, nil
}
