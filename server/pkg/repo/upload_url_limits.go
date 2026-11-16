package repo

import (
	"context"
	"database/sql"
	"time"
)

type UploadURLRepository struct {
	DB *sql.DB
}

func (r *UploadURLRepository) CountPending(ctx context.Context, userID int64, since time.Time, limit int) (int, error) {
	var count int
	err := r.DB.QueryRowContext(ctx, `SELECT COUNT(*) FROM (
		SELECT 1 FROM temp_objects
		WHERE user_id = $1 AND created_at > $2 AND cleanup_state IS NULL
		ORDER BY created_at DESC LIMIT $3
	) pending`, userID, since.UnixMicro(), limit).Scan(&count)
	return count, err
}
