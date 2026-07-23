package datacleanup

import (
	"context"
	"database/sql"
	"fmt"
	entity "github.com/ente/museum/ente/data_cleanup"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
)

// Repository wraps out interaction related to data_cleanup database table
type Repository struct {
	DB *sql.DB
}

func (r *Repository) Insert(ctx context.Context, userID int64) error {
	_, err := r.DB.ExecContext(ctx, `INSERT INTO data_cleanup(user_id) VALUES ($1)`, userID)
	return stacktrace.Propagate(err, "failed to insert")
}

func (r *Repository) HasScheduledDelete(ctx context.Context, userID int64) (bool, error) {
	var exists bool
	err := r.DB.QueryRowContext(ctx, `SELECT EXISTS(
		SELECT 1 FROM data_cleanup WHERE user_id = $1 AND stage = $2
	)`, userID, entity.Scheduled).Scan(&exists)
	return exists, stacktrace.Propagate(err, "failed to check scheduled delete")
}

func (r *Repository) LockScheduledDelete(ctx context.Context, tx *sql.Tx, userID int64) error {
	var lockedUserID int64
	return tx.QueryRowContext(ctx, `SELECT user_id FROM data_cleanup
		WHERE user_id = $1 AND stage = $2 FOR UPDATE`, userID, entity.Scheduled).Scan(&lockedUserID)
}

func (r *Repository) RemoveScheduledDelete(ctx context.Context, userID int64) error {
	return removeScheduledDelete(ctx, r.DB, userID)
}

func (r *Repository) RemoveScheduledDeleteTx(ctx context.Context, tx *sql.Tx, userID int64) error {
	return removeScheduledDelete(ctx, tx, userID)
}

type scheduledDeleteExecutor interface {
	ExecContext(context.Context, string, ...any) (sql.Result, error)
}

func removeScheduledDelete(ctx context.Context, executor scheduledDeleteExecutor, userID int64) error {
	result, err := executor.ExecContext(ctx, `DELETE FROM data_cleanup WHERE user_id = $1 AND stage = $2`, userID, entity.Scheduled)
	if err != nil {
		return err
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if affected != 1 {
		return fmt.Errorf("only one row should have been affected, got %d", affected)
	}
	return nil
}

func (r *Repository) GetItemsPendingCompletion(ctx context.Context, limit int) ([]*entity.DataCleanup, error) {
	rows, err := r.DB.QueryContext(ctx, `SELECT user_id, stage, stage_schedule_time, stage_attempt_count, created_at, updated_at  from  data_cleanup 
         where stage != $1 and stage_schedule_time < now_utc_micro_seconds() 
         ORDER BY stage_schedule_time LIMIT $2`, entity.Completed, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	result := make([]*entity.DataCleanup, 0)

	for rows.Next() {
		item := entity.DataCleanup{}
		if err = rows.Scan(&item.UserID, &item.Stage, &item.StageScheduleTime, &item.StageAttemptCount, &item.CreatedAt, &item.UpdatedAt); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}

		result = append(result, &item)
	}
	return result, nil
}

// MoveToNextStage update stage with corresponding schedule
func (r *Repository) MoveToNextStage(ctx context.Context, userID int64, stage entity.Stage, stageScheduleTime int64) error {
	_, err := r.DB.ExecContext(ctx, `UPDATE data_cleanup SET stage = $1,stage_schedule_time = $2, stage_attempt_count=0
			 WHERE user_id = $3`, stage, stageScheduleTime, userID)
	return stacktrace.Propagate(err, "failed to insert/update")
}

// ScheduleNextAttemptAfterNHours bumps the attempt count by one and schedule next attempt after n hr(s)
func (r *Repository) ScheduleNextAttemptAfterNHours(ctx context.Context, userID int64, n int32) error {
	_, err := r.DB.ExecContext(ctx, `UPDATE data_cleanup SET stage_attempt_count = stage_attempt_count +1, stage_schedule_time = $1
			 WHERE user_id = $2`, time.MicrosecondsAfterHours(n), userID)
	return stacktrace.Propagate(err, "failed to insert/update")
}

func (r *Repository) DeleteTableData(ctx context.Context, userID int64) error {
	_, err := r.DB.ExecContext(ctx, `DELETE FROM key_attributes WHERE user_id = $1`, userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to delete key attributes data")
	}
	_, err = r.DB.ExecContext(ctx, `DELETE FROM authenticator_key WHERE user_id = $1`, userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to delete auth data")
	}
	_, err = r.DB.ExecContext(ctx, `DELETE FROM entity_key WHERE user_id = $1`, userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to delete entity key data")
	}
	// delete entity_data
	_, err = r.DB.ExecContext(ctx, `DELETE FROM entity_data WHERE user_id = $1`, userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to delete entity data")
	}
	_, err = r.DB.ExecContext(ctx, `UPDATE user_attachments
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
		WHERE user_id = $1
		  AND is_deleted = FALSE`, userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to mark contact attachment data deleted")
	}
	_, err = r.DB.ExecContext(ctx, `DELETE FROM contact_entity WHERE user_id = $1`, userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to delete contact data")
	}
	// deleting casting data
	_, err = r.DB.ExecContext(ctx, `DELETE FROM casting WHERE cast_user = $1`, userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to delete casting data")
	}
	// delete notification_history data
	_, err = r.DB.ExecContext(ctx, `DELETE FROM notification_history WHERE user_id = $1`, userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to delete notification history data")
	}
	// delete families data
	_, err = r.DB.ExecContext(ctx, `DELETE FROM families WHERE admin_id = $1`, userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to delete family data")
	}

	// delete passkeys (this also clears passkey_credentials via foreign key constraint)
	_, err = r.DB.ExecContext(ctx, `DELETE FROM passkeys WHERE user_id = $1`, userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to delete passkeys data")
	}
	// delete passkey_login_sessions
	_, err = r.DB.ExecContext(ctx, `DELETE FROM passkey_login_sessions WHERE user_id = $1`, userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to delete passkey login sessions data")
	}
	_, err = r.DB.ExecContext(ctx, `DELETE FROM remote_store WHERE user_id = $1`, userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to delete remote store data")
	}

	// delete srp_auth data
	_, err = r.DB.ExecContext(ctx, `DELETE FROM srp_auth WHERE user_id = $1`, userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to delete srp auth data")
	}
	// delete temp_srp_setup data
	_, err = r.DB.ExecContext(ctx, `DELETE FROM temp_srp_setup WHERE user_id = $1`, userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to delete temp srp setup data")
	}
	// delete two_factor data
	_, err = r.DB.ExecContext(ctx, `DELETE FROM two_factor WHERE user_id = $1`, userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to delete two factor data")
	}
	// delete tokens data
	_, err = r.DB.ExecContext(ctx, `DELETE FROM tokens WHERE user_id = $1`, userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to delete tokens data")
	}
	// delete webauthn_sessions data
	_, err = r.DB.ExecContext(ctx, `DELETE FROM webauthn_sessions WHERE user_id = $1`, userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to delete web auth sessions data")
	}
	return nil
}
