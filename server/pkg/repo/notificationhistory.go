package repo

import (
	"context"
	"database/sql"

	"github.com/ente/stacktrace"
	"github.com/lib/pq"

	"github.com/ente/museum/pkg/utils/time"
)

type NotificationHistoryRepository struct {
	DB *sql.DB
}

const (
	StorageWarningExpiredScheduledDeletionTemplateID       = "storage_warning_expired_scheduled_deletion"
	StorageWarningActiveOverageScheduledDeletionTemplateID = "storage_warning_active_overage_scheduled_deletion"
	StorageWarningLoginGraceTemplateID                     = "storage_warning_login_grace_7d"
	StorageWarningLoginGraceNotificationGroup              = "storage_warning_login_grace"
	StorageWarningLoginGraceDays                           = 7
	StorageWarningLoginGraceDurationMicroseconds           = StorageWarningLoginGraceDays * 24 * time.MicroSecondsInOneHour
)

func (repo *NotificationHistoryRepository) GetLastNotificationTime(userID int64, templateID string) (int64, error) {
	var lastNotificationTime sql.NullInt64
	row := repo.DB.QueryRow(`SELECT MAX(sent_time) FROM notification_history WHERE user_id = $1 and template_id = $2`, userID, templateID)
	err := row.Scan(&lastNotificationTime)
	if err != nil {
		return 0, stacktrace.Propagate(err, "")
	}
	if lastNotificationTime.Valid {
		return lastNotificationTime.Int64, nil
	}
	return 0, nil
}

func (repo *NotificationHistoryRepository) SetLastNotificationTimeToNow(userID int64, templateID string) error {
	return repo.SetLastNotificationTimeToNowWithGroup(userID, templateID, "")
}

func (repo *NotificationHistoryRepository) SetLastNotificationTimeToNowWithGroup(userID int64, templateID string, notificationGroup string) error {
	var groupValue sql.NullString
	if notificationGroup != "" {
		groupValue = sql.NullString{
			String: notificationGroup,
			Valid:  true,
		}
	}
	_, err := repo.DB.Exec(`INSERT INTO notification_history(user_id, template_id, sent_time, notification_group) VALUES($1, $2, $3, $4)`,
		userID, templateID, time.Microseconds(), groupValue)
	return stacktrace.Propagate(err, "")
}

// GetLastNotificationTimes returns the latest sent_time per templateID for the
// provided user.
func (repo *NotificationHistoryRepository) GetLastNotificationTimes(userID int64, templateIDs []string) (map[string]int64, error) {
	result := make(map[string]int64)
	if len(templateIDs) == 0 {
		return result, nil
	}

	rows, err := repo.DB.Query(
		`SELECT template_id, MAX(sent_time) FROM notification_history
		 WHERE user_id = $1 AND template_id = ANY($2)
		 GROUP BY template_id`,
		userID, pq.Array(templateIDs))
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to fetch notification history")
	}
	defer rows.Close()

	for rows.Next() {
		var templateID string
		var sentTime int64
		if err := rows.Scan(&templateID, &sentTime); err != nil {
			return nil, stacktrace.Propagate(err, "failed to scan notification history")
		}
		result[templateID] = sentTime
	}
	if err := rows.Err(); err != nil {
		return nil, stacktrace.Propagate(err, "failed to iterate notification history")
	}

	return result, nil
}

func (repo *NotificationHistoryRepository) DeleteNotificationHistoryByGroupExcludingUsers(notificationGroup string, keepUserIDs []int64) error {
	if notificationGroup == "" {
		return nil
	}

	if len(keepUserIDs) == 0 {
		_, err := repo.DB.Exec(`DELETE FROM notification_history WHERE notification_group = $1`, notificationGroup)
		return stacktrace.Propagate(err, "failed to delete grouped notification history")
	}

	_, err := repo.DB.Exec(
		`DELETE FROM notification_history
		 WHERE notification_group = $1
		   AND NOT (user_id = ANY($2))`,
		notificationGroup, pq.Array(keepUserIDs))
	return stacktrace.Propagate(err, "failed to delete grouped notification history")
}

func StorageWarningScheduledDeletionTemplateIDs() []string {
	return []string{
		StorageWarningExpiredScheduledDeletionTemplateID,
		StorageWarningActiveOverageScheduledDeletionTemplateID,
	}
}

func StorageWarningLoginGraceUntil(sentAt int64) int64 {
	if sentAt <= 0 {
		return 0
	}
	return sentAt + StorageWarningLoginGraceDurationMicroseconds
}

func StorageWarningLoginGraceActive(sentAt int64, now int64) bool {
	graceUntil := StorageWarningLoginGraceUntil(sentAt)
	return graceUntil > 0 && now < graceUntil
}

// GetStorageWarningLoginGraceCandidates returns warning recipients with a
// grace marker, even if their current usage is below the normal candidate
// threshold. The daily job uses this to clear recovered grace rows or re-block
// after the grace window expires.
func (repo *NotificationHistoryRepository) GetStorageWarningLoginGraceCandidates(ctx context.Context) ([]StorageWarningCandidate, error) {
	rows, err := repo.DB.QueryContext(ctx, `
		SELECT
			nh.user_id AS recipient_id,
			u.family_admin_id IS NOT NULL AS is_family_plan
		FROM notification_history nh
		INNER JOIN users u
			ON u.user_id = nh.user_id
		WHERE
			nh.template_id = $1
			AND u.encrypted_email IS NOT NULL
		GROUP BY nh.user_id, u.family_admin_id
		ORDER BY nh.user_id
	`, StorageWarningLoginGraceTemplateID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to fetch storage warning login grace candidates")
	}
	defer rows.Close()

	candidates := make([]StorageWarningCandidate, 0)
	for rows.Next() {
		var candidate StorageWarningCandidate
		if err := rows.Scan(&candidate.RecipientID, &candidate.IsFamilyPlan); err != nil {
			return nil, stacktrace.Propagate(err, "failed to scan storage warning login grace candidate")
		}
		candidates = append(candidates, candidate)
	}
	if err := rows.Err(); err != nil {
		return nil, stacktrace.Propagate(err, "failed to iterate storage warning login grace candidates")
	}
	return candidates, nil
}

func (repo *NotificationHistoryRepository) HasAnyNotificationForTemplates(userID int64, templateIDs []string) (bool, error) {
	if len(templateIDs) == 0 {
		return false, nil
	}

	row := repo.DB.QueryRow(
		`SELECT EXISTS(
			SELECT 1
			  FROM notification_history
			 WHERE user_id = $1
			   AND template_id = ANY($2)
		)`,
		userID, pq.Array(templateIDs))
	var exists bool
	if err := row.Scan(&exists); err != nil {
		return false, stacktrace.Propagate(err, "failed to read notification history existence")
	}
	return exists, nil
}

func (repo *NotificationHistoryRepository) IsStorageWarningDeletionScheduled(userID int64) (bool, error) {
	return repo.HasAnyNotificationForTemplates(userID, StorageWarningScheduledDeletionTemplateIDs())
}

func (repo *NotificationHistoryRepository) ClearStorageWarningDeletionScheduled(userID int64) error {
	_, err := repo.DB.Exec(
		`DELETE FROM notification_history
		 WHERE user_id = $1
		   AND template_id = ANY($2)`,
		userID, pq.Array(StorageWarningScheduledDeletionTemplateIDs()))
	return stacktrace.Propagate(err, "failed to clear storage warning scheduled deletion history")
}

func (repo *NotificationHistoryRepository) ClearStorageWarningLoginGrace(userID int64) error {
	_, err := repo.DB.Exec(
		`DELETE FROM notification_history
		 WHERE user_id = $1
		   AND template_id = $2`,
		userID, StorageWarningLoginGraceTemplateID)
	return stacktrace.Propagate(err, "failed to clear storage warning login grace")
}

func (repo *NotificationHistoryRepository) IsStorageWarningLoginGraceActive(userID int64, now int64) (bool, int64, error) {
	graceSentAt, err := repo.GetLastNotificationTime(userID, StorageWarningLoginGraceTemplateID)
	if err != nil {
		return false, 0, stacktrace.Propagate(err, "failed to read storage warning login grace")
	}
	graceUntil := StorageWarningLoginGraceUntil(graceSentAt)
	return StorageWarningLoginGraceActive(graceSentAt, now), graceUntil, nil
}

// GrantStorageWarningLoginGrace replaces terminal login-block rows with a
// soft-unblock marker. Duplicate grace rows are allowed; readers use the latest
// sent_time so a later admin action starts a fresh window.
func (repo *NotificationHistoryRepository) GrantStorageWarningLoginGrace(userID int64) (int64, bool, error) {
	now := time.Microseconds()
	tx, err := repo.DB.Begin()
	if err != nil {
		return 0, false, stacktrace.Propagate(err, "failed to start storage warning grace transaction")
	}
	defer tx.Rollback()

	result, err := tx.Exec(
		`DELETE FROM notification_history
		 WHERE user_id = $1
		   AND template_id = ANY($2)`,
		userID, pq.Array(StorageWarningScheduledDeletionTemplateIDs()))
	if err != nil {
		return 0, false, stacktrace.Propagate(err, "failed to clear storage warning scheduled deletion history")
	}
	deletedRows, err := result.RowsAffected()
	if err != nil {
		return 0, false, stacktrace.Propagate(err, "failed to read cleared storage warning scheduled deletion count")
	}
	if deletedRows == 0 {
		if err := tx.Commit(); err != nil {
			return 0, false, stacktrace.Propagate(err, "failed to commit storage warning grace transaction")
		}
		return 0, false, nil
	}

	_, err = tx.Exec(
		`INSERT INTO notification_history(user_id, template_id, sent_time, notification_group)
		 VALUES($1, $2, $3, $4)`,
		userID,
		StorageWarningLoginGraceTemplateID,
		now,
		StorageWarningLoginGraceNotificationGroup)
	if err != nil {
		return 0, false, stacktrace.Propagate(err, "failed to grant storage warning login grace")
	}

	if err := tx.Commit(); err != nil {
		return 0, false, stacktrace.Propagate(err, "failed to commit storage warning grace transaction")
	}
	return now + StorageWarningLoginGraceDurationMicroseconds, true, nil
}
