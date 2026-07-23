package repo

import (
	"context"
	"database/sql"

	"github.com/ente/museum/ente"
	"github.com/ente/stacktrace"
	"github.com/lib/pq"
	log "github.com/sirupsen/logrus"
)

// GetFilesInfo returns map of fileIDs to ente.FileInfo for a given userID.
func (repo *FileRepository) GetFilesInfo(ctx context.Context, fileIDs []int64, userID int64) (map[int64]*ente.FileInfo, error) {
	rows, err := repo.DB.QueryContext(ctx, `SELECT file_id, info from files where file_id = ANY($1) and owner_id = $2`, pq.Array(fileIDs), userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	result := make(map[int64]*ente.FileInfo, 0)
	for rows.Next() {
		var fileID int64
		var info *ente.FileInfo
		if err = rows.Scan(&fileID, &info); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		result[fileID] = info
	}
	return result, nil
}

// UpdateSizeInfo updates the size info for a given map of fileIDs to ente.FileInfo.
func (repo *FileRepository) UpdateSizeInfo(ctx context.Context, sizeInfo map[int64]*ente.FileInfo) error {
	// Update the size info for each file using a batched transaction.
	tx, err := repo.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()
	for fileID, info := range sizeInfo {
		_, err := tx.ExecContext(ctx, `UPDATE files SET info = $1 WHERE file_id = $2 and info is NULL`, info, fileID)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
	}
	if err := tx.Commit(); err != nil {
		return stacktrace.Propagate(err, "")
	}
	return nil
}

// GetFileInfoFromObjectKeys returns the file info for a given list of fileIDs.
func (repo *FileRepository) GetFileInfoFromObjectKeys(ctx context.Context, fileIDs []int64) (map[int64]*ente.FileInfo, error) {
	rows, err := repo.DB.QueryContext(ctx, `SELECT file_id, size, o_type FROM object_keys WHERE file_id = ANY($1)`, pq.Array(fileIDs))
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer func(rows *sql.Rows) {
		err := rows.Close()
		if err != nil {
			log.Errorf("error closing rows: %v", err)
		}
	}(rows)
	result := make(map[int64]*ente.FileInfo, 0)
	for rows.Next() {
		var fileID int64
		var size int64
		var oType ente.ObjectType
		if err = rows.Scan(&fileID, &size, &oType); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		if _, ok := result[fileID]; !ok {
			result[fileID] = &ente.FileInfo{}
		}
		switch oType {
		case ente.FILE:
			result[fileID].FileSize = size
		case ente.THUMBNAIL:
			result[fileID].ThumbnailSize = size
		}
	}
	return result, nil
}
