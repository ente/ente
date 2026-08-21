package repo

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"github.com/ente/museum/pkg/repo/public"
	"strings"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
	"github.com/lib/pq"
	"github.com/sirupsen/logrus"
)

const (
	TrashDurationInDays = 30
	TrashDiffLimit      = 2500

	TrashBatchSize = 1000

	EmptyTrashQueueItemSeparator = "::"
)

type FileWithUpdatedAt struct {
	FileID    int64
	UpdatedAt int64
}

type TrashRepository struct {
	DB           *sql.DB
	ObjectRepo   *ObjectRepository
	FileRepo     *FileRepository
	QueueRepo    *QueueRepository
	FileLinkRepo *public.FileLinkRepository
}

func (t *TrashRepository) InsertItems(ctx context.Context, tx *sql.Tx, userID int64, items []ente.TrashItemRequest) error {
	if len(items) == 0 {
		return nil
	}
	lb := 0
	size := len(items)
	deletedBy := time.NDaysFromNow(TrashDurationInDays)
	for lb < size {
		ub := min(lb+TrashBatchSize, size)
		slicedList := items[lb:ub]

		var inserts []string
		var params []interface{}
		updatedAt := time.Microseconds()
		query := "INSERT INTO trash(file_id, collection_id, user_id, delete_by, updated_at) VALUES "
		for i, v := range slicedList {
			inserts = append(inserts, fmt.Sprintf("($%d, $%d, $%d, $%d, $%d)", i*5+1, i*5+2, i*5+3, i*5+4, i*5+5))
			params = append(params, v.FileID, v.CollectionID, userID, deletedBy, updatedAt)
		}
		queryVals := strings.Join(inserts, ",")
		query = query + queryVals
		query = query + ` ON CONFLICT (file_id) DO UPDATE SET(is_restored, delete_by, updated_at) = ` +
			fmt.Sprintf("(FALSE, $%d, $%d)", len(slicedList)*5+1, len(slicedList)*5+2) + ` WHERE trash.is_deleted = FALSE`
		params = append(params, deletedBy, updatedAt)
		_, err := tx.ExecContext(ctx, query, params...)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
		lb += TrashBatchSize
	}
	return nil
}

func (t *TrashRepository) GetDiff(userID int64, sinceTime int64, limit int, app ente.App) ([]ente.Trash, error) {
	rows, err := t.DB.Query(`
	SELECT t.file_id, t.user_id, t.collection_id, cf.encrypted_key, cf.key_decryption_nonce, 
		f.file_decryption_header, f.thumbnail_decryption_header, f.metadata_decryption_header, 
		f.encrypted_metadata, f.magic_metadata,f.pub_magic_metadata, f.updation_time, f.info,
		t.is_deleted, t.is_restored, t.created_at, t.updated_at, t.delete_by
	FROM trash t 
	JOIN collection_files cf ON t.file_id = cf.file_id AND t.collection_id = cf.collection_id
	JOIN files f ON f.file_id = t.file_id
			AND t.user_id = $1
			AND f.owner_id = $1
			AND t.updated_at > $2
	JOIN collections c ON c.collection_id = t.collection_id
	WHERE c.app = $4
	ORDER BY t.updated_at 
	LIMIT $3
`,
		userID, sinceTime, limit, app)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return convertRowsToTrash(rows)
}

func (t *TrashRepository) GetFilesWithVersion(userID int64, updateAtTime int64, app ente.App) ([]ente.Trash, error) {
	rows, err := t.DB.Query(`
		SELECT t.file_id, t.user_id, t.collection_id, cf.encrypted_key, cf.key_decryption_nonce,
		       f.file_decryption_header, f.thumbnail_decryption_header, f.metadata_decryption_header,
		       f.encrypted_metadata, f.magic_metadata, f.pub_magic_metadata, f.updation_time, f.info,
		       t.is_deleted, t.is_restored, t.created_at, t.updated_at, t.delete_by
		FROM trash t
		    JOIN collection_files cf ON t.file_id = cf.file_id AND t.collection_id = cf.collection_id
		    JOIN files f ON  f.file_id = t.file_id
		                         AND t.user_id = $1
		                         AND t.updated_at = $2
		    JOIN collections c ON c.collection_id = t.collection_id
		WHERE c.app = $3`,
		userID, updateAtTime, app)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return convertRowsToTrash(rows)
}

func (t *TrashRepository) TrashFiles(ctx context.Context, userID int64, trash ente.TrashRequest) error {
	fileIDs := make([]int64, 0, len(trash.TrashItems))
	for _, item := range trash.TrashItems {
		fileIDs = append(fileIDs, item.FileID)
	}
	tx, err := t.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()
	if err := lockFiles(ctx, tx, userID, fileIDs); err != nil {
		return stacktrace.Propagate(err, "")
	}
	updationTime := time.Microseconds()
	rows, err := tx.QueryContext(ctx, `SELECT DISTINCT collection_id FROM 
			collection_files WHERE file_id = ANY($1) AND is_deleted = $2`, pq.Array(fileIDs), false)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	cIDs := make([]int64, 0)
	for rows.Next() {
		var cID int64
		if err := rows.Scan(&cID); err != nil {
			return stacktrace.Propagate(err, "")
		}
		cIDs = append(cIDs, cID)
	}
	_, err = tx.ExecContext(ctx, `UPDATE collection_files 
			SET is_deleted = $1, updation_time = $2 WHERE file_id = ANY($3)`,
		true, updationTime, pq.Array(fileIDs))
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	_, err = tx.ExecContext(ctx, `UPDATE collections SET updation_time = $1
			WHERE collection_id = ANY ($2)`, updationTime, pq.Array(cIDs))
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	err = t.InsertItems(ctx, tx, userID, trash.TrashItems)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if err = t.FileLinkRepo.DisableLinkForFilesTx(ctx, tx, fileIDs); err != nil {
		return stacktrace.Propagate(err, "failed to disable file links for files being trashed")
	}
	return stacktrace.Propagate(tx.Commit(), "")
}

func (t *TrashRepository) CleanUpDeletedFilesFromCollection(ctx context.Context, fileIDs []int64, userID int64) error {
	err := t.verifyFilesAreDeleted(ctx, userID, fileIDs)
	if err != nil {
		return stacktrace.Propagate(err, "deleted files check failed")
	}
	tx, err := t.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	rows, err := tx.QueryContext(ctx, `SELECT DISTINCT collection_id FROM 
		collection_files WHERE file_id = ANY($1) AND is_deleted = $2`, pq.Array(fileIDs), false)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	cIDs := make([]int64, 0)
	for rows.Next() {
		var cID int64
		if err := rows.Scan(&cID); err != nil {
			return stacktrace.Propagate(err, "")
		}
		cIDs = append(cIDs, cID)
	}
	updationTime := time.Microseconds()
	_, err = tx.ExecContext(ctx, `UPDATE collection_files 
		SET is_deleted = $1, updation_time = $2 WHERE file_id = ANY($3)`,
		true, updationTime, pq.Array(fileIDs))
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	_, err = tx.ExecContext(ctx, `UPDATE collections SET updation_time = $1
		WHERE collection_id = ANY ($2)`, updationTime, pq.Array(cIDs))
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	err = tx.Commit()
	return stacktrace.Propagate(err, "")
}

func (t *TrashRepository) Delete(ctx context.Context, userID int64, fileIDs []int64) error {
	if len(fileIDs) > TrashDiffLimit {
		return fmt.Errorf("can not delete more than %d in one go", TrashDiffLimit)
	}
	tx, err := t.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()
	if err := lockFiles(ctx, tx, userID, fileIDs); err != nil {
		return stacktrace.Propagate(err, "")
	}
	fileIDsInTrash, _, err := t.getFilesInTrashState(ctx, tx, userID, fileIDs)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}

	logrus.WithField("fileIDs", fileIDsInTrash).Info("deleting files")
	_, err = tx.ExecContext(ctx, `UPDATE trash SET is_deleted= true WHERE file_id = ANY ($1)`, pq.Array(fileIDsInTrash))
	if err != nil {
		return stacktrace.Propagate(err, "")
	}

	err = t.FileRepo.scheduleDeletion(ctx, tx, fileIDsInTrash, userID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	return stacktrace.Propagate(tx.Commit(), "")
}

func (t *TrashRepository) getFilesInTrashState(ctx context.Context, tx *sql.Tx, userID int64, fileIDs []int64) ([]int64, bool, error) {
	rows, err := tx.QueryContext(ctx, `SELECT file_id FROM trash
			WHERE user_id = $1 AND file_id = ANY ($2)
			AND is_deleted = FALSE AND is_restored = FALSE`, userID, pq.Array(fileIDs))
	if err != nil {
		return nil, false, stacktrace.Propagate(err, "")
	}
	fileIDsInTrash, err := convertRowsToFileId(rows)
	if err != nil {
		return nil, false, stacktrace.Propagate(err, "")
	}

	canRestoreOrDeleteAllFiles := len(fileIDsInTrash) == len(fileIDs)
	if !canRestoreOrDeleteAllFiles {
		logrus.WithFields(logrus.Fields{
			"user_id":       userID,
			"input_fileIds": fileIDs,
			"trash_fileIds": fileIDsInTrash,
		}).Warn("mismatch in input fileIds and fileIDs present in trash")
	}
	return fileIDsInTrash, canRestoreOrDeleteAllFiles, nil
}

func (t *TrashRepository) getFilesInTrashOrDeleted(ctx context.Context, tx *sql.Tx, userID int64, fileIDs []int64) ([]int64, error) {
	rows, err := tx.QueryContext(ctx, `SELECT file_id FROM trash
			WHERE user_id = $1 AND file_id = ANY ($2)
			AND is_restored = FALSE`, userID, pq.Array(fileIDs))
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	fileIDsInTrash, err := convertRowsToFileId(rows)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return fileIDsInTrash, nil
}

func (t *TrashRepository) verifyFilesAreDeleted(ctx context.Context, userID int64, fileIDs []int64) error {
	rows, err := t.DB.QueryContext(ctx, `SELECT file_id FROM trash 
			WHERE user_id = $1 AND file_id = ANY ($2) 
			AND is_deleted = TRUE AND is_restored = FALSE`, userID, pq.Array(fileIDs))
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	filesDeleted, err := convertRowsToFileId(rows)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}

	areAllFilesDeleted := len(filesDeleted) == len(fileIDs)
	if !areAllFilesDeleted {
		logrus.WithFields(logrus.Fields{
			"user_id":       userID,
			"input_fileIds": fileIDs,
			"trash_fileIds": filesDeleted,
		}).Error("all file ids are not deleted from trash")
		return stacktrace.NewError("all file ids are not deleted from trash")
	}

	row := t.DB.QueryRowContext(ctx, `SELECT coalesce(sum(size),0) FROM object_keys WHERE file_id = ANY($1) and is_deleted = FALSE`,
		pq.Array(fileIDs))
	var totalUsage int64
	err = row.Scan(&totalUsage)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			totalUsage = 0
		} else {
			return stacktrace.Propagate(err, "failed to get total usage for fileIDs")
		}
	}
	if totalUsage != 0 {
		logrus.WithFields(logrus.Fields{
			"user_id":       userID,
			"input_fileIds": fileIDs,
			"trash_fileIds": filesDeleted,
			"total_usage":   totalUsage,
		}).Error("object_keys table still has entries for deleted files")
		return stacktrace.NewError("object_keys table still has entries for deleted files")
	}
	return nil
}

func (t *TrashRepository) GetFilesIDsForDeletion(userID int64, lastUpdatedAt int64, app ente.App) ([]int64, error) {
	rows, err := t.DB.Query(`SELECT t.file_id FROM trash t
                JOIN collections c ON c.collection_id = t.collection_id
                WHERE t.user_id = $1 AND t.updated_at <= $2 AND t.is_deleted = FALSE AND t.is_restored = FALSE AND c.app = $3`, userID, lastUpdatedAt, app)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	fileIDs, err := convertRowsToFileId(rows)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return fileIDs, nil
}

func (t *TrashRepository) GetTimeStampForLatestNonDeletedEntry(userID int64) (*int64, error) {
	row := t.DB.QueryRow(`SELECT max(updated_at) FROM trash WHERE user_id = $1 AND is_deleted = FALSE AND is_restored = FALSE`, userID)
	var updatedAt *int64
	err := row.Scan(&updatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return updatedAt, stacktrace.Propagate(err, "")
}

func (t *TrashRepository) HasItems(ctx context.Context, userID int64) (bool, error) {
	row := t.DB.QueryRowContext(ctx, `
		SELECT exists(
			SELECT 1 FROM trash
			WHERE user_id = $1
		)`, userID)
	var hasItems bool
	err := row.Scan(&hasItems)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	return hasItems, stacktrace.Propagate(err, "")
}

func (t *TrashRepository) GetUserIDToFileIDsMapForDeletion() (map[int64][]int64, error) {
	rows, err := t.DB.Query(`SELECT user_id, file_id FROM trash 
			WHERE delete_by <= $1  AND is_deleted IS FALSE AND is_restored IS FALSE limit $2`,
		time.Microseconds(), TrashDiffLimit)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	result := make(map[int64][]int64, 0)
	for rows.Next() {
		var userID, fileID int64
		if err = rows.Scan(&userID, &fileID); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		if fileIDs, ok := result[userID]; ok {
			result[userID] = append(fileIDs, fileID)
		} else {
			result[userID] = []int64{fileID}
		}
	}
	return result, nil
}

// Wait 50 days for compliance deletion locks, and never split an updated_at
// group across batches.
func (t *TrashRepository) GetFileIdsForDroppingMetadata(sinceUpdatedAt int64) ([]FileWithUpdatedAt, error) {
	rows, err := t.DB.Query(`
		select file_id, updated_at from trash  where is_deleted=true AND updated_at > $1
AND updated_at < (now_utc_micro_seconds() - (24::BIGINT * 50* 60 * 60 * 1000 * 1000))
order by updated_at ASC limit $2
`, sinceUpdatedAt, TrashDiffLimit+1)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	var fileWithUpdatedAt []FileWithUpdatedAt
	for rows.Next() {
		var fileID, updatedAt int64
		if err = rows.Scan(&fileID, &updatedAt); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		fileWithUpdatedAt = append(fileWithUpdatedAt, FileWithUpdatedAt{
			FileID:    fileID,
			UpdatedAt: updatedAt,
		})
	}

	if len(fileWithUpdatedAt) == 0 {
		return []FileWithUpdatedAt{}, nil
	}
	if len(fileWithUpdatedAt) < TrashDiffLimit {
		return fileWithUpdatedAt, nil
	}

	lastUpdatedAt := fileWithUpdatedAt[len(fileWithUpdatedAt)-1].UpdatedAt
	var i = len(fileWithUpdatedAt) - 1
	for ; i >= 0; i-- {
		if fileWithUpdatedAt[i].UpdatedAt != lastUpdatedAt {
			break
		}
	}
	return fileWithUpdatedAt[0 : i+1], nil
}

func (t *TrashRepository) EmptyTrash(ctx context.Context, userID int64, lastUpdatedAt int64, app ente.App) error {
	itemID := fmt.Sprintf("%d%s%d", userID, EmptyTrashQueueItemSeparator, lastUpdatedAt)
	queueName := TrashEmptyQueue
	if app == ente.Locker {
		queueName = TrashEmptyLockerQueue
	}
	return t.QueueRepo.InsertItem(ctx, queueName, itemID)
}

func (t *TrashRepository) GetTrashUpdatedAt(userID int64) (int64, error) {
	row := t.DB.QueryRow(`SELECT coalesce(max(updated_at),0) FROM trash WHERE user_id = $1`, userID)
	var updatedAt int64
	err := row.Scan(&updatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, nil
	}
	return updatedAt, stacktrace.Propagate(err, "")
}

func convertRowsToTrash(rows *sql.Rows) ([]ente.Trash, error) {
	defer rows.Close()
	trashFiles := make([]ente.Trash, 0)
	for rows.Next() {
		var (
			trash ente.Trash
		)
		err := rows.Scan(&trash.File.ID, &trash.File.OwnerID, &trash.File.CollectionID, &trash.File.EncryptedKey, &trash.File.KeyDecryptionNonce,
			&trash.File.File.DecryptionHeader, &trash.File.Thumbnail.DecryptionHeader, &trash.File.Metadata.DecryptionHeader,
			&trash.File.Metadata.EncryptedData, &trash.File.MagicMetadata, &trash.File.PubicMagicMetadata, &trash.File.UpdationTime, &trash.File.Info, &trash.IsDeleted, &trash.IsRestored,
			&trash.CreatedAt, &trash.UpdatedAt, &trash.DeleteBy)
		if err != nil {
			return trashFiles, stacktrace.Propagate(err, "")
		}

		trashFiles = append(trashFiles, trash)
	}
	return trashFiles, nil
}
