package contact

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"slices"
	"time"

	"github.com/ente/museum/ente"
	contactmodel "github.com/ente/museum/ente/contact"
	"github.com/ente/museum/pkg/utils/crypto"
	"github.com/ente/stacktrace"
	"github.com/lib/pq"
)

func (r *Repository) CanCreateContact(ctx context.Context, actorUserID int64, contactUserID int64) (bool, error) {
	eligible, err := r.hasActiveEmergencyRelationship(ctx, actorUserID, contactUserID)
	if err != nil {
		return false, stacktrace.Propagate(err, "failed to check emergency relationship")
	}
	if eligible {
		return true, nil
	}

	eligible, err = r.hasSharedActiveFamily(ctx, actorUserID, contactUserID)
	if err != nil {
		return false, stacktrace.Propagate(err, "failed to check family relationship")
	}
	if eligible {
		return true, nil
	}

	eligible, err = r.hasCommonSharedCollection(ctx, actorUserID, contactUserID)
	if err != nil {
		return false, stacktrace.Propagate(err, "failed to check shared collections")
	}
	return eligible, nil
}

func (r *Repository) Create(ctx context.Context, userID int64, req contactmodel.CreateRequest) (string, error) {
	id := contactmodel.NewContactID()
	err := r.DB.QueryRowContext(
		ctx,
		`INSERT INTO contact_entity(id, user_id, contact_user_id, encrypted_key, encrypted_data)
		 VALUES($1, $2, $3, $4, $5)
		 RETURNING id`,
		id,
		userID,
		req.ContactUserID,
		req.EncryptedKey,
		req.EncryptedData,
	).Scan(&id)
	if err != nil {
		var pqErr *pq.Error
		if errors.As(err, &pqErr) && pqErr.Code == "23505" {
			return "", stacktrace.Propagate(
				ente.NewBadRequestWithMessage("contact already exists for contactUserID"),
				"",
			)
		}
		return "", stacktrace.Propagate(err, "failed to create contact")
	}
	return id, nil
}

func (r *Repository) ContactUserExists(ctx context.Context, contactUserID int64) (bool, error) {
	var exists bool
	err := r.DB.QueryRowContext(
		ctx,
		`SELECT EXISTS(
			SELECT 1
			  FROM users
			 WHERE user_id = $1
			   AND encrypted_email IS NOT NULL
		)`,
		contactUserID,
	).Scan(&exists)
	if err != nil {
		return false, stacktrace.Propagate(err, "failed to check contact user existence")
	}
	return exists, nil
}

func (r *Repository) hasActiveEmergencyRelationship(ctx context.Context, actorUserID int64, contactUserID int64) (bool, error) {
	var exists bool
	err := r.DB.QueryRowContext(
		ctx,
		`SELECT EXISTS(
			SELECT 1
			FROM emergency_contact
			WHERE state = ANY($3)
			  AND (
					(user_id = $1 AND emergency_contact_id = $2)
				 OR (user_id = $2 AND emergency_contact_id = $1)
			  )
		)`,
		actorUserID,
		contactUserID,
		pq.Array([]ente.ContactState{ente.UserInvitedContact, ente.ContactAccepted}),
	).Scan(&exists)
	if err != nil {
		return false, err
	}
	return exists, nil
}

func (r *Repository) hasSharedActiveFamily(ctx context.Context, actorUserID int64, contactUserID int64) (bool, error) {
	var exists bool
	err := r.DB.QueryRowContext(
		ctx,
		`SELECT EXISTS(
			SELECT 1
			FROM users actor
			JOIN users contact ON actor.family_admin_id = contact.family_admin_id
			WHERE actor.user_id = $1
			  AND contact.user_id = $2
			  AND actor.family_admin_id IS NOT NULL
		)`,
		actorUserID,
		contactUserID,
	).Scan(&exists)
	if err != nil {
		return false, err
	}
	return exists, nil
}

func (r *Repository) hasCommonSharedCollection(ctx context.Context, actorUserID int64, contactUserID int64) (bool, error) {
	var exists bool
	err := r.DB.QueryRowContext(
		ctx,
		`WITH shared_access AS (
			SELECT collection_id
			FROM collection_shares
			WHERE collection_shares.is_deleted = FALSE
			  AND (collection_shares.to_user_id = $1 OR collection_shares.from_user_id = $1)
		), contact_shared_access AS (
			SELECT collection_id
			FROM collection_shares
			WHERE collection_shares.is_deleted = FALSE
			  AND (collection_shares.to_user_id = $2 OR collection_shares.from_user_id = $2)
		)
		SELECT EXISTS(
			SELECT 1
			FROM shared_access actor
			INNER JOIN contact_shared_access contact
				ON actor.collection_id = contact.collection_id
		)`,
		actorUserID,
		contactUserID,
	).Scan(&exists)
	if err != nil {
		return false, err
	}
	return exists, nil
}

func (r *Repository) Get(ctx context.Context, userID int64, id string) (*contactmodel.Entity, error) {
	row := r.DB.QueryRowContext(
		ctx,
		`SELECT c.id, c.user_id, c.contact_user_id, c.profile_picture_attachment_id, c.encrypted_key, c.encrypted_data,
		        c.is_deleted, c.created_at, c.updated_at, u.encrypted_email, u.email_decryption_nonce
		   FROM contact_entity c
		   LEFT JOIN users u
		     ON u.user_id = c.contact_user_id
		  WHERE c.id = $1 AND c.user_id = $2`,
		id,
		userID,
	)
	entity, err := r.scanEntityWithEmail(row)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, &ente.ErrNotFoundError
		}
		return nil, stacktrace.Propagate(err, "failed to get contact")
	}
	return entity, nil
}

type ContactUpdateState struct {
	ContactUserID int64
	IsDeleted     bool
}

func (r *Repository) GetContactUpdateState(ctx context.Context, userID int64, id string) (ContactUpdateState, error) {
	var state ContactUpdateState
	err := r.DB.QueryRowContext(
		ctx,
		`SELECT contact_user_id, is_deleted
		   FROM contact_entity
		  WHERE id = $1 AND user_id = $2`,
		id,
		userID,
	).Scan(&state.ContactUserID, &state.IsDeleted)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return ContactUpdateState{}, &ente.ErrNotFoundError
		}
		return ContactUpdateState{}, stacktrace.Propagate(err, "failed to get contact update state")
	}
	return state, nil
}

func (r *Repository) Update(ctx context.Context, userID int64, id string, req contactmodel.UpdateRequest) error {
	result, err := r.DB.ExecContext(
		ctx,
		`UPDATE contact_entity
		    SET contact_user_id = $1,
		        encrypted_data = $2,
		        is_deleted = FALSE
		  WHERE id = $3 AND user_id = $4`,
		req.ContactUserID,
		req.EncryptedData,
		id,
		userID,
	)
	if err != nil {
		var pqErr *pq.Error
		if errors.As(err, &pqErr) && pqErr.Code == "23505" {
			return stacktrace.Propagate(
				ente.NewBadRequestWithMessage("contact already exists for contactUserID"),
				"",
			)
		}
		return stacktrace.Propagate(err, "failed to update contact")
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if rowsAffected == 1 {
		return nil
	}
	if _, getErr := r.Get(ctx, userID, id); getErr != nil {
		return stacktrace.Propagate(getErr, "failed to fetch contact after update miss")
	}
	return stacktrace.NewError("exactly one row should be updated")
}

func (r *Repository) Delete(ctx context.Context, userID int64, id string) error {
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()

	entity, err := r.getForUpdate(ctx, tx, userID, id)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if entity.IsDeleted {
		return tx.Commit()
	}

	if entity.ProfilePictureAttachmentID != nil {
		if err := markAttachmentDeletedTx(ctx, tx, userID, contactmodel.ProfilePicture, *entity.ProfilePictureAttachmentID); err != nil {
			return stacktrace.Propagate(err, "")
		}
	}
	if _, err := tx.ExecContext(
		ctx,
		`UPDATE contact_entity
		    SET is_deleted = TRUE,
		        encrypted_data = NULL,
		        profile_picture_attachment_id = NULL
		  WHERE id = $1 AND user_id = $2`,
		id,
		userID,
	); err != nil {
		return stacktrace.Propagate(err, "failed to delete contact")
	}
	return stacktrace.Propagate(tx.Commit(), "")
}

func (r *Repository) GetDiff(ctx context.Context, userID int64, sinceTime int64, limit int16) ([]contactmodel.Entity, error) {
	rows, err := r.DB.QueryContext(
		ctx,
		`SELECT c.id, c.user_id, c.contact_user_id, c.profile_picture_attachment_id, c.encrypted_key, c.encrypted_data,
		        c.is_deleted, c.created_at, c.updated_at, u.encrypted_email, u.email_decryption_nonce
		   FROM contact_entity c
		   LEFT JOIN users u
		     ON u.user_id = c.contact_user_id
		  WHERE c.user_id = $1 AND c.updated_at > $2
		  ORDER BY c.updated_at
		  LIMIT $3`,
		userID,
		sinceTime,
		limit,
	)
	if err != nil {
		return nil, stacktrace.Propagate(err, "contact diff query failed")
	}
	defer rows.Close()

	entities := make([]contactmodel.Entity, 0)
	for rows.Next() {
		entity, scanErr := r.scanEntityWithEmail(rows)
		if scanErr != nil {
			return nil, stacktrace.Propagate(scanErr, "failed to scan contact diff row")
		}
		entities = append(entities, *entity)
	}
	return entities, nil
}

func (r *Repository) TouchContactsForContactUser(ctx context.Context, contactUserID int64) error {
	_, err := r.DB.ExecContext(
		ctx,
		`UPDATE contact_entity
		    SET contact_user_id = contact_user_id
		  WHERE contact_user_id = $1
		    AND is_deleted = FALSE`,
		contactUserID,
	)
	return stacktrace.Propagate(err, "failed to touch contacts for contact user")
}

func (r *Repository) AttachContactAttachment(
	ctx context.Context,
	userID int64,
	contactID string,
	attachmentType contactmodel.AttachmentType,
	attachmentID string,
	size int64,
) (*contactmodel.Entity, error) {
	policy, err := attachmentType.Policy()
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()

	entity, err := r.getForUpdate(ctx, tx, userID, contactID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	if entity.IsDeleted {
		return nil, stacktrace.Propagate(ente.NewBadRequestWithMessage("contact is already deleted"), "")
	}

	objectKey := contactmodel.AttachmentObjectKey(userID, attachmentType, attachmentID)
	var latestBucket string
	if err := tx.QueryRowContext(
		ctx,
		`SELECT bucket_id FROM temp_objects WHERE object_key = $1 FOR UPDATE`,
		objectKey,
	).Scan(&latestBucket); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, stacktrace.Propagate(ente.NewBadRequestWithMessage("staged attachment upload not found"), "")
		}
		return nil, stacktrace.Propagate(err, "failed to fetch staged attachment")
	}

	if _, err := tx.ExecContext(
		ctx,
		`INSERT INTO user_attachments(attachment_id, user_id, attachment_type, size, latest_bucket)
		 VALUES($1, $2, $3, $4, $5)`,
		attachmentID,
		userID,
		string(attachmentType),
		size,
		latestBucket,
	); err != nil {
		var pqErr *pq.Error
		if errors.As(err, &pqErr) && pqErr.Code == "23505" {
			return nil, stacktrace.Propagate(ente.NewBadRequestWithMessage("attachmentID already exists"), "")
		}
		return nil, stacktrace.Propagate(err, "failed to insert attachment row")
	}

	currentAttachmentID := attachmentIDForPolicy(entity, policy)
	if currentAttachmentID != nil && *currentAttachmentID != "" {
		if err := markAttachmentDeletedTx(ctx, tx, userID, attachmentType, *currentAttachmentID); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
	}

	updateSlotQuery := fmt.Sprintf(
		`UPDATE contact_entity
		    SET %s = $1
		  WHERE id = $2 AND user_id = $3 AND is_deleted = FALSE`,
		policy.SlotColumn,
	)
	if _, err := tx.ExecContext(
		ctx,
		updateSlotQuery,
		attachmentID,
		contactID,
		userID,
	); err != nil {
		return nil, stacktrace.Propagate(err, "failed to update contact attachment")
	}

	if err := r.ObjectCleanupRepo.RemoveTempObjectFromDC(ctx, tx, objectKey, latestBucket); err != nil {
		return nil, stacktrace.Propagate(err, "failed to remove attachment from temp_objects")
	}

	if err := tx.Commit(); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return r.Get(ctx, userID, contactID)
}

func (r *Repository) DeleteContactAttachment(
	ctx context.Context,
	userID int64,
	contactID string,
	attachmentType contactmodel.AttachmentType,
) (*contactmodel.Entity, error) {
	policy, err := attachmentType.Policy()
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()

	entity, err := r.getForUpdate(ctx, tx, userID, contactID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	if entity.IsDeleted {
		return nil, stacktrace.Propagate(ente.NewBadRequestWithMessage("contact is already deleted"), "")
	}
	currentAttachmentID := attachmentIDForPolicy(entity, policy)
	if currentAttachmentID != nil {
		if err := markAttachmentDeletedTx(ctx, tx, userID, attachmentType, *currentAttachmentID); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		clearSlotQuery := fmt.Sprintf(
			`UPDATE contact_entity
			    SET %s = NULL
			  WHERE id = $1 AND user_id = $2 AND is_deleted = FALSE`,
			policy.SlotColumn,
		)
		if _, err := tx.ExecContext(
			ctx,
			clearSlotQuery,
			contactID,
			userID,
		); err != nil {
			return nil, stacktrace.Propagate(err, "failed to clear contact attachment")
		}
	}
	if err := tx.Commit(); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return r.Get(ctx, userID, contactID)
}

func (r *Repository) GetAttachment(ctx context.Context, userID int64, attachmentID string) (*contactmodel.Attachment, error) {
	row := r.DB.QueryRowContext(
		ctx,
		`SELECT attachment_id, user_id, attachment_type, size, latest_bucket, replicated_buckets,
		        delete_from_buckets, inflight_rep_buckets, pending_sync, is_deleted, sync_locked_till,
		        created_at, updated_at
		   FROM user_attachments
		  WHERE attachment_id = $1 AND user_id = $2`,
		attachmentID,
		userID,
	)
	attachment, err := scanAttachment(row)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, &ente.ErrNotFoundError
		}
		return nil, stacktrace.Propagate(err, "failed to get attachment")
	}
	return attachment, nil
}

func (r *Repository) GetStagedAttachmentBucket(
	ctx context.Context,
	userID int64,
	attachmentType contactmodel.AttachmentType,
	attachmentID string,
) (string, error) {
	objectKey := contactmodel.AttachmentObjectKey(userID, attachmentType, attachmentID)
	var bucketID string
	err := r.DB.QueryRowContext(
		ctx,
		`SELECT bucket_id
		   FROM temp_objects
		  WHERE object_key = $1`,
		objectKey,
	).Scan(&bucketID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "", &ente.ErrNotFoundError
		}
		return "", stacktrace.Propagate(err, "failed to fetch staged attachment bucket")
	}
	return bucketID, nil
}

func (r *Repository) AddBucket(row contactmodel.Attachment, bucketID string, columnName string) error {
	query := fmt.Sprintf(`
		UPDATE user_attachments
		SET %s = array(
			SELECT DISTINCT elem FROM unnest(
				array_append(user_attachments.%s, $1)
			) AS elem
			WHERE elem IS NOT NULL
		)
		WHERE attachment_id = $2 AND user_id = $3 AND attachment_type = $4`, columnName, columnName)
	result, err := r.DB.Exec(query, bucketID, row.AttachmentID, row.UserID, string(row.AttachmentType))
	if err != nil {
		return stacktrace.Propagate(err, "failed to add bucket to %s", columnName)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if rowsAffected == 0 {
		return stacktrace.NewError("bucket not added to %s", columnName)
	}
	return nil
}

func (r *Repository) RemoveBucket(row contactmodel.Attachment, bucketID string, columnName string) error {
	query := fmt.Sprintf(`
		UPDATE user_attachments
		SET %s = array(
			SELECT DISTINCT elem FROM unnest(
				array_remove(user_attachments.%s, $1)
			) AS elem
			WHERE elem IS NOT NULL
		)
		WHERE attachment_id = $2 AND user_id = $3 AND attachment_type = $4`, columnName, columnName)
	result, err := r.DB.Exec(query, bucketID, row.AttachmentID, row.UserID, string(row.AttachmentType))
	if err != nil {
		return stacktrace.Propagate(err, "failed to remove bucket from %s", columnName)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if rowsAffected == 0 {
		return stacktrace.NewError("bucket not removed from %s", columnName)
	}
	return nil
}

func (r *Repository) MoveBetweenBuckets(row contactmodel.Attachment, bucketID string, sourceColumn string, destColumn string) error {
	query := fmt.Sprintf(`
		UPDATE user_attachments
		SET %s = array(
			SELECT DISTINCT elem FROM unnest(
				array_append(user_attachments.%s, $1)
			) AS elem
			WHERE elem IS NOT NULL
		),
		%s = array(
			SELECT DISTINCT elem FROM unnest(
				array_remove(user_attachments.%s, $1)
			) AS elem
			WHERE elem IS NOT NULL
		)
		WHERE attachment_id = $2 AND user_id = $3 AND attachment_type = $4`, destColumn, destColumn, sourceColumn, sourceColumn)
	result, err := r.DB.Exec(query, bucketID, row.AttachmentID, row.UserID, string(row.AttachmentType))
	if err != nil {
		return stacktrace.Propagate(err, "failed to move bucket from %s to %s", sourceColumn, destColumn)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if rowsAffected == 0 {
		return stacktrace.NewError("bucket not moved from %s to %s", sourceColumn, destColumn)
	}
	return nil
}

func (r *Repository) GetPendingSyncAttachmentAndExtendLock(
	ctx context.Context,
	newSyncLockTime int64,
	forDeletion bool,
) (*contactmodel.Attachment, error) {
	if newSyncLockTime < time.Now().Add(5*time.Minute).UnixMicro() {
		return nil, stacktrace.NewError("newSyncLockTime should be at least 5min in the future")
	}
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()

	row := tx.QueryRowContext(
		ctx,
		`SELECT attachment_id, user_id, attachment_type, size, latest_bucket, replicated_buckets,
		        delete_from_buckets, inflight_rep_buckets, pending_sync, is_deleted, sync_locked_till,
		        created_at, updated_at
		   FROM user_attachments
		  WHERE pending_sync = TRUE
		    AND is_deleted = $1
		    AND sync_locked_till < now_utc_micro_seconds()
		  LIMIT 1
		  FOR UPDATE SKIP LOCKED`,
		forDeletion,
	)
	attachment, err := scanAttachment(row)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	if attachment.SyncLockedTill > newSyncLockTime {
		return nil, stacktrace.NewError(
			"newSyncLockTime (%d) is less than existing SyncLockedTill(%d)",
			newSyncLockTime,
			attachment.SyncLockedTill,
		)
	}
	if _, err := tx.ExecContext(
		ctx,
		`UPDATE user_attachments
		    SET sync_locked_till = $1
		  WHERE attachment_id = $2 AND user_id = $3 AND attachment_type = $4`,
		newSyncLockTime,
		attachment.AttachmentID,
		attachment.UserID,
		string(attachment.AttachmentType),
	); err != nil {
		return nil, stacktrace.Propagate(err, "failed to extend attachment sync lock")
	}
	if err := tx.Commit(); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return attachment, nil
}

func (r *Repository) MarkAttachmentReplicationAsDone(ctx context.Context, row contactmodel.Attachment) error {
	_, err := r.DB.ExecContext(
		ctx,
		`UPDATE user_attachments
		    SET pending_sync = FALSE
		  WHERE is_deleted = FALSE
		    AND attachment_id = $1
		    AND user_id = $2
		    AND attachment_type = $3`,
		row.AttachmentID,
		row.UserID,
		string(row.AttachmentType),
	)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	return nil
}

func (r *Repository) RegisterReplicationAttempt(ctx context.Context, row contactmodel.Attachment, dstBucketID string) error {
	if slices.Contains(row.DeleteFromBuckets, dstBucketID) {
		return r.MoveBetweenBuckets(row, dstBucketID, DeletionColumn, InflightRepColumn)
	}
	if !slices.Contains(row.InflightRepBuckets, dstBucketID) {
		return r.AddBucket(row, dstBucketID, InflightRepColumn)
	}
	return nil
}

func (r *Repository) ResetAttachmentSyncLock(ctx context.Context, row contactmodel.Attachment, syncLockedTill int64) error {
	_, err := r.DB.ExecContext(
		ctx,
		`UPDATE user_attachments
		    SET sync_locked_till = now_utc_micro_seconds()
		  WHERE pending_sync = FALSE
		    AND attachment_id = $1
		    AND user_id = $2
		    AND attachment_type = $3
		    AND sync_locked_till = $4`,
		row.AttachmentID,
		row.UserID,
		string(row.AttachmentType),
		syncLockedTill,
	)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	return nil
}

func (r *Repository) DeleteAttachment(ctx context.Context, row contactmodel.Attachment) error {
	res, err := r.DB.ExecContext(
		ctx,
		`DELETE FROM user_attachments
		  WHERE attachment_id = $1
		    AND attachment_type = $2
		    AND latest_bucket = $3
		    AND user_id = $4
		    AND replicated_buckets = ARRAY[]::s3region[]
		    AND delete_from_buckets = ARRAY[]::s3region[]
		    AND inflight_rep_buckets = ARRAY[]::s3region[]
		    AND is_deleted = TRUE`,
		row.AttachmentID,
		string(row.AttachmentType),
		row.LatestBucket,
		row.UserID,
	)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	rowsAffected, err := res.RowsAffected()
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if rowsAffected == 0 {
		return stacktrace.NewError("attachment not deleted")
	}
	return nil
}

func (r *Repository) getForUpdate(ctx context.Context, tx *sql.Tx, userID int64, id string) (*contactmodel.Entity, error) {
	row := tx.QueryRowContext(
		ctx,
		`SELECT id, user_id, contact_user_id, profile_picture_attachment_id, encrypted_key, encrypted_data,
		        is_deleted, created_at, updated_at
		   FROM contact_entity
		  WHERE id = $1 AND user_id = $2
		  FOR UPDATE`,
		id,
		userID,
	)
	entity, err := scanEntity(row)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, &ente.ErrNotFoundError
		}
		return nil, stacktrace.Propagate(err, "failed to lock contact row")
	}
	return entity, nil
}

func markAttachmentDeletedTx(ctx context.Context, tx *sql.Tx, userID int64, attachmentType contactmodel.AttachmentType, attachmentID string) error {
	_, err := tx.ExecContext(
		ctx,
		`UPDATE user_attachments
		    SET is_deleted = TRUE,
		        pending_sync = TRUE,
		        sync_locked_till = 0,
		        delete_from_buckets = array(
		            SELECT DISTINCT elem
		              FROM unnest(array_cat(array_cat(replicated_buckets, delete_from_buckets), inflight_rep_buckets)) AS elem
		             WHERE elem IS NOT NULL
		        ),
		        replicated_buckets = ARRAY[]::s3region[],
		        inflight_rep_buckets = ARRAY[]::s3region[]
		  WHERE attachment_id = $1
		    AND user_id = $2
		    AND attachment_type = $3
		    AND is_deleted = FALSE`,
		attachmentID,
		userID,
		string(attachmentType),
	)
	return stacktrace.Propagate(err, "failed to mark attachment deleted")
}

func attachmentIDForPolicy(entity *contactmodel.Entity, policy contactmodel.AttachmentPolicy) *string {
	switch policy.Type {
	case contactmodel.ProfilePicture:
		return entity.ProfilePictureAttachmentID
	default:
		return nil
	}
}

type rowScanner interface {
	Scan(dest ...interface{}) error
}

func scanEntity(scanner rowScanner) (*contactmodel.Entity, error) {
	var (
		entity        contactmodel.Entity
		pictureID     sql.NullString
		encryptedKey  []byte
		encryptedData []byte
	)
	if err := scanner.Scan(
		&entity.ID,
		&entity.UserID,
		&entity.ContactUserID,
		&pictureID,
		&encryptedKey,
		&encryptedData,
		&entity.IsDeleted,
		&entity.CreatedAt,
		&entity.UpdatedAt,
	); err != nil {
		return nil, err
	}
	if pictureID.Valid {
		entity.ProfilePictureAttachmentID = &pictureID.String
	}
	if entity.IsDeleted {
		entity.ProfilePictureAttachmentID = nil
		entity.EncryptedKey = nil
		entity.EncryptedData = nil
		return &entity, nil
	}
	entity.EncryptedKey = &encryptedKey
	entity.EncryptedData = &encryptedData
	return &entity, nil
}

func (r *Repository) scanEntityWithEmail(scanner rowScanner) (*contactmodel.Entity, error) {
	entity, encryptedEmail, nonce, err := scanEntityWithEncryptedEmail(scanner)
	if err != nil {
		return nil, err
	}
	if entity.IsDeleted || encryptedEmail == nil || nonce == nil {
		entity.Email = nil
		return entity, nil
	}
	email, err := crypto.Decrypt(*encryptedEmail, r.SecretEncryptionKey, *nonce)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to decrypt contact email")
	}
	entity.Email = &email
	return entity, nil
}

func scanEntityWithEncryptedEmail(scanner rowScanner) (*contactmodel.Entity, *[]byte, *[]byte, error) {
	var (
		entity            contactmodel.Entity
		pictureID         sql.NullString
		encryptedKey      []byte
		encryptedData     []byte
		contactEmail      []byte
		contactEmailNonce []byte
	)
	if err := scanner.Scan(
		&entity.ID,
		&entity.UserID,
		&entity.ContactUserID,
		&pictureID,
		&encryptedKey,
		&encryptedData,
		&entity.IsDeleted,
		&entity.CreatedAt,
		&entity.UpdatedAt,
		&contactEmail,
		&contactEmailNonce,
	); err != nil {
		return nil, nil, nil, err
	}
	if pictureID.Valid {
		entity.ProfilePictureAttachmentID = &pictureID.String
	}
	if entity.IsDeleted {
		entity.ProfilePictureAttachmentID = nil
		entity.EncryptedKey = nil
		entity.EncryptedData = nil
		return &entity, nil, nil, nil
	}
	entity.EncryptedKey = &encryptedKey
	entity.EncryptedData = &encryptedData
	var emailPtr *[]byte
	var noncePtr *[]byte
	if len(contactEmail) > 0 && len(contactEmailNonce) > 0 {
		emailPtr = &contactEmail
		noncePtr = &contactEmailNonce
	}
	return &entity, emailPtr, noncePtr, nil
}

func scanAttachment(scanner rowScanner) (*contactmodel.Attachment, error) {
	var attachment contactmodel.Attachment
	if err := scanner.Scan(
		&attachment.AttachmentID,
		&attachment.UserID,
		&attachment.AttachmentType,
		&attachment.Size,
		&attachment.LatestBucket,
		pq.Array(&attachment.ReplicatedBuckets),
		pq.Array(&attachment.DeleteFromBuckets),
		pq.Array(&attachment.InflightRepBuckets),
		&attachment.PendingSync,
		&attachment.IsDeleted,
		&attachment.SyncLockedTill,
		&attachment.CreatedAt,
		&attachment.UpdatedAt,
	); err != nil {
		return nil, err
	}
	return &attachment, nil
}
