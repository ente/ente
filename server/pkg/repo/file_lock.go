package repo

import (
	"context"
	"database/sql"

	"github.com/ente/stacktrace"
	"github.com/lib/pq"
)

func lockFiles(ctx context.Context, tx *sql.Tx, userID int64, fileIDs []int64) error {
	if len(fileIDs) == 0 {
		return nil
	}

	rows, err := tx.QueryContext(ctx, `SELECT file_id
		FROM files
		WHERE owner_id = $1 AND file_id = ANY($2)
		ORDER BY file_id
		FOR UPDATE`, userID, pq.Array(fileIDs))
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	defer rows.Close()

	for rows.Next() {
		var fileID int64
		if err := rows.Scan(&fileID); err != nil {
			return stacktrace.Propagate(err, "")
		}
	}
	return stacktrace.Propagate(rows.Err(), "")
}
