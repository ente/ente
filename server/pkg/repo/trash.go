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
	// TrashDurationInDays number of days after which file will be removed from trash
	TrashDurationInDays = 30
	// TrashDiffLimit is the default limit for number of items server will attempt to return when clients
	// ask for changes.
	TrashDiffLimit = 2500

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

func (t *TrashRepository) TrashFiles(fileIDs []int64, userID int64, trash ente.TrashRequest) error {
	updationTime := time.Microseconds()
	ctx := context.Background()
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
	err = t.InsertItems(ctx, tx, userID, trash.TrashItems)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	err = tx.Commit()

	if err == nil {
		removeLinkErr := t.FileLinkRepo.DisableLinkForFiles(ctx, fileIDs)
		if removeLinkErr != nil {
			return stacktrace.Propagate(removeLinkErr, "failed to disable file links for files being trashed")
		}
	}
	return stacktrace.Propagate(err, "")
}

// CleanUpDeletedFilesFromCollection deletes the files from the collection if the files are deleted from the trash
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
	// find file_ids from the trash which belong to the user and can be deleted
	// skip restored and already deleted files
	fileIDsInTrash, _, err := t.GetFilesInTrashState(ctx, userID, fileIDs)
	if err != nil {
		return err
	}
	tx, err := t.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}

	logrus.WithField("fileIDs", fileIDsInTrash).Info("deleting files")
	_, err = tx.ExecContext(ctx, `UPDATE trash SET is_deleted= true WHERE file_id = ANY ($1)`, pq.Array(fileIDsInTrash))
	if err != nil {
		if rollbackErr := tx.Rollback(); rollbackErr != nil {
			logrus.WithError(rollbackErr).Error("transaction rollback failed")
			return stacktrace.Propagate(rollbackErr, "")
		}
		return stacktrace.Propagate(err, "")
	}

	err = t.FileRepo.scheduleDeletion(ctx, tx, fileIDsInTrash, userID)
	if err != nil {
		if rollbackErr := tx.Rollback(); rollbackErr != nil {
			logrus.WithError(rollbackErr).Error("transaction rollback failed")
			return stacktrace.Propagate(rollbackErr, "")
		}
		return stacktrace.Propagate(err, "")
	}
	return tx.Commit()
}

// GetFilesInTrashState for a given userID and fileIDs, return the list of fileIDs which are actually present in
// trash and is not deleted or restored yet.
func (t *TrashRepository) GetFilesInTrashState(ctx context.Context, userID int64, fileIDs []int64) ([]int64, bool, error) {
	rows, err := t.DB.Query(`SELECT file_id FROM trash
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

// GetFilesInTrashOrDeleted returns the subset of fileIDs that are either in trash (not restored)
// or have been permanently deleted. This is useful for validation checks to prevent operations
// on files that are no longer in an active state.
// Unlike GetFilesInTrashState, this method does not log warnings when files are not found,
// making it suitable for validation checks where files are expected to NOT be in trash.
func (t *TrashRepository) GetFilesInTrashOrDeleted(ctx context.Context, userID int64, fileIDs []int64) ([]int64, error) {
	rows, err := t.DB.QueryContext(ctx, `SELECT file_id FROM trash
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

// verifyFilesAreDeleted for a given userID and fileIDs, this method verifies that given files are actually deleted
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

	// get the size of file from object_keys table
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

// GetFilesIDsForDeletion for given userID and lastUpdateAt timestamp, returns the fileIDs which are in trash and
// where last updated_at before lastUpdateAt timestamp.
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

// GetTimeStampForLatestNonDeletedEntry returns the updated at timestamp for the latest,non-deleted entry in the trash
func (t *TrashRepository) GetTimeStampForLatestNonDeletedEntry(userID int64) (*int64, error) {
	row := t.DB.QueryRow(`SELECT max(updated_at) FROM trash WHERE user_id = $1 AND is_deleted = FALSE AND is_restored = FALSE`, userID)
	var updatedAt *int64
	err := row.Scan(&updatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return updatedAt, stacktrace.Propagate(err, "")
}

// HasItems returns true if the user has any entries in trash.
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

// GetUserIDToFileIDsMapForDeletion returns map of userID to fileIds, where the file ids which should be deleted by now
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

// GetFileIdsForDroppingMetadata retrieves file IDs of deleted files for metadata scrubbing.
// It returns files that were deleted after the provided timestamp (sinceUpdatedAt) and have been in the trash for at least 50 days.
// This delay ensures compliance with deletion locks.
// The method orders the results by the 'updated_at' field in ascending order and limits the results to 'TrashDiffLimit' + 1.
// If multiple files have the same 'updated_at' timestamp and are at the limit boundary, they are excluded to prevent partial scrubbing.
//
// Parameters:
//
//	sinceUpdatedAt: The timestamp (in microseconds) to filter files that were deleted after this time.
//
// Returns:
//
//	A slice of FileWithUpdatedAt: Each item contains a file ID and its corresponding 'updated_at' timestamp.
//	error: If there is any issue in executing the query, an error is returned.
//
// Note: The method returns an empty slice if no matching files are found.
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

	// from the end ignore the fileIds from fileWithUpdatedAt that have the same updatedAt.
	// this is to avoid scrubbing partial list of files that have same updatedAt as due to the limit not
	// all files with the same updatedAt are returned.
	lastUpdatedAt := fileWithUpdatedAt[len(fileWithUpdatedAt)-1].UpdatedAt
	var i = len(fileWithUpdatedAt) - 1
	for ; i >= 0; i-- {
		if fileWithUpdatedAt[i].UpdatedAt != lastUpdatedAt {
			// found index (from end) where file's version is different from given version
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
