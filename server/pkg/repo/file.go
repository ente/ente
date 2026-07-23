package repo

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strconv"
	"strings"

	"github.com/ente/stacktrace"
	log "github.com/sirupsen/logrus"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/s3config"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/lib/pq"
)

// FileRepository is an implementation of the FileRepo that
// persists and retrieves data from disk.
type FileRepository struct {
	DB                *sql.DB
	S3Config          *s3config.S3Config
	QueueRepo         *QueueRepository
	ObjectRepo        *ObjectRepository
	ObjectCleanupRepo *ObjectCleanupRepository
	ObjectCopiesRepo  *ObjectCopiesRepository
	UsageRepo         *UsageRepository
}

// Create creates an entry in the database for the given file
func (repo *FileRepository) Create(
	file ente.File,
	fileSize int64,
	thumbnailSize int64,
	usageDiff int64,
	collectionOwnerID int64,
	app ente.App,
) (ente.File, int64, error) {
	hotDC := repo.S3Config.GetHotDataCenter()
	dcsForNewEntry := pq.StringArray{hotDC}

	ctx := context.Background()
	tx, err := repo.DB.BeginTx(ctx, nil)
	if err != nil {
		return file, -1, stacktrace.Propagate(err, "")
	}
	if file.OwnerID != collectionOwnerID {
		return file, -1, stacktrace.Propagate(errors.New("both file and collection should belong to same owner"), "")
	}
	var fileID int64
	err = tx.QueryRowContext(ctx, `INSERT INTO files
			(owner_id, encrypted_metadata,
			file_decryption_header, thumbnail_decryption_header, metadata_decryption_header,
			magic_metadata, pub_magic_metadata, info, updation_time)
			VALUES($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING file_id`,
		file.OwnerID, file.Metadata.EncryptedData, file.File.DecryptionHeader,
		file.Thumbnail.DecryptionHeader, file.Metadata.DecryptionHeader,
		file.MagicMetadata, file.PubicMagicMetadata, file.Info,
		file.UpdationTime).Scan(&fileID)
	if err != nil {
		tx.Rollback()
		return file, -1, stacktrace.Propagate(err, "")
	}
	file.ID = fileID
	_, err = tx.ExecContext(ctx, `INSERT INTO collection_files
			(collection_id, file_id, encrypted_key, key_decryption_nonce, is_deleted, updation_time, c_owner_id, f_owner_id)
			VALUES($1, $2, $3, $4, $5, $6, $7, $8)`, file.CollectionID, file.ID,
		file.EncryptedKey, file.KeyDecryptionNonce, false, file.UpdationTime, file.OwnerID, collectionOwnerID)
	if err != nil {
		tx.Rollback()
		return file, -1, stacktrace.Propagate(err, "")
	}
	_, err = tx.ExecContext(ctx, `UPDATE collections SET updation_time = $1
			WHERE collection_id = $2`, file.UpdationTime, file.CollectionID)
	if err != nil {
		tx.Rollback()
		return file, -1, stacktrace.Propagate(err, "")
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO object_keys(file_id, o_type, object_key, size, datacenters)
			VALUES($1, $2, $3, $4, $5)`, fileID, ente.FILE, file.File.ObjectKey, fileSize, dcsForNewEntry)
	if err != nil {
		tx.Rollback()
		if err.Error() == "pq: duplicate key value violates unique constraint \"object_keys_object_key_key\"" {
			return file, -1, ente.ErrDuplicateFileObjectFound
		}
		return file, -1, stacktrace.Propagate(err, "")
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO object_keys(file_id, o_type, object_key, size, datacenters)
			VALUES($1, $2, $3, $4, $5)`, fileID, ente.THUMBNAIL, file.Thumbnail.ObjectKey, thumbnailSize, dcsForNewEntry)
	if err != nil {
		tx.Rollback()
		if err.Error() == "pq: duplicate key value violates unique constraint \"object_keys_object_key_key\"" {
			return file, -1, ente.ErrDuplicateThumbnailObjectFound
		}
		return file, -1, stacktrace.Propagate(err, "")
	}

	err = repo.ObjectCleanupRepo.RemoveTempObjectKey(ctx, tx, file.File.ObjectKey, hotDC)
	if err != nil {
		tx.Rollback()
		return file, -1, stacktrace.Propagate(err, "")
	}
	err = repo.ObjectCleanupRepo.RemoveTempObjectKey(ctx, tx, file.Thumbnail.ObjectKey, hotDC)
	if err != nil {
		tx.Rollback()
		return file, -1, stacktrace.Propagate(err, "")
	}
	usage, err := repo.updateUsage(ctx, tx, file.OwnerID, usageDiff)
	if err != nil {
		tx.Rollback()
		return file, -1, stacktrace.Propagate(err, "")
	}

	err = repo.markAsNeedingReplication(ctx, tx, file, hotDC)
	if err != nil {
		tx.Rollback()
		return file, -1, stacktrace.Propagate(err, "")
	}

	err = tx.Commit()
	if err != nil {
		return file, -1, stacktrace.Propagate(err, "")
	}
	return file, usage, stacktrace.Propagate(err, "")
}

// CreateMetaFile creates an entry in the database for the given file
func (repo *FileRepository) CreateMetaFile(
	metaFile ente.MetaFile,
	collectionOwnerID int64,
	app ente.App,
) (*ente.File, error) {
	ctx := context.Background()
	tx, err := repo.DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	if metaFile.OwnerID != collectionOwnerID {
		return nil, stacktrace.Propagate(errors.New("both file and collection should belong to same owner"), "")
	}

	var fileID int64
	info := &ente.FileInfo{
		FileSize:      0,
		ThumbnailSize: 0,
	}
	err = tx.QueryRowContext(ctx, `INSERT INTO files
			(owner_id, encrypted_metadata,
			file_decryption_header, thumbnail_decryption_header, metadata_decryption_header,
			magic_metadata, pub_magic_metadata, info, updation_time)
			VALUES($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING file_id`,
		metaFile.OwnerID, metaFile.Metadata.EncryptedData, "",
		"", metaFile.Metadata.DecryptionHeader,
		metaFile.MagicMetadata, metaFile.PubicMagicMetadata, info,
		metaFile.UpdationTime).Scan(&fileID)
	if err != nil {
		tx.Rollback()
		return nil, stacktrace.Propagate(err, "")
	}

	_, err = tx.ExecContext(ctx, `INSERT INTO collection_files
			(collection_id, file_id, encrypted_key, key_decryption_nonce, is_deleted, updation_time, c_owner_id, f_owner_id)
			VALUES($1, $2, $3, $4, $5, $6, $7, $8)`, metaFile.CollectionID, fileID,
		metaFile.EncryptedKey, metaFile.KeyDecryptionNonce, false, metaFile.UpdationTime, metaFile.OwnerID, collectionOwnerID)
	if err != nil {
		tx.Rollback()
		return nil, stacktrace.Propagate(err, "")
	}
	_, err = tx.ExecContext(ctx, `UPDATE collections SET updation_time = $1
			WHERE collection_id = $2`, metaFile.UpdationTime, metaFile.CollectionID)
	if err != nil {
		tx.Rollback()
		return nil, stacktrace.Propagate(err, "")
	}
	err = tx.Commit()
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	var file ente.File = ente.File{
		ID:                 fileID,
		UpdationTime:       metaFile.UpdationTime,
		OwnerID:            metaFile.OwnerID,
		Metadata:           metaFile.Metadata,
		PubicMagicMetadata: metaFile.PubicMagicMetadata,
		MagicMetadata:      metaFile.MagicMetadata,
		EncryptedKey:       metaFile.EncryptedKey,
		KeyDecryptionNonce: metaFile.KeyDecryptionNonce,
		Info:               info,
		CollectionID:       metaFile.CollectionID,
	}
	return &file, stacktrace.Propagate(err, "")
}

// markAsNeedingReplication inserts new entries in object_copies, setting the
// current hot DC as the source copy.
//
// The higher layer above us (file controller) would've already checked that the
// object exists in the current hot DC (See `c.sizeOf` in file controller). This
// would cover cases where the client fetched presigned upload URLs for say
// hotDC1, but by the time they connected to museum, museum switched to using
// hotDC2. So then when museum would try to fetch the file size from hotDC2, the
// object won't be found there, and the upload would fail (which is the
// behaviour we want, since hot DC swaps are not a frequent/expected operation,
// we just wish to guarantee correctness if they do happen).
func (repo *FileRepository) markAsNeedingReplication(ctx context.Context, tx *sql.Tx, file ente.File, hotDC string) error {
	if hotDC == repo.S3Config.GetHotBackblazeDC() {
		err := repo.ObjectCopiesRepo.CreateNewB2Object(ctx, tx, file.File.ObjectKey, true, true)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
		err = repo.ObjectCopiesRepo.CreateNewB2Object(ctx, tx, file.Thumbnail.ObjectKey, true, false)
		return stacktrace.Propagate(err, "")
	} else if hotDC == repo.S3Config.GetHotWasabiDC() {
		err := repo.ObjectCopiesRepo.CreateNewWasabiObject(ctx, tx, file.File.ObjectKey, true, true)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
		err = repo.ObjectCopiesRepo.CreateNewWasabiObject(ctx, tx, file.Thumbnail.ObjectKey, true, false)
		return stacktrace.Propagate(err, "")
	} else {
		// Bail out if we're trying to add a new entry for a file but the
		// primary hot DC is not one of the known types.
		err := fmt.Errorf("only B2 and Wasabi DCs can be used for as the primary hot storage; instead, it was %s", hotDC)
		return stacktrace.Propagate(err, "")
	}
}

// See markAsNeedingReplication - this variant is for updating only thumbnails.
func (repo *FileRepository) markThumbnailAsNeedingReplication(ctx context.Context, tx *sql.Tx, thumbnailObjectKey string, hotDC string) error {
	if hotDC == repo.S3Config.GetHotBackblazeDC() {
		err := repo.ObjectCopiesRepo.CreateNewB2Object(ctx, tx, thumbnailObjectKey, true, false)
		return stacktrace.Propagate(err, "")
	} else if hotDC == repo.S3Config.GetHotWasabiDC() {
		err := repo.ObjectCopiesRepo.CreateNewWasabiObject(ctx, tx, thumbnailObjectKey, true, false)
		return stacktrace.Propagate(err, "")
	} else {
		// Bail out if we're trying to add a new entry for a file but the
		// primary hot DC is not one of the known types.
		err := fmt.Errorf("only B2 and Wasabi DCs can be used for as the primary hot storage; instead, it was %s", hotDC)
		return stacktrace.Propagate(err, "")
	}
}

// ResetNeedsReplication resets the replication status for an existing file
func (repo *FileRepository) ResetNeedsReplication(file ente.File, hotDC string) error {
	if hotDC == repo.S3Config.GetHotBackblazeDC() {
		err := repo.ObjectCopiesRepo.ResetNeedsWasabiReplication(file.File.ObjectKey)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
		err = repo.ObjectCopiesRepo.ResetNeedsScalewayReplication(file.File.ObjectKey)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}

		err = repo.ObjectCopiesRepo.ResetNeedsWasabiReplication(file.Thumbnail.ObjectKey)
		return stacktrace.Propagate(err, "")
	} else if hotDC == repo.S3Config.GetHotWasabiDC() {
		err := repo.ObjectCopiesRepo.ResetNeedsB2Replication(file.File.ObjectKey)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
		err = repo.ObjectCopiesRepo.ResetNeedsScalewayReplication(file.File.ObjectKey)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}

		err = repo.ObjectCopiesRepo.ResetNeedsB2Replication(file.Thumbnail.ObjectKey)
		return stacktrace.Propagate(err, "")
	} else {
		// Bail out if we're trying to update the replication flags but the
		// primary hot DC is not one of the known types.
		err := fmt.Errorf("only B2 and Wasabi DCs can be used for as the primary hot storage; instead, it was %s", hotDC)
		return stacktrace.Propagate(err, "")
	}
}

// Update updates the entry in the database for the given file
func (repo *FileRepository) Update(file ente.File, fileSize int64, thumbnailSize int64, usageDiff int64, oldObjects []string, isDuplicateRequest bool) error {
	hotDC := repo.S3Config.GetHotDataCenter()
	dcsForNewEntry := pq.StringArray{hotDC}

	ctx := context.Background()
	tx, err := repo.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	_, err = tx.ExecContext(ctx, `UPDATE files SET encrypted_metadata = $1,
			file_decryption_header = $2, thumbnail_decryption_header = $3, 
			metadata_decryption_header = $4, updation_time = $5 , info = $6 WHERE file_id = $7`,
		file.Metadata.EncryptedData, file.File.DecryptionHeader,
		file.Thumbnail.DecryptionHeader, file.Metadata.DecryptionHeader,
		file.UpdationTime, file.Info, file.ID)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	updatedRows, err := tx.QueryContext(ctx, `UPDATE collection_files 
			SET updation_time = $1 WHERE file_id = $2 RETURNING collection_id`, file.UpdationTime,
		file.ID)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	defer updatedRows.Close()
	updatedCIDs := make([]int64, 0)
	for updatedRows.Next() {
		var cID int64
		err := updatedRows.Scan(&cID)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
		updatedCIDs = append(updatedCIDs, cID)
	}
	_, err = tx.ExecContext(ctx, `UPDATE collections SET updation_time = $1
			WHERE collection_id = ANY($2)`, file.UpdationTime, pq.Array(updatedCIDs))
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	_, err = tx.ExecContext(ctx, `DELETE FROM object_copies WHERE object_key = ANY($1)`,
		pq.Array(oldObjects))
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	_, err = tx.ExecContext(ctx, `UPDATE object_keys 
			SET object_key = $1, size = $2, datacenters = $3 WHERE file_id = $4 AND o_type = $5`,
		file.File.ObjectKey, fileSize, dcsForNewEntry, file.ID, ente.FILE)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	_, err = tx.ExecContext(ctx, `UPDATE object_keys 
			SET object_key = $1, size = $2, datacenters = $3 WHERE file_id = $4 AND o_type = $5`,
		file.Thumbnail.ObjectKey, thumbnailSize, dcsForNewEntry, file.ID, ente.THUMBNAIL)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	_, err = repo.updateUsage(ctx, tx, file.OwnerID, usageDiff)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	err = repo.ObjectCleanupRepo.RemoveTempObjectKey(ctx, tx, file.File.ObjectKey, hotDC)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	err = repo.ObjectCleanupRepo.RemoveTempObjectKey(ctx, tx, file.Thumbnail.ObjectKey, hotDC)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	if isDuplicateRequest {
		// Skip markAsNeedingReplication for duplicate requests, it'd fail with
		//     pq: duplicate key value violates unique constraint \"object_copies_pkey\"
		// and render our transaction uncommittable
		log.Infof("Skipping update of object_copies for a duplicate request to update file %d", file.ID)
	} else {
		err = repo.markAsNeedingReplication(ctx, tx, file, hotDC)
		if err != nil {
			tx.Rollback()
			return stacktrace.Propagate(err, "")
		}
	}
	err = repo.QueueRepo.AddItems(ctx, tx, OutdatedObjectsQueue, oldObjects)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	err = tx.Commit()
	return stacktrace.Propagate(err, "")
}

// UpdateMagicAttributes updates the magic attributes for the list of files and update collection_files & collection
// which have this file.
func (repo *FileRepository) UpdateMagicAttributes(
	ctx context.Context,
	fileUpdates []ente.UpdateMagicMetadata,
	isPublicMetadata bool,
	skipVersion *bool,
) error {
	updationTime := time.Microseconds()
	tx, err := repo.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	fileIDs := make([]int64, 0)
	for _, update := range fileUpdates {
		update.MagicMetadata.Version = update.MagicMetadata.Version + 1
		fileIDs = append(fileIDs, update.ID)
		if isPublicMetadata {
			_, err = tx.ExecContext(ctx, `UPDATE files SET pub_magic_metadata = $1,  updation_time = $2 WHERE file_id = $3`,
				update.MagicMetadata, updationTime, update.ID)
		} else {
			_, err = tx.ExecContext(ctx, `UPDATE files SET magic_metadata = $1,  updation_time = $2 WHERE file_id = $3`,
				update.MagicMetadata, updationTime, update.ID)
		}
		if err != nil {
			if rollbackErr := tx.Rollback(); rollbackErr != nil {
				log.WithError(rollbackErr).Error("transaction rollback failed")
				return stacktrace.Propagate(rollbackErr, "")
			}
			return stacktrace.Propagate(err, "")
		}
	}
	if skipVersion != nil && *skipVersion {
		return tx.Commit()
	}
	// todo: full table scan, need to add index (for discussion: add user_id and idx {user_id, file_id}).
	updatedRows, err := tx.QueryContext(ctx, `UPDATE collection_files 
			SET updation_time = $1 WHERE file_id = ANY($2) AND is_deleted= false RETURNING collection_id`, updationTime,
		pq.Array(fileIDs))
	if err != nil {
		if rollbackErr := tx.Rollback(); rollbackErr != nil {
			log.WithError(rollbackErr).Error("transaction rollback failed")
			return stacktrace.Propagate(rollbackErr, "")
		}
		return stacktrace.Propagate(err, "")
	}
	defer updatedRows.Close()
	updatedCIDs := make([]int64, 0)
	for updatedRows.Next() {
		var cID int64
		err := updatedRows.Scan(&cID)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
		updatedCIDs = append(updatedCIDs, cID)
	}
	_, err = tx.ExecContext(ctx, `UPDATE collections SET updation_time = $1
			WHERE collection_id = ANY($2)`, updationTime, pq.Array(updatedCIDs))
	if err != nil {
		if rollbackErr := tx.Rollback(); rollbackErr != nil {
			log.WithError(rollbackErr).Error("transaction rollback failed")
			return stacktrace.Propagate(rollbackErr, "")
		}
		return stacktrace.Propagate(err, "")
	}
	return tx.Commit()
}

// Update updates the entry in the database for the given file
func (repo *FileRepository) UpdateThumbnail(ctx context.Context, fileID int64, userID int64, thumbnail ente.FileAttributes, thumbnailSize int64, usageDiff int64, oldThumbnailObject *string) error {
	hotDC := repo.S3Config.GetHotDataCenter()
	dcsForNewEntry := pq.StringArray{hotDC}

	tx, err := repo.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	updationTime := time.Microseconds()
	_, err = tx.ExecContext(ctx, `UPDATE files SET 
			thumbnail_decryption_header = $1, 
			updation_time = $2 WHERE file_id = $3`,
		thumbnail.DecryptionHeader,
		updationTime, fileID)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	updatedRows, err := tx.QueryContext(ctx, `UPDATE collection_files 
			SET updation_time = $1 WHERE file_id = $2 RETURNING collection_id`, updationTime,
		fileID)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	defer updatedRows.Close()
	updatedCIDs := make([]int64, 0)
	for updatedRows.Next() {
		var cID int64
		err := updatedRows.Scan(&cID)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
		updatedCIDs = append(updatedCIDs, cID)
	}
	_, err = tx.ExecContext(ctx, `UPDATE collections SET updation_time = $1
			WHERE collection_id = ANY($2)`, updationTime, pq.Array(updatedCIDs))
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	if oldThumbnailObject != nil {
		_, err = tx.ExecContext(ctx, `DELETE FROM object_copies WHERE object_key = $1`,
			*oldThumbnailObject)
		if err != nil {
			tx.Rollback()
			return stacktrace.Propagate(err, "")
		}
	}
	_, err = tx.ExecContext(ctx, `UPDATE object_keys 
			SET object_key = $1, size = $2, datacenters = $3 WHERE file_id = $4 AND o_type = $5`,
		thumbnail.ObjectKey, thumbnailSize, dcsForNewEntry, fileID, ente.THUMBNAIL)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	_, err = repo.updateUsage(ctx, tx, userID, usageDiff)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}

	err = repo.ObjectCleanupRepo.RemoveTempObjectKey(ctx, tx, thumbnail.ObjectKey, hotDC)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	err = repo.markThumbnailAsNeedingReplication(ctx, tx, thumbnail.ObjectKey, hotDC)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if oldThumbnailObject != nil {
		err = repo.QueueRepo.AddItems(ctx, tx, OutdatedObjectsQueue, []string{*oldThumbnailObject})
		if err != nil {
			tx.Rollback()
			return stacktrace.Propagate(err, "")
		}
	}
	err = tx.Commit()
	return stacktrace.Propagate(err, "")
}

// GetOwnerID returns the ownerID for a file
func (repo *FileRepository) GetOwnerID(fileID int64) (int64, error) {
	row := repo.DB.QueryRow(`SELECT owner_id FROM files WHERE file_id = $1`,
		fileID)
	var ownerID int64
	err := row.Scan(&ownerID)
	return ownerID, stacktrace.Propagate(err, "failed to get file owner")
}

// GetOwnerToFileCountMap will return a map of ownerId & number of files owned by that owner
func (repo *FileRepository) GetOwnerToFileCountMap(ctx context.Context, fileIDs []int64) (map[int64]int64, error) {
	rows, err := repo.DB.QueryContext(ctx, `SELECT owner_id, count(*) FROM files WHERE file_id = ANY($1) group by owner_id`,
		pq.Array(fileIDs))
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	result := make(map[int64]int64, 0)
	for rows.Next() {
		var ownerID, count int64
		if err = rows.Scan(&ownerID, &count); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		result[ownerID] = count
	}
	return result, nil
}

// GetOwnerToFileIDsMap will return a map of ownerId & number of files owned by that owner
func (repo *FileRepository) GetOwnerToFileIDsMap(ctx context.Context, fileIDs []int64) (map[int64][]int64, error) {
	rows, err := repo.DB.QueryContext(ctx, `SELECT owner_id, file_id FROM files WHERE file_id = ANY($1)`,
		pq.Array(fileIDs))
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	result := make(map[int64][]int64, 0)
	for rows.Next() {
		var ownerID, fileID int64
		if err = rows.Scan(&ownerID, &fileID); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		if ownerFileIDs, ok := result[ownerID]; ok {
			result[ownerID] = append(ownerFileIDs, fileID)
		} else {
			result[ownerID] = []int64{fileID}
		}
	}
	return result, nil
}
func (repo *FileRepository) VerifyFileOwner(ctx context.Context, fileIDs []int64, ownerID int64, logger *log.Entry) error {
	countMap, err := repo.GetOwnerToFileCountMap(ctx, fileIDs)
	if err != nil {
		return stacktrace.Propagate(err, "failed to get owners info")
	}
	logger = logger.WithFields(log.Fields{
		"owner_id":   ownerID,
		"file_ids":   fileIDs,
		"owners_map": countMap,
	})
	if len(countMap) == 0 {
		logger.Error("all fileIDs are invalid")
		return stacktrace.Propagate(ente.ErrBadRequest, "")
	}
	if len(countMap) > 1 {
		logger.Error("files are owned by multiple users")
		return stacktrace.Propagate(ente.ErrPermissionDenied, "")
	}
	if filesOwned, ok := countMap[ownerID]; ok {
		if filesOwned != int64(len(fileIDs)) {
			logger.WithField("file_owned", filesOwned).Error("failed to find all fileIDs")
			return stacktrace.Propagate(ente.ErrBadRequest, "")
		}
		return nil
	} else {
		logger.Error("user is not an owner of any file")
		return stacktrace.Propagate(ente.ErrPermissionDenied, "")
	}
}

// GetOwnerAndMagicMetadata returns the ownerID and magicMetadata for given file id
func (repo *FileRepository) GetOwnerAndMagicMetadata(fileID int64, publicMetadata bool) (int64, *ente.MagicMetadata, error) {
	var row *sql.Row
	if publicMetadata {
		row = repo.DB.QueryRow(`SELECT owner_id, pub_magic_metadata FROM files WHERE file_id = $1`,
			fileID)
	} else {
		row = repo.DB.QueryRow(`SELECT owner_id, magic_metadata FROM files WHERE file_id = $1`,
			fileID)
	}
	var ownerID int64
	var magicMetadata *ente.MagicMetadata
	err := row.Scan(&ownerID, &magicMetadata)
	return ownerID, magicMetadata, stacktrace.Propagate(err, "")
}

// GetSize returns the size of files indicated by fileIDs that are owned by the given userID.
func (repo *FileRepository) GetSize(userID int64, fileIDs []int64) (int64, error) {
	row := repo.DB.QueryRow(`
			SELECT COALESCE(SUM(size), 0) FROM object_keys WHERE o_type = 'file' AND is_deleted = false AND file_id = ANY(SELECT file_id FROM files WHERE (file_id = ANY($1) AND owner_id = $2))`,
		pq.Array(fileIDs), userID)
	var size int64
	err := row.Scan(&size)
	if err != nil {
		return -1, stacktrace.Propagate(err, "")
	}
	return size, nil
}

// GetFileCountForUser returns the total number of files in the system for a given user.
func (repo *FileRepository) GetFileCountForUser(userID int64, app ente.App) (int64, error) {
	row := repo.DB.QueryRow(`SELECT count(distinct files.file_id)  
			FROM collection_files
			JOIN collections c on c.owner_id = $1 and c.collection_id = collection_files.collection_id 
			JOIN files ON 
			files.owner_id = $1 AND files.file_id = collection_files.file_id
			WHERE (c.app = $2 AND collection_files.is_deleted = false);`, userID, app)

	var fileCount int64
	err := row.Scan(&fileCount)
	if err != nil {
		return -1, stacktrace.Propagate(err, "")
	}
	return fileCount, nil
}

func (repo *FileRepository) GetFileAttributesFromObjectKey(objectKey string) (ente.File, error) {
	s3ObjectKeys, err := repo.ObjectRepo.GetAllFileObjectsByObjectKey(objectKey)
	if err != nil {
		return ente.File{}, stacktrace.Propagate(err, "")
	}
	if len(s3ObjectKeys) != 2 {
		return ente.File{}, stacktrace.Propagate(fmt.Errorf("unexpected file count: %d", len(s3ObjectKeys)), "")
	}

	var file ente.File
	file.ID = s3ObjectKeys[0].FileID // all file IDs should be same as per query in GetAllFileObjectsByObjectKey
	row := repo.DB.QueryRow(`SELECT owner_id, file_decryption_header, thumbnail_decryption_header, metadata_decryption_header, encrypted_metadata FROM files WHERE file_id = $1`, file.ID)
	err = row.Scan(&file.OwnerID,
		&file.File.DecryptionHeader, &file.Thumbnail.DecryptionHeader,
		&file.Metadata.DecryptionHeader,
		&file.Metadata.EncryptedData)
	if err != nil {
		return ente.File{}, err
	}
	for _, object := range s3ObjectKeys {
		if object.Type == ente.FILE {
			file.File.ObjectKey = object.ObjectKey
			file.File.Size = object.FileSize
		} else if object.Type == ente.THUMBNAIL {
			file.Thumbnail.ObjectKey = object.ObjectKey
			file.Thumbnail.Size = object.FileSize
		} else {
			err = fmt.Errorf("unexpted file type %s", object.Type)
			return ente.File{}, stacktrace.Propagate(err, "")
		}
	}
	return file, nil
}

func (repo *FileRepository) GetFileAttributesForCopy(fileIDs []int64) ([]ente.File, error) {
	result := make([]ente.File, 0)
	rows, err := repo.DB.Query(`SELECT file_id, owner_id, file_decryption_header, thumbnail_decryption_header, metadata_decryption_header, encrypted_metadata, pub_magic_metadata FROM files WHERE file_id = ANY($1)`, pq.Array(fileIDs))
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	for rows.Next() {
		var file ente.File
		err := rows.Scan(&file.ID, &file.OwnerID, &file.File.DecryptionHeader, &file.Thumbnail.DecryptionHeader, &file.Metadata.DecryptionHeader, &file.Metadata.EncryptedData, &file.PubicMagicMetadata)
		if err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		result = append(result, file)
	}
	return result, nil
}

func (repo *FileRepository) GetFileAttributes(fileID int64) (*ente.File, error) {
	rows := repo.DB.QueryRow(`SELECT file_id, owner_id, file_decryption_header, thumbnail_decryption_header, metadata_decryption_header, encrypted_metadata, pub_magic_metadata, info FROM files WHERE file_id = $1`, fileID)
	var file ente.File
	err := rows.Scan(&file.ID, &file.OwnerID, &file.File.DecryptionHeader, &file.Thumbnail.DecryptionHeader, &file.Metadata.DecryptionHeader, &file.Metadata.EncryptedData, &file.PubicMagicMetadata, &file.Info)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &file, nil
}

// GetUsage  gets the Storage usage of a user
// Deprecated: GetUsage is deprecated, use UsageRepository.GetUsage
func (repo *FileRepository) GetUsage(userID int64) (int64, error) {
	return repo.UsageRepo.GetUsage(userID)
}

func (repo *FileRepository) DropFilesMetadata(ctx context.Context, fileIDs []int64) error {
	// ensure that the fileIDs are not present in object_keys
	rows, err := repo.DB.QueryContext(ctx, `SELECT distinct(file_id) FROM object_keys WHERE file_id = ANY($1)`, pq.Array(fileIDs))
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	fileIdsNotDeleted := make([]int64, 0)
	for rows.Next() {
		var fileID int64
		err := rows.Scan(&fileID)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
		fileIdsNotDeleted = append(fileIdsNotDeleted, fileID)
	}
	if len(fileIdsNotDeleted) > 0 {
		return stacktrace.Propagate(fmt.Errorf("fileIDs %v are still present in object_keys", fileIdsNotDeleted), "")
	}
	_, err = repo.DB.ExecContext(ctx, `
			UPDATE files SET encrypted_metadata = '-', 
			                 metadata_decryption_header = '-',
			                 file_decryption_header = '-', 
			                 thumbnail_decryption_header = '-',
			                 magic_metadata = NULL,
			                 pub_magic_metadata = NULL,
			                 info = NULL
             where file_id = ANY($1)`, pq.Array(fileIDs))
	return stacktrace.Propagate(err, "")
}

// GetDuplicateFiles returns the list of files for a user that are of the same size
func (repo *FileRepository) GetDuplicateFiles(userID int64) ([]ente.DuplicateFiles, error) {
	rows, err := repo.DB.Query(`SELECT string_agg(o.file_id::character varying, ','), o.size FROM object_keys o JOIN files f ON f.file_id = o.file_id
											WHERE f.owner_id = $1 AND o.o_type = 'file' AND o.is_deleted = false
											GROUP BY size 
											HAVING count(*) > 1;`, userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	result := make([]ente.DuplicateFiles, 0)
	for rows.Next() {
		var res string
		var size int64
		err := rows.Scan(&res, &size)
		if err != nil {
			return result, stacktrace.Propagate(err, "")
		}
		fileIDs := make([]int64, 0)
		for fileIDStr := range strings.SplitSeq(res, ",") {
			fileID, err := strconv.ParseInt(fileIDStr, 10, 64)
			if err != nil {
				return result, stacktrace.Propagate(err, "")
			}
			fileIDs = append(fileIDs, fileID)
		}
		result = append(result, ente.DuplicateFiles{FileIDs: fileIDs, Size: size})
	}
	return result, nil
}

func (repo *FileRepository) GetTotalFileCount() (int64, error) {
	// 9,522,438 is the magic number that accommodates the bumping up of fileIDs
	// Doing this magic instead of count(*) since it's faster
	row := repo.DB.QueryRow(`select (select max(file_id) from files) - (select 9522438)`)
	var count int64
	err := row.Scan(&count)
	return count, stacktrace.Propagate(err, "")
}

func convertRowsToFiles(rows *sql.Rows) ([]ente.File, error) {
	defer rows.Close()
	files := make([]ente.File, 0)
	for rows.Next() {
		var (
			file         ente.File
			updationTime float64
			actionUser   sql.NullInt64
			action       sql.NullString
			addedAt      sql.NullInt64
		)
		err := rows.Scan(&file.ID, &file.OwnerID, &file.CollectionID, &file.CollectionOwnerID,
			&file.EncryptedKey, &file.KeyDecryptionNonce,
			&file.File.DecryptionHeader, &file.Thumbnail.DecryptionHeader,
			&file.Metadata.DecryptionHeader,
			&file.Metadata.EncryptedData, &file.MagicMetadata, &file.PubicMagicMetadata,
			&file.Info, &actionUser, &action, &file.IsDeleted, &updationTime, &addedAt)
		if err != nil {
			return files, stacktrace.Propagate(err, "")
		}
		if actionUser.Valid {
			v := actionUser.Int64
			file.ActionUserID = &v
		}
		if action.Valid {
			v := action.String
			file.Action = &v
		}
		file.UpdationTime = int64(updationTime)
		if addedAt.Valid {
			v := addedAt.Int64
			file.CollectionAddedAt = &v
		}
		files = append(files, file)
	}
	return files, nil
}

// scheduleDeletion added a list of files's object ids to delete queue for deletion from datastore
func (repo *FileRepository) scheduleDeletion(ctx context.Context, tx *sql.Tx, fileIDs []int64, userID int64) error {
	diff := int64(0)

	objectsToBeDeleted, err := repo.ObjectRepo.MarkObjectsAsDeletedForFileIDs(ctx, tx, fileIDs)
	if err != nil {
		return stacktrace.Propagate(err, "file object deletion failed for fileIDs: %v", fileIDs)
	}
	totalObjectSize := int64(0)
	for _, object := range objectsToBeDeleted {
		totalObjectSize += object.FileSize
	}
	diff = diff - (totalObjectSize)
	_, err = repo.updateUsage(ctx, tx, userID, diff)
	return stacktrace.Propagate(err, "")
}

// updateUsage updates the storage usage of a user and returns the updated value
func (repo *FileRepository) updateUsage(ctx context.Context, tx *sql.Tx, userID int64, diff int64) (int64, error) {
	row := tx.QueryRowContext(ctx, `SELECT storage_consumed FROM usage WHERE user_id = $1 FOR UPDATE`, userID)
	var usage int64
	err := row.Scan(&usage)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			usage = 0
		} else {
			return -1, stacktrace.Propagate(err, "")
		}
	}
	newUsage := usage + diff
	_, err = tx.ExecContext(ctx, `INSERT INTO usage (user_id, storage_consumed)
			VALUES ($1, $2)
			ON CONFLICT (user_id) DO UPDATE
				SET storage_consumed = $2`,
		userID, newUsage)
	if err != nil {
		return -1, stacktrace.Propagate(err, "")
	}
	return newUsage, nil
}
