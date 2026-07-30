package userentity

import (
	"context"
	"database/sql"
	"errors"

	"github.com/ente/museum/ente"
	model "github.com/ente/museum/ente/userentity"
	"github.com/ente/stacktrace"
	"github.com/sirupsen/logrus"
)

// Create inserts a new  entry
func (r *Repository) Create(ctx context.Context, userID int64, entry model.EntityDataRequest) (string, error) {
	var id string
	if entry.ID != nil {
		id = *entry.ID
	} else {
		idPrt, err := entry.Type.GetNewID()
		if err != nil {
			return "", stacktrace.Propagate(err, "failed to generate new id")
		}
		id = *idPrt
	}
	if entry.Type.CanRestoreDeletedData() {
		return r.createOrRestoreDeleted(ctx, userID, id, entry)
	}
	err := r.DB.QueryRow(`INSERT into entity_data(
                         id,
                         user_id,
                         type,
                         encrypted_data,
                         header) VALUES ($1,$2,$3,$4,$5) RETURNING id`,
		id,                  //$1 id
		userID,              // $2 user_id
		entry.Type,          // $3 type
		entry.EncryptedData, // $4 encrypted_data
		entry.Header).       // $5 header
		Scan(&id)
	if err != nil {
		return id, stacktrace.Propagate(err, "failed to create enity data")
	}
	return id, nil
}

func (r *Repository) createOrRestoreDeleted(ctx context.Context, userID int64, id string, entry model.EntityDataRequest) (string, error) {
	err := r.DB.QueryRowContext(ctx, `INSERT into entity_data(
                         id,
                         user_id,
                         type,
                         encrypted_data,
                         header) VALUES ($1,$2,$3,$4,$5)
                         ON CONFLICT (id) DO UPDATE SET
                         encrypted_data = EXCLUDED.encrypted_data,
                         header = EXCLUDED.header,
                         is_deleted = FALSE
                         WHERE entity_data.user_id = EXCLUDED.user_id
                         AND entity_data.type = EXCLUDED.type
                         AND entity_data.is_deleted = TRUE
                         RETURNING id`,
		id,
		userID,
		entry.Type,
		entry.EncryptedData,
		entry.Header).
		Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return id, ente.NewAlreadyExistsError("Entity already exists")
	}
	if err != nil {
		return id, stacktrace.Propagate(err, "failed to create entity data")
	}
	return id, nil
}

func (r *Repository) Get(ctx context.Context, userID int64, id string) (*model.EntityData, error) {
	res := model.EntityData{}
	row := r.DB.QueryRowContext(ctx, `SELECT
	id, user_id, type, encrypted_data, header, is_deleted, created_at, updated_at
	FROM entity_data
	WHERE  id = $1 AND
	user_id = $2`,
		id,     // $1
		userID, // %2     // $3
	)
	err := row.Scan(&res.ID, &res.UserID, &res.Type, &res.EncryptedData, &res.Header, &res.IsDeleted, &res.CreatedAt, &res.UpdatedAt)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to get entity data")
	}
	return &res, nil
}

func (r *Repository) Delete(ctx context.Context, userID int64, id string) (bool, error) {
	_, err := r.DB.ExecContext(ctx,
		`UPDATE entity_data SET is_deleted = true, encrypted_data = NULL, header = NULL where id=$1 and user_id = $2`,
		id, userID)
	if err != nil {
		return false, stacktrace.Propagate(err, "faield to delele entity_data with id=%s", id)
	}
	return true, nil
}

func (r *Repository) Update(ctx context.Context, userID int64, req model.UpdateEntityDataRequest) error {
	result, err := r.DB.ExecContext(ctx,
		`UPDATE entity_data SET encrypted_data = $1, header = $2 where id=$3 and user_id = $4 and is_deleted = FALSE`,
		req.EncryptedData, req.Header, req.ID, userID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if affected != 1 {
		dbEntity, dbEntityErr := r.Get(ctx, userID, req.ID)
		if dbEntityErr != nil {
			return stacktrace.Propagate(dbEntityErr, "failed to get entity for update with id=%s", req.ID)
		}
		if dbEntity.IsDeleted {
			return stacktrace.Propagate(ente.NewBadRequestWithMessage("entity is already deleted"), "")
		} else if *dbEntity.EncryptedData == req.EncryptedData && *dbEntity.Header == req.Header {
			logrus.WithField("id", req.ID).Info("entity is already updated")
			return nil
		}
		return stacktrace.Propagate(errors.New("exactly one row should be updated"), "")
	}
	return nil
}

// GetDiff returns the &{[]model.EntityData} which have been added or
// modified after the given sinceTime
func (r *Repository) GetDiff(ctx context.Context, userID int64, eType model.EntityType, sinceTime int64, limit int16) ([]model.EntityData, error) {
	rows, err := r.DB.QueryContext(ctx, `SELECT
       id, user_id, type, encrypted_data, header, is_deleted, created_at, updated_at
	   FROM entity_data
	   WHERE user_id = $1 and type = $2
	   and updated_at > $3
       ORDER BY updated_at
	   LIMIT $4`,
		userID,
		eType,     // $2
		sinceTime, // $3
		limit,     // $4
	)
	if err != nil {
		return nil, stacktrace.Propagate(err, "GetDiff query failed")
	}
	return convertRowsToEntityData(rows)
}

func convertRowsToEntityData(rows *sql.Rows) ([]model.EntityData, error) {
	defer func() {
		if err := rows.Close(); err != nil {
			logrus.Error(err)
		}
	}()
	result := make([]model.EntityData, 0)
	for rows.Next() {
		entity := model.EntityData{}
		err := rows.Scan(
			&entity.ID, &entity.UserID, &entity.Type, &entity.EncryptedData, &entity.Header, &entity.IsDeleted,
			&entity.CreatedAt, &entity.UpdatedAt)
		if err != nil {
			return nil, stacktrace.Propagate(err, "failed to convert convertRowsToEntityData")
		}
		result = append(result, entity)
	}
	return result, nil
}
