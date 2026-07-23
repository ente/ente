package repo

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/ente/base"
	"github.com/ente/stacktrace"
	"github.com/lib/pq"
)

type CollectionActionsRepository struct {
	DB *sql.DB
}

func (r *CollectionActionsRepository) Create(ctx context.Context, userID int64, actorUserID int64, collectionID int64, fileID *int64, data map[string]interface{}, action string, isPending bool, now int64) (string, error) {
	id := base.MustNewID("cact")
	payload, err := marshalCollectionActionData(data)
	if err != nil {
		return "", err
	}
	_, err = r.DB.ExecContext(ctx, `INSERT INTO collection_actions(id, user_id, actor_user_id, collection_id, file_id, data, action, is_pending, created_at, updated_at)
            VALUES($1, $2, $3, $4, $5, $6, $7, $8, $9, $9)`, id, userID, actorUserID, collectionID, fileID, payload, action, isPending, now)
	return id, stacktrace.Propagate(err, "")
}

// CreateBulk inserts multiple collection actions that only differ by fileID.
func (r *CollectionActionsRepository) CreateBulk(ctx context.Context, userID int64, actorUserID int64, collectionID int64, fileIDs []int64, data map[string]interface{}, action string, isPending bool) error {
	if len(fileIDs) == 0 {
		return nil
	}
	if actorUserID == userID {
		return fmt.Errorf("actor %d and target user id %d should be different", actorUserID, userID)
	}
	payload, err := marshalCollectionActionData(data)
	if err != nil {
		return err
	}
	valueStrings := make([]string, 0, len(fileIDs))
	args := make([]interface{}, 0, len(fileIDs)*8)
	for i := range fileIDs {
		id := base.MustNewID("cact")
		fileID := fileIDs[i]
		idx := i*8 + 1
		valueStrings = append(valueStrings, fmt.Sprintf("($%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d)",
			idx, idx+1, idx+2, idx+3, idx+4, idx+5, idx+6, idx+7))
		args = append(args, id, userID, actorUserID, collectionID, fileID, payload, action, isPending)
	}
	query := fmt.Sprintf(`INSERT INTO collection_actions(id, user_id, actor_user_id, collection_id, file_id, data, action, is_pending) VALUES %s`, strings.Join(valueStrings, ","))
	_, err = r.DB.ExecContext(ctx, query, args...)
	return stacktrace.Propagate(err, "")
}

func (r *CollectionActionsRepository) ListPendingRemoveActions(ctx context.Context, userID int64, updatedAfter int64, limit int) ([]ente.CollectionAction, error) {
	rows, err := r.DB.QueryContext(ctx, `SELECT ca.id, ca.user_id, ca.actor_user_id, ca.collection_id, ca.file_id, ca.data, ca.action, ca.is_pending, ca.created_at, ca.updated_at,
	        (cf.collection_id IS NOT NULL) AS is_valid
	    FROM collection_actions ca
	    LEFT JOIN collection_files cf
	        ON cf.collection_id = ca.collection_id
	        AND cf.file_id = ca.file_id
	        AND cf.is_deleted = false
	        AND cf.action = $2
	    WHERE ca.user_id = $1
	        AND ca.action = $2
	        AND ca.is_pending = true
	        AND ca.updated_at > $3
	    ORDER BY ca.updated_at
	    LIMIT $4`, userID, ente.ActionRemove, updatedAfter, limit)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	result := make([]ente.CollectionAction, 0)
	staleActionIDs := make([]string, 0)
	for rows.Next() {
		var (
			ca      ente.CollectionAction
			data    []byte
			fileID  sql.NullInt64
			isValid bool
		)
		if err := rows.Scan(&ca.ID, &ca.UserID, &ca.ActorUserID, &ca.CollectionID, &fileID, &data, &ca.Action, &ca.IsPending, &ca.CreatedAt, &ca.UpdatedAt, &isValid); err != nil {
			return result, stacktrace.Propagate(err, "")
		}
		if fileID.Valid {
			v := fileID.Int64
			ca.FileID = &v
		}
		if len(data) > 0 {
			var m map[string]interface{}
			if err := json.Unmarshal(data, &m); err != nil {
				return result, stacktrace.Propagate(err, "failed to unmarshal data")
			}
			ca.Data = m
		}
		if !isValid {
			staleActionIDs = append(staleActionIDs, ca.ID)
			continue
		}
		result = append(result, ca)
	}
	if len(staleActionIDs) > 0 {
		if err := r.resetPendingForActions(ctx, staleActionIDs); err != nil {
			return result, stacktrace.Propagate(err, "failed to reset stale pending actions")
		}
	}
	return result, nil
}

func (r *CollectionActionsRepository) ListPendingDeleteSuggestions(ctx context.Context, userID int64, updatedAfter int64, limit int) ([]ente.CollectionAction, error) {
	rows, err := r.DB.QueryContext(ctx, `SELECT ca.id, ca.user_id, ca.actor_user_id, ca.collection_id, ca.file_id, ca.data, ca.action, ca.is_pending, ca.created_at, ca.updated_at,
	        f.owner_id,
	        (t.file_id IS NOT NULL) AS is_in_trash
	    FROM collection_actions ca
	    LEFT JOIN files f
	        ON f.file_id = ca.file_id
	    LEFT JOIN trash t
	        ON t.user_id = ca.user_id
	        AND t.file_id = ca.file_id
	        AND t.is_restored = false
	    WHERE ca.user_id = $1
	        AND ca.action = $2
	        AND ca.is_pending = true
	        AND ca.updated_at > $3
	    ORDER BY ca.updated_at
	    LIMIT $4`, userID, ente.ActionDeleteSuggested, updatedAfter, limit)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()

	result := make([]ente.CollectionAction, 0)
	staleActionIDs := make([]string, 0)
	for rows.Next() {
		var (
			ca            ente.CollectionAction
			data          []byte
			fileID        sql.NullInt64
			ownerID       sql.NullInt64
			hasTrashEntry bool
		)
		if err := rows.Scan(&ca.ID, &ca.UserID, &ca.ActorUserID, &ca.CollectionID, &fileID, &data, &ca.Action, &ca.IsPending, &ca.CreatedAt, &ca.UpdatedAt, &ownerID, &hasTrashEntry); err != nil {
			return result, stacktrace.Propagate(err, "")
		}
		if !fileID.Valid {
			staleActionIDs = append(staleActionIDs, ca.ID)
			continue
		}
		fid := fileID.Int64
		ca.FileID = &fid

		if !ownerID.Valid {
			staleActionIDs = append(staleActionIDs, ca.ID)
			continue
		}
		if ownerID.Int64 != ca.UserID {
			return result, stacktrace.NewError("delete suggestion action %s references file %d owned by %d for user %d", ca.ID, fid, ownerID.Int64, ca.UserID)
		}
		if hasTrashEntry {
			staleActionIDs = append(staleActionIDs, ca.ID)
			continue
		}
		if len(data) > 0 {
			var m map[string]interface{}
			if err := json.Unmarshal(data, &m); err != nil {
				return result, stacktrace.Propagate(err, "failed to unmarshal data")
			}
			ca.Data = m
		}
		result = append(result, ca)
	}
	if len(staleActionIDs) > 0 {
		if err := r.resetPendingForActions(ctx, staleActionIDs); err != nil {
			return result, stacktrace.Propagate(err, "failed to reset stale delete-suggested actions")
		}
	}
	return result, nil
}

func (r *CollectionActionsRepository) resetPendingForActions(ctx context.Context, ids []string) error {
	if len(ids) == 0 {
		return nil
	}
	_, err := r.DB.ExecContext(ctx, `UPDATE collection_actions SET is_pending = false WHERE id = ANY($1)`, pq.Array(ids))
	return stacktrace.Propagate(err, "")
}

func (r *CollectionActionsRepository) RejectDeleteSuggestions(ctx context.Context, userID int64, fileIDs []int64) (int64, error) {
	if len(fileIDs) == 0 {
		return 0, nil
	}
	res, err := r.DB.ExecContext(ctx, `UPDATE collection_actions
	        SET is_pending = false
	    WHERE user_id = $1
	        AND action = $2
	        AND is_pending = true
	        AND file_id = ANY($3)`, userID, ente.ActionDeleteSuggested, pq.Array(fileIDs))
	if err != nil {
		return 0, stacktrace.Propagate(err, "")
	}
	rowsAffected, err := res.RowsAffected()
	return rowsAffected, stacktrace.Propagate(err, "")
}

func marshalCollectionActionData(data map[string]interface{}) (interface{}, error) {
	if data == nil {
		return nil, nil
	}
	payload, err := json.Marshal(data)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to marshal collection action data")
	}
	return string(payload), nil // pq expects json inputs as text, not bytea
}
