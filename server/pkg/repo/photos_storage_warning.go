package repo

import (
	"context"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/time"
)

const (
	PhotosStorageWarningTemplateID  = "photos_storage_90_percent"
	PhotosStorageReminderTemplateID = "photos_storage_reminder"
)

func (repo *UserRepository) GetPhotosStorageWarningCandidates(ctx context.Context) ([]int64, error) {
	rows, err := repo.DB.QueryContext(ctx, `
  SELECT u.user_id
  FROM users u
  JOIN subscriptions s ON s.user_id = u.user_id
  JOIN usage us ON us.user_id = u.user_id
  WHERE u.family_admin_id IS NULL
    AND u.encrypted_email IS NOT NULL
    AND s.product_id = $1
    AND s.storage > 0
    AND s.expiry_time > now_utc_micro_seconds()
    AND us.storage_consumed >= s.storage - s.storage / 10
    AND NOT EXISTS (
      SELECT 1 FROM notification_history n
      WHERE n.user_id = u.user_id AND n.template_id IN ($2, $3)
    )
  ORDER BY u.user_id`, ente.FreePlanProductID, PhotosStorageReminderTemplateID, StorageLimitExceededTemplateID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ids []int64
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

func (repo *NotificationHistoryRepository) ClaimPhotosStorageNotification(ctx context.Context, userID int64, event string) (bool, error) {
	result, err := repo.DB.ExecContext(ctx, `
  INSERT INTO notification_history(user_id,template_id,sent_time) VALUES($1,$2,$3)
  ON CONFLICT(user_id,template_id)
    WHERE template_id IN ('photos_storage_90_percent','photos_storage_reminder') DO NOTHING`, userID, event, time.Microseconds())
	if err != nil {
		return false, err
	}
	count, err := result.RowsAffected()
	return count == 1, err
}
