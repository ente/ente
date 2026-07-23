package repo

import (
	"context"
	"database/sql"
	"errors"
	"fmt"

	"github.com/ente/stacktrace"
	log "github.com/sirupsen/logrus"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/time"
)

// ObjectCleanupRepository maintains state related to objects that might need to
// be cleaned up.
//
// In particular, all presigned urls start their life as a "temp object" that is
// liable to be cleaned up if not marked as a successful upload by the client.
type ObjectCleanupRepository struct {
	DB *sql.DB
}

// AddTempObject persists a given object identifier and it's expirationTime
func (repo *ObjectCleanupRepository) AddTempObject(tempObject ente.TempObject, expirationTime int64) error {
	var err error
	if tempObject.IsMultipart {
		_, err = repo.DB.Exec(`INSERT INTO temp_objects(object_key, expiration_time,upload_id,is_multipart, bucket_id)
		VALUES($1, $2, $3, $4, $5)`, tempObject.ObjectKey, expirationTime, tempObject.UploadID, tempObject.IsMultipart, tempObject.BucketId)
	} else {
		_, err = repo.DB.Exec(`INSERT INTO temp_objects(object_key, expiration_time, bucket_id)
		VALUES($1, $2, $3)`, tempObject.ObjectKey, expirationTime, tempObject.BucketId)
	}
	return stacktrace.Propagate(err, "")
}

// RemoveTempObjectKey removes a TempObject identified by its key and datacenter
func (repo *ObjectCleanupRepository) RemoveTempObjectKey(ctx context.Context, tx *sql.Tx, objectKey string, dc string) error {
	_, err := tx.ExecContext(ctx, `DELETE FROM temp_objects WHERE object_key = $1`, objectKey)
	return stacktrace.Propagate(err, "")
}

// RemoveTempObjectFromDC will also return how many rows were affected
func (repo *ObjectCleanupRepository) RemoveTempObjectFromDC(ctx context.Context, tx *sql.Tx, objectKey string, dc string) error {
	res, err := tx.ExecContext(ctx, `DELETE FROM temp_objects WHERE object_key = $1 and bucket_id = $2`, objectKey, dc)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	rowsAffected, err := res.RowsAffected()
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if rowsAffected != 1 {
		return stacktrace.Propagate(fmt.Errorf("only one row should be affected not %d", rowsAffected), "")
	}
	return nil
}

func (repo *ObjectCleanupRepository) DoesTempObjectExist(ctx context.Context, objectKey string, uploadID string) (bool, error) {
	var exists bool
	query := `SELECT EXISTS(SELECT 1 FROM temp_objects WHERE object_key = $1 AND upload_id = $2)`
	err := repo.DB.QueryRowContext(ctx, query, objectKey, uploadID).Scan(&exists)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return false, nil
		}
		return false, stacktrace.Propagate(err, "failed to check if temp object exists")
	}
	return exists, nil
}

// GetExpiredObjects returns the list of object keys that have expired
func (repo *ObjectCleanupRepository) GetAndLockExpiredObjects() (*sql.Tx, []ente.TempObject, error) {
	tx, err := repo.DB.Begin()
	if err != nil {
		return nil, nil, stacktrace.Propagate(err, "")
	}

	rollback := func() {
		rerr := tx.Rollback()
		if rerr != nil {
			log.Errorf("Ignoring error when rolling back transaction: %s", rerr)
		}
	}

	commit := func() {
		cerr := tx.Commit()
		if cerr != nil {
			log.Errorf("Ignoring error when committing transaction: %s", cerr)
		}
	}

	rows, err := tx.Query(`
	SELECT object_key, is_multipart, upload_id, bucket_id FROM temp_objects
	WHERE expiration_time <= $1
	LIMIT 1000
	FOR UPDATE SKIP LOCKED
	`, time.Microseconds())

	if err != nil && errors.Is(err, sql.ErrNoRows) {
		commit()
		return nil, nil, err
	}

	if err != nil {
		rollback()
		return nil, nil, stacktrace.Propagate(err, "")
	}

	defer rows.Close()
	tempObjects := make([]ente.TempObject, 0)
	for rows.Next() {
		var tempObject ente.TempObject
		var uploadID sql.NullString
		var bucketID sql.NullString
		err := rows.Scan(&tempObject.ObjectKey, &tempObject.IsMultipart, &uploadID, &bucketID)
		if err != nil {
			rollback()
			return nil, nil, stacktrace.Propagate(err, "")
		}
		if tempObject.IsMultipart {
			tempObject.UploadID = uploadID.String
		}
		if bucketID.Valid {
			tempObject.BucketId = bucketID.String
		}
		tempObjects = append(tempObjects, tempObject)
	}
	return tx, tempObjects, nil
}

// SetExpiryForTempObject sets the expiration_time for TempObject
func (repo *ObjectCleanupRepository) SetExpiryForTempObject(tx *sql.Tx, tempObject ente.TempObject, expirationTime int64) error {
	if tempObject.IsMultipart {
		_, err := tx.Exec(`
			UPDATE temp_objects SET expiration_time = $1 WHERE object_key = $2 AND upload_id = $3
			`, expirationTime, tempObject.ObjectKey, tempObject.UploadID)
		return stacktrace.Propagate(err, "")
	} else {
		_, err := tx.Exec(`
			UPDATE temp_objects SET expiration_time = $1 WHERE object_key = $2
			`, expirationTime, tempObject.ObjectKey)
		return stacktrace.Propagate(err, "")
	}
}

// RemoveTempObject removes a given TempObject
func (repo *ObjectCleanupRepository) RemoveTempObject(tx *sql.Tx, tempObject ente.TempObject) error {
	if tempObject.IsMultipart {
		_, err := tx.Exec(`
			DELETE FROM temp_objects WHERE object_key = $1 AND upload_id = $2
			`, tempObject.ObjectKey, tempObject.UploadID)
		return stacktrace.Propagate(err, "")
	} else {
		_, err := tx.Exec(`
			DELETE FROM temp_objects WHERE object_key = $1
			`, tempObject.ObjectKey)
		return stacktrace.Propagate(err, "")
	}
}
