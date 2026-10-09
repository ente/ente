package repo

import (
	"context"
	"database/sql"
	"errors"
	"fmt"

	"github.com/ente/museum/ente"
	"github.com/ente/stacktrace"
	"github.com/lib/pq"
)

func (repo *CollectionRepository) GetCollectionFileIDs(collectionID int64, collectionOwnerID int64) ([]int64, error) {
	// Collaboration Todo: Filter out files which are not owned by the collection owner
	rows, err := repo.DB.Query(
		`SELECT file_id   
			FROM collection_files
			WHERE is_deleted=false
				AND collection_id =$1 AND (f_owner_id is null or f_owner_id = $2)`, collectionID, collectionOwnerID)
	if err != nil {
		return make([]int64, 0), stacktrace.Propagate(err, "")
	}
	return convertRowsToFileId(rows)
}

type CollectionFileState string

const (
	CollectionFileActive        CollectionFileState = "active"
	CollectionFileAbsent        CollectionFileState = "absent"
	CollectionFileDeleted       CollectionFileState = "deleted"
	CollectionFilePendingRemove CollectionFileState = "pending_remove"
)

func (repo *CollectionRepository) GetCollectionFileState(ctx context.Context, collectionID, fileID int64) (CollectionFileState, error) {
	var isDeleted, isPendingRemove bool
	err := repo.DB.QueryRowContext(ctx, `SELECT is_deleted, action IS NOT DISTINCT FROM $3 FROM collection_files WHERE collection_id = $1 AND file_id = $2`,
		collectionID, fileID, ente.ActionRemove).Scan(&isDeleted, &isPendingRemove)
	if errors.Is(err, sql.ErrNoRows) {
		return CollectionFileAbsent, nil
	}
	if err != nil {
		return CollectionFileAbsent, stacktrace.Propagate(err, "")
	}
	if isDeleted {
		return CollectionFileDeleted, nil
	}
	if isPendingRemove {
		return CollectionFilePendingRemove, nil
	}
	return CollectionFileActive, nil
}

func (repo *CollectionRepository) DoAllFilesExistInGivenCollections(fileIDs []int64, cIDs []int64) error {
	rows, err := repo.DB.Query(`
        SELECT DISTINCT file_id 
        FROM collection_files 
        WHERE file_id = ANY ($1) 
        AND is_deleted = false 
        AND action IS DISTINCT FROM $3
        AND collection_id = ANY ($2)`,
		pq.Array(fileIDs), pq.Array(cIDs), ente.ActionRemove)

	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	defer rows.Close()

	fileIDMap := make(map[int64]bool)
	for _, id := range fileIDs {
		fileIDMap[id] = false
	}
	for rows.Next() {
		var fileID int64
		if err := rows.Scan(&fileID); err != nil {
			return stacktrace.Propagate(err, "")
		}
		fileIDMap[fileID] = true
	}

	if err = rows.Err(); err != nil {
		return stacktrace.Propagate(err, "")
	}

	var missingFiles []int64
	for id, found := range fileIDMap {
		if !found {
			missingFiles = append(missingFiles, id)
		}
	}
	if len(missingFiles) > 0 {
		return stacktrace.Propagate(fmt.Errorf("missing files %v", missingFiles), "")
	}
	return nil
}

func (repo *CollectionRepository) VerifyAllFileIDsExistsInCollection(ctx context.Context, cID int64, fileIDs []int64) error {
	if len(fileIDs) == 0 {
		return nil
	}
	fileIdMap := make(map[int64]bool)
	rows, err := repo.DB.QueryContext(ctx, `SELECT file_id FROM collection_files WHERE collection_id = $1 AND is_deleted = $2 AND file_id = ANY ($3) AND action IS DISTINCT FROM $4`,
		cID, false, pq.Array(fileIDs), ente.ActionRemove)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	for rows.Next() {
		var fileID int64
		if err := rows.Scan(&fileID); err != nil {
			return stacktrace.Propagate(err, "")
		}
		fileIdMap[fileID] = true
	}
	if err := rows.Err(); err != nil {
		return stacktrace.Propagate(err, "")
	}
	for _, fileID := range fileIDs {
		if _, ok := fileIdMap[fileID]; !ok {
			return stacktrace.Propagate(ente.ErrPermissionDenied, "fileID %d not found in collection %d", fileID, cID)
		}
	}
	return nil
}

// FilterActiveFileIDsInCollection returns the fileIDs still active in the collection
// (not deleted and not marked for owner removal).
// If any fileID was never in the collection, it returns an error.
func (repo *CollectionRepository) FilterActiveFileIDsInCollection(ctx context.Context, cID int64, fileIDs []int64) ([]int64, error) {
	if len(fileIDs) == 0 {
		return []int64{}, nil
	}
	type fileState struct {
		isDeleted bool
		action    string
	}
	fileStates := make(map[int64]fileState)
	rows, err := repo.DB.QueryContext(ctx, `SELECT file_id, is_deleted, COALESCE(action, '') FROM collection_files WHERE collection_id = $1 AND file_id = ANY ($2)`,
		cID, pq.Array(fileIDs))
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	for rows.Next() {
		var fileID int64
		var isDeleted bool
		var action string
		if err := rows.Scan(&fileID, &isDeleted, &action); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		fileStates[fileID] = fileState{
			isDeleted: isDeleted,
			action:    action,
		}
	}
	if err := rows.Err(); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	missing := make([]int64, 0)
	active := make([]int64, 0, len(fileIDs))
	for _, fileID := range fileIDs {
		state, ok := fileStates[fileID]
		if !ok {
			missing = append(missing, fileID)
			continue
		}
		if !state.isDeleted && state.action != ente.ActionRemove {
			active = append(active, fileID)
		}
	}
	if len(missing) > 0 {
		return nil, stacktrace.Propagate(fmt.Errorf("fileIDs %v not found in collection %d", missing, cID), "")
	}
	return active, nil
}

func (repo *CollectionRepository) GetCollectionsFilesCount(collectionID int64) (int64, error) {
	row := repo.DB.QueryRow(`SELECT count(*) FROM collection_files WHERE collection_id=$1 AND is_deleted = false`, collectionID)
	var count int64 = 0
	err := row.Scan(&count)
	if err != nil {
		return -1, stacktrace.Propagate(err, "")
	}
	return count, nil
}

func (repo *CollectionRepository) GetCollectionCount(fileID int64) (int64, error) {
	row := repo.DB.QueryRow(`SELECT count(*) FROM collection_files WHERE file_id = $1 and is_deleted = false`, fileID)
	var count int64 = 0
	err := row.Scan(&count)
	if err != nil {
		return -1, stacktrace.Propagate(err, "")
	}
	return count, nil
}
