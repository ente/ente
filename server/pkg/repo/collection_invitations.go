package repo

import (
	"context"
	"database/sql"
	"sort"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/crypto"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/lib/pq"
)

type ShareAcceptanceOptions struct {
	Enabled       bool
	InviterUserID int64
}

type invitationCollection struct {
	ID           int64
	OwnerID      int64
	App          ente.App
	Deleted      bool
	OwnerActive  bool
	UpdationTime int64
}

type invitationMembership struct {
	CollectionID int64
	InviterID    sql.NullInt64
	Status       ente.CollectionAcceptanceStatus
	Deleted      bool
}

func (repo *CollectionRepository) GetPendingInvitations(ctx context.Context, userID int64) ([]ente.CollectionInvitation, error) {
	rows, err := repo.DB.QueryContext(ctx, `SELECT cs.collection_id, cs.invited_by_user_id,
		inviter.encrypted_email, inviter.email_decryption_nonce, cs.encrypted_key,
		c.name, c.encrypted_name, c.name_decryption_nonce, COALESCE(cs.shared_at, cs.updation_time)
		FROM collection_shares cs
		JOIN collections c ON c.collection_id = cs.collection_id
		JOIN users inviter ON inviter.user_id = cs.invited_by_user_id
		JOIN users owner ON owner.user_id = c.owner_id
		WHERE cs.to_user_id = $1 AND cs.is_deleted = FALSE AND cs.acceptance_status = 'pending'
			AND c.is_deleted = FALSE AND c.app = 'photos'
			AND inviter.encrypted_email IS NOT NULL AND owner.encrypted_email IS NOT NULL
		ORDER BY cs.shared_at DESC NULLS LAST, cs.collection_id DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := make([]ente.CollectionInvitation, 0)
	for rows.Next() {
		var invitation ente.CollectionInvitation
		var name, encryptedName, nameNonce sql.NullString
		var email, nonce []byte
		if err := rows.Scan(&invitation.CollectionID, &invitation.Inviter.ID, &email, &nonce,
			&invitation.EncryptedKey, &name, &encryptedName, &nameNonce, &invitation.SharedAt); err != nil {
			return nil, err
		}
		invitation.Inviter.Email, err = crypto.Decrypt(email, repo.SecretEncryptionKey, nonce)
		if err != nil {
			return nil, err
		}
		if name.String != "" {
			invitation.Name = name.String
		} else {
			invitation.EncryptedName = encryptedName.String
			invitation.NameDecryptionNonce = nameNonce.String
		}
		result = append(result, invitation)
	}
	return result, rows.Err()
}

func (repo *CollectionRepository) AcceptInvitations(ctx context.Context, userID int64, collectionIDs []int64) ([]int64, error) {
	ids, err := invitationIDs(collectionIDs)
	if err != nil {
		return nil, err
	}
	tx, err := repo.DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	memberships, err := readInvitationMemberships(ctx, tx, userID, ids, false)
	if err != nil || len(memberships) != len(ids) {
		if err != nil {
			return nil, err
		}
		return nil, ente.ErrPermissionDenied
	}
	inviterID := memberships[0].InviterID
	if !inviterID.Valid && (len(ids) != 1 || memberships[0].Status != ente.CollectionAccepted) {
		return nil, ente.ErrBadRequest
	}
	userIDs := []int64{userID}
	for _, membership := range memberships {
		if membership.Status == ente.CollectionPending && inviterID.Valid {
			userIDs = append(userIDs, inviterID.Int64)
			break
		}
	}
	ownerRows, err := tx.QueryContext(ctx, `SELECT owner_id FROM collections WHERE collection_id = ANY($1)`, pq.Array(ids))
	if err != nil {
		return nil, err
	}
	for ownerRows.Next() {
		var ownerID int64
		if err := ownerRows.Scan(&ownerID); err != nil {
			ownerRows.Close()
			return nil, err
		}
		userIDs = append(userIDs, ownerID)
	}
	err = ownerRows.Err()
	ownerRows.Close()
	if err != nil {
		return nil, err
	}
	if err := lockActiveShareUsers(ctx, tx, userIDs); err != nil {
		return nil, err
	}
	collections, err := lockInvitationCollections(ctx, tx, ids)
	if err != nil {
		return nil, err
	}
	memberships, err = readInvitationMemberships(ctx, tx, userID, ids, true)
	if err != nil {
		return nil, err
	}
	if len(collections) != len(ids) || len(memberships) != len(ids) {
		return nil, ente.ErrPermissionDenied
	}
	changed := make([]int64, 0, len(ids))
	for _, membership := range memberships {
		collection := collections[membership.CollectionID]
		if collection.Deleted || collection.App != ente.Photos || membership.Deleted ||
			membership.InviterID != inviterID || membership.Status == ente.CollectionRejected {
			return nil, ente.ErrPermissionDenied
		}
		if membership.Status == ente.CollectionPending {
			changed = append(changed, membership.CollectionID)
		}
	}
	if err := acceptInvitationRows(ctx, tx, userID, changed, time.Microseconds()); err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return ids, nil
}

func (repo *CollectionRepository) RejectInvitation(ctx context.Context, userID, collectionID int64) error {
	tx, err := repo.DB.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err := lockActiveShareUsers(ctx, tx, []int64{userID}); err != nil {
		return err
	}
	collections, err := lockInvitationCollections(ctx, tx, []int64{collectionID})
	if err != nil {
		return err
	}
	collection, found := collections[collectionID]
	if !found || collection.Deleted || collection.App != ente.Photos {
		return ente.ErrPermissionDenied
	}
	memberships, err := readInvitationMemberships(ctx, tx, userID, []int64{collectionID}, true)
	if err != nil {
		return err
	}
	if len(memberships) != 1 {
		return ente.ErrPermissionDenied
	}
	membership := memberships[0]
	if membership.Status == ente.CollectionRejected {
		return nil
	}
	if membership.Deleted || membership.Status != ente.CollectionPending {
		return ente.ErrPermissionDenied
	}
	if err := touchInvitationCollections(ctx, tx, []int64{collectionID}, time.Microseconds()); err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, `UPDATE collection_shares cs
		SET acceptance_status = 'rejected', is_deleted = TRUE, updation_time = c.updation_time
		FROM collections c WHERE cs.collection_id = c.collection_id
			AND cs.collection_id = $1 AND cs.to_user_id = $2`, collectionID, userID)
	if err != nil {
		return err
	}
	return tx.Commit()
}

func (repo *CollectionRepository) JoinPublicCollection(ctx context.Context, collectionID, ownerID, userID int64,
	encryptedKey string, role ente.CollectionParticipantRole, updationTime int64) ([]int64, error) {
	if !validShareRole(role) || userID == ownerID {
		return nil, ente.ErrBadRequest
	}
	tx, err := repo.DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	if err := lockActiveShareUsers(ctx, tx, []int64{ownerID, userID}); err != nil {
		return nil, err
	}
	rows, err := tx.QueryContext(ctx, `SELECT cs.collection_id FROM collection_shares cs
		JOIN collections c ON c.collection_id = cs.collection_id
		JOIN users owner ON owner.user_id = c.owner_id AND owner.encrypted_email IS NOT NULL
		WHERE cs.to_user_id = $1 AND cs.invited_by_user_id = $2
			AND cs.is_deleted = FALSE AND cs.acceptance_status = 'pending'
			AND c.is_deleted = FALSE AND c.app = 'photos'`, userID, ownerID)
	if err != nil {
		return nil, err
	}
	ids := []int64{collectionID}
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return nil, err
		}
		if id != collectionID {
			ids = append(ids, id)
		}
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return nil, err
	}
	collections, err := lockInvitationCollections(ctx, tx, ids)
	if err != nil {
		return nil, err
	}
	collection, found := collections[collectionID]
	if !found || collection.Deleted || collection.OwnerID != ownerID {
		return nil, ente.ErrCollectionDeleted
	}
	memberships, err := readInvitationMemberships(ctx, tx, userID, ids, true)
	if err != nil {
		return nil, err
	}
	changed := make([]int64, 0, len(ids))
	joined := false
	for _, membership := range memberships {
		if membership.CollectionID == collectionID && !membership.Deleted && membership.Status == ente.CollectionAccepted {
			joined = true
		}
		parent := collections[membership.CollectionID]
		if collection.App == ente.Photos && !parent.Deleted && parent.OwnerActive && parent.App == ente.Photos && !membership.Deleted &&
			membership.Status == ente.CollectionPending && membership.InviterID.Valid && membership.InviterID.Int64 == ownerID {
			changed = append(changed, membership.CollectionID)
		}
	}
	if !joined {
		if _, err := tx.ExecContext(ctx, `INSERT INTO collection_shares
			(collection_id, from_user_id, to_user_id, encrypted_key, role_type, shared_at, updation_time, acceptance_status)
			VALUES ($1, $2, $3, $4, $5, $6, $6, 'accepted')
			ON CONFLICT (collection_id, from_user_id, to_user_id) DO UPDATE SET
				is_deleted = FALSE, acceptance_status = 'accepted', invited_by_user_id = NULL,
				encrypted_key = EXCLUDED.encrypted_key, role_type = EXCLUDED.role_type,
				shared_at = EXCLUDED.shared_at, updation_time = EXCLUDED.updation_time`,
			collectionID, ownerID, userID, encryptedKey, role, updationTime); err != nil {
			return nil, err
		}
		if !containsInvitationID(changed, collectionID) {
			changed = append(changed, collectionID)
		}
	} else if role == ente.COLLABORATOR {
		result, err := tx.ExecContext(ctx, `UPDATE collection_shares SET role_type = 'COLLABORATOR'
			WHERE collection_id = $1 AND to_user_id = $2 AND role_type = 'VIEWER'`, collectionID, userID)
		if err != nil {
			return nil, err
		}
		updated, err := result.RowsAffected()
		if err != nil {
			return nil, err
		}
		if updated > 0 {
			changed = append(changed, collectionID)
		}
	}
	if err := acceptInvitationRows(ctx, tx, userID, changed, updationTime); err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	if !containsInvitationID(changed, collectionID) {
		changed = append(changed, collectionID)
	}
	sort.Slice(changed, func(i, j int) bool { return changed[i] < changed[j] })
	return changed, nil
}

func (repo *CollectionRepository) writeDirectShares(ctx context.Context, collectionID, ownerID int64,
	shares []CollectionShareItem, updationTime int64, automatic bool, options []ShareAcceptanceOptions) ([]ente.CollectionShareStatus, error) {
	option := ShareAcceptanceOptions{InviterUserID: ownerID}
	if len(options) > 0 {
		option = options[0]
	}
	if option.InviterUserID <= 0 || len(shares) == 0 {
		return nil, ente.ErrBadRequest
	}
	userIDs := []int64{option.InviterUserID, ownerID}
	for _, share := range shares {
		if !validShareRole(share.Role) {
			return nil, ente.ErrBadRequest
		}
		userIDs = append(userIDs, share.ToUserID)
	}
	tx, err := repo.DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	if err := lockActiveShareUsers(ctx, tx, userIDs); err != nil {
		return nil, err
	}
	collections, err := lockInvitationCollections(ctx, tx, []int64{collectionID})
	if err != nil {
		return nil, err
	}
	collection, found := collections[collectionID]
	if !found || collection.Deleted || collection.OwnerID != ownerID {
		return nil, ente.ErrCollectionDeleted
	}
	if option.InviterUserID != ownerID {
		var admin bool
		err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM collection_shares
			WHERE collection_id = $1 AND to_user_id = $2 AND is_deleted = FALSE
				AND acceptance_status = 'accepted' AND role_type = 'ADMIN')`, collectionID, option.InviterUserID).Scan(&admin)
		if err != nil {
			return nil, err
		}
		if !admin {
			return nil, ente.ErrPermissionDenied
		}
	}
	result := make([]ente.CollectionShareStatus, 0, len(shares))
	changedRecipients := make([]int64, 0, len(shares))
	for _, share := range shares {
		status := ente.CollectionAccepted
		var inviterID *int64
		if option.Enabled && collection.App == ente.Photos {
			inviterID = &option.InviterUserID
			trusted, err := trustedCollectionInviter(ctx, tx, share.ToUserID, option.InviterUserID)
			if err != nil {
				return nil, err
			}
			if !trusted {
				status = ente.CollectionPending
			}
		}
		conflict := `DO UPDATE SET is_deleted = FALSE, role_type = EXCLUDED.role_type,
			updation_time = EXCLUDED.updation_time,
			shared_at = CASE WHEN collection_shares.is_deleted THEN EXCLUDED.shared_at ELSE collection_shares.shared_at END,
			acceptance_status = CASE WHEN collection_shares.is_deleted THEN EXCLUDED.acceptance_status ELSE collection_shares.acceptance_status END,
			invited_by_user_id = CASE WHEN collection_shares.is_deleted THEN EXCLUDED.invited_by_user_id ELSE collection_shares.invited_by_user_id END`
		if automatic {
			conflict = "DO NOTHING"
		}
		res, err := tx.ExecContext(ctx, `INSERT INTO collection_shares
			(collection_id, from_user_id, to_user_id, encrypted_key, role_type, shared_at, updation_time, acceptance_status, invited_by_user_id)
			VALUES ($1, $2, $3, $4, $5, $6, $6, $7, $8)
			ON CONFLICT (collection_id, from_user_id, to_user_id) `+conflict,
			collectionID, ownerID, share.ToUserID, share.EncryptedKey, share.Role, updationTime, status, inviterID)
		if err != nil {
			return nil, err
		}
		count, err := res.RowsAffected()
		if err != nil {
			return nil, err
		}
		shareStatus := ente.CollectionShared
		if count == 0 {
			var deleted bool
			if err := tx.QueryRowContext(ctx, `SELECT is_deleted FROM collection_shares
				WHERE collection_id = $1 AND to_user_id = $2`, collectionID, share.ToUserID).Scan(&deleted); err != nil {
				return nil, err
			}
			shareStatus = ente.CollectionAlreadyShared
			if deleted {
				shareStatus = ente.CollectionBlockedPriorRemoval
			}
		} else {
			changedRecipients = append(changedRecipients, share.ToUserID)
		}
		result = append(result, shareStatus)
	}
	if len(changedRecipients) > 0 {
		if err := touchInvitationCollections(ctx, tx, []int64{collectionID}, updationTime); err != nil {
			return nil, err
		}
		if _, err := tx.ExecContext(ctx, `UPDATE collection_shares cs SET updation_time = c.updation_time
			FROM collections c WHERE cs.collection_id = c.collection_id
				AND cs.collection_id = $1 AND cs.to_user_id = ANY($2)`, collectionID, pq.Array(changedRecipients)); err != nil {
			return nil, err
		}
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return result, nil
}

func trustedCollectionInviter(ctx context.Context, tx *sql.Tx, recipientID, inviterID int64) (bool, error) {
	var trusted bool
	err := tx.QueryRowContext(ctx, `SELECT
		EXISTS (SELECT 1 FROM users recipient JOIN users inviter
			ON recipient.family_admin_id = inviter.family_admin_id
			WHERE recipient.user_id = $1 AND inviter.user_id = $2 AND recipient.family_admin_id IS NOT NULL)
		OR EXISTS (SELECT 1 FROM collection_shares cs JOIN collections c ON c.collection_id = cs.collection_id
			WHERE cs.to_user_id = $1 AND COALESCE(cs.invited_by_user_id, cs.from_user_id) = $2
				AND cs.is_deleted = FALSE AND cs.acceptance_status = 'accepted'
				AND c.is_deleted = FALSE AND c.app = 'photos')`, recipientID, inviterID).Scan(&trusted)
	return trusted, err
}

func lockActiveShareUsers(ctx context.Context, tx *sql.Tx, ids []int64) error {
	rows, err := tx.QueryContext(ctx, `SELECT user_id, encrypted_email IS NOT NULL FROM users
		WHERE user_id = ANY($1) ORDER BY user_id FOR NO KEY UPDATE`, pq.Array(ids))
	if err != nil {
		return err
	}
	defer rows.Close()
	found := make(map[int64]bool)
	for rows.Next() {
		var id int64
		var active bool
		if err := rows.Scan(&id, &active); err != nil {
			return err
		}
		if !active {
			return ente.ErrPermissionDenied
		}
		found[id] = true
	}
	if err := rows.Err(); err != nil {
		return err
	}
	for _, id := range ids {
		if !found[id] {
			return ente.ErrPermissionDenied
		}
	}
	return nil
}

func lockInvitationCollections(ctx context.Context, tx *sql.Tx, ids []int64) (map[int64]invitationCollection, error) {
	rows, err := tx.QueryContext(ctx, `SELECT c.collection_id, c.owner_id, c.app, c.is_deleted, c.updation_time,
		EXISTS (SELECT 1 FROM users WHERE user_id = c.owner_id AND encrypted_email IS NOT NULL)
		FROM collections c WHERE c.collection_id = ANY($1) ORDER BY c.collection_id FOR UPDATE`, pq.Array(ids))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := make(map[int64]invitationCollection)
	for rows.Next() {
		var collection invitationCollection
		if err := rows.Scan(&collection.ID, &collection.OwnerID, &collection.App, &collection.Deleted, &collection.UpdationTime, &collection.OwnerActive); err != nil {
			return nil, err
		}
		result[collection.ID] = collection
	}
	return result, rows.Err()
}

func readInvitationMemberships(ctx context.Context, tx *sql.Tx, userID int64, ids []int64, lock bool) ([]invitationMembership, error) {
	query := `SELECT collection_id, invited_by_user_id, acceptance_status, is_deleted
		FROM collection_shares WHERE to_user_id = $1 AND collection_id = ANY($2) ORDER BY collection_id`
	if lock {
		query += " FOR UPDATE"
	}
	rows, err := tx.QueryContext(ctx, query, userID, pq.Array(ids))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := make([]invitationMembership, 0, len(ids))
	for rows.Next() {
		var membership invitationMembership
		if err := rows.Scan(&membership.CollectionID, &membership.InviterID, &membership.Status, &membership.Deleted); err != nil {
			return nil, err
		}
		result = append(result, membership)
	}
	return result, rows.Err()
}

func touchInvitationCollections(ctx context.Context, tx *sql.Tx, ids []int64, updationTime int64) error {
	_, err := tx.ExecContext(ctx, `UPDATE collections SET updation_time = GREATEST(updation_time + 1, $1)
		WHERE collection_id = ANY($2)`, updationTime, pq.Array(ids))
	return err
}

func acceptInvitationRows(ctx context.Context, tx *sql.Tx, userID int64, ids []int64, updationTime int64) error {
	if len(ids) == 0 {
		return nil
	}
	if err := touchInvitationCollections(ctx, tx, ids, updationTime); err != nil {
		return err
	}
	_, err := tx.ExecContext(ctx, `UPDATE collection_shares cs SET acceptance_status = 'accepted', updation_time = c.updation_time
		FROM collections c WHERE cs.collection_id = c.collection_id AND cs.collection_id = ANY($1) AND cs.to_user_id = $2`, pq.Array(ids), userID)
	return err
}

func invitationIDs(ids []int64) ([]int64, error) {
	if len(ids) == 0 {
		return nil, ente.ErrBadRequest
	}
	result := append([]int64(nil), ids...)
	sort.Slice(result, func(i, j int) bool { return result[i] < result[j] })
	for index, id := range result {
		if id <= 0 || (index > 0 && result[index-1] == id) {
			return nil, ente.ErrBadRequest
		}
	}
	return result, nil
}

func containsInvitationID(ids []int64, target int64) bool {
	for _, id := range ids {
		if id == target {
			return true
		}
	}
	return false
}

func validShareRole(role ente.CollectionParticipantRole) bool {
	return role == ente.VIEWER || role == ente.COLLABORATOR || role == ente.ADMIN
}
