package cast

import (
	"context"
	"database/sql"
	"strings"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/ente/cast"
	"github.com/ente/museum/pkg/utils/random"
	"github.com/ente/stacktrace"
	"github.com/google/uuid"
	log "github.com/sirupsen/logrus"
)

type Repository struct {
	DB *sql.DB
}

func (r *Repository) AddCode(ctx context.Context, pubKey string, ip string, deviceName string) (string, error) {
	codeValue, err := random.GenerateAlphaNumString(6)
	if err != nil {
		return "", err
	}
	codeValue = strings.ToUpper(codeValue)
	_, err = r.DB.ExecContext(ctx, "INSERT INTO casting (code, public_key, id, ip, device_name) VALUES ($1, $2, $3, $4, $5)", codeValue, pubKey, uuid.New(), ip, deviceName)
	if err != nil {
		return "", err
	}
	return codeValue, nil
}

func (r *Repository) GetAllDevices(ctx context.Context, userID int64) ([]cast.CastInfo, error) {
	rows, err := r.DB.QueryContext(ctx, "SELECT id, collection_id, ip, last_used_at, device_name FROM casting WHERE cast_user = $1 and is_deleted=false ORDER BY created_at DESC", userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to query devices")
	}
	defer rows.Close()
	devices := make([]cast.CastInfo, 0)
	for rows.Next() {
		var device cast.CastInfo
		if err := rows.Scan(&device.DeviceID, &device.CollectionID, &device.DeviceIP, &device.LastUsedAt, &device.DeviceName); err != nil {
			return nil, stacktrace.Propagate(err, "failed to scan device row")
		}
		devices = append(devices, device)
	}
	if err := rows.Err(); err != nil {
		return nil, stacktrace.Propagate(err, "error iterating over device rows")
	}
	return devices, nil
}

// InsertCastData insert collection_id, cast_user, token and encrypted_payload for given code if collection_id is not null
func (r *Repository) InsertCastData(ctx context.Context, castUserID int64, code string, collectionID int64, castToken string, encryptedPayload string) error {
	code = strings.ToUpper(code)
	_, err := r.DB.ExecContext(ctx, "UPDATE casting SET collection_id = $1, cast_user = $2, token = $3, encrypted_payload = $4 WHERE code = $5 and is_deleted=false", collectionID, castUserID, castToken, encryptedPayload, code)
	return err
}

func (r *Repository) GetPubKeyAndIp(ctx context.Context, code string) (string, string, error) {
	code = strings.ToUpper(code)
	var pubKey, ip string
	row := r.DB.QueryRowContext(ctx, "SELECT public_key, ip FROM casting WHERE code = $1 and is_deleted=false", code)
	err := row.Scan(&pubKey, &ip)
	if err != nil {
		if err == sql.ErrNoRows {
			return "", "", ente.ErrNotFoundError.NewErr("code not found")
		}
		return "", "", err
	}
	return pubKey, ip, nil
}

func (r *Repository) GetEncCastData(ctx context.Context, code string) (*string, error) {
	code = strings.ToUpper(code)
	var payload sql.NullString
	row := r.DB.QueryRowContext(ctx, "SELECT encrypted_payload FROM casting WHERE code = $1 and is_deleted=false", code)
	err := row.Scan(&payload)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, ente.ErrNotFoundError.NewErr("active code not found")
		}
		return nil, err
	}
	if !payload.Valid {
		return nil, nil
	}
	res := &payload.String
	return res, nil
}

func (r *Repository) GetCollectionAndCasterIDForToken(ctx context.Context, token string) (int64, int64, error) {
	var collection, userID int64
	row := r.DB.QueryRowContext(ctx, "SELECT collection_id, cast_user FROM casting WHERE token = $1 and is_deleted=false", token)
	err := row.Scan(&collection, &userID)
	if err != nil {
		if err == sql.ErrNoRows {
			return -1, -1, ente.ErrCastPermissionDenied.NewErr("invalid token")
		}
		return -1, -1, err
	}
	return collection, userID, nil
}

func (r *Repository) UpdateLastUsedAtForToken(ctx context.Context, token string) error {
	_, err := r.DB.ExecContext(ctx, "UPDATE casting SET last_used_at = now_utc_micro_seconds() WHERE token = $1", token)
	if err != nil {
		return err
	}
	return nil
}

// DeleteUnclaimedCodes that are not associated with a collection and are older than the given time
func (r *Repository) DeleteUnclaimedCodes(ctx context.Context, expiryTime int64) error {
	result, err := r.DB.ExecContext(ctx, "DELETE FROM casting WHERE last_used_at < $1 and is_deleted=false and collection_id is null", expiryTime)
	if err != nil {
		return err
	}
	if rows, rErr := result.RowsAffected(); rErr == nil && rows > 0 {
		log.Infof("Deleted %d unclaimed codes", rows)
	}
	return nil
}

// DeleteOldSessions where last used at is older than the given time
func (r *Repository) DeleteOldSessions(ctx context.Context, expiryTime int64) error {
	result, err := r.DB.ExecContext(ctx, "DELETE FROM casting WHERE last_used_at < $1", expiryTime)
	if err != nil {
		return err
	}
	if rows, rErr := result.RowsAffected(); rErr == nil && rows > 0 {
		log.Infof("Deleted %d old sessions", rows)
	}
	return nil
}

// RevokeTokenForUser code for given userID
func (r *Repository) RevokeTokenForUser(ctx context.Context, userId int64) error {
	_, err := r.DB.ExecContext(ctx, "UPDATE casting SET is_deleted=true where cast_user=$1", userId)
	return stacktrace.Propagate(err, "")
}

// RevokeTokenForCollection code for given collectionID
func (r *Repository) RevokeTokenForCollection(ctx context.Context, collectionID int64) error {
	_, err := r.DB.ExecContext(ctx, "UPDATE casting SET is_deleted=true where collection_id=$1", collectionID)
	return stacktrace.Propagate(err, "")
}

// RevokeForGivenUserAndCollection ..
func (r *Repository) RevokeForGivenUserAndCollection(ctx context.Context, collectionID int64, userID int64) error {
	_, err := r.DB.ExecContext(ctx, "UPDATE casting SET is_deleted=true where collection_id=$1 and cast_user=$2", collectionID, userID)
	return stacktrace.Propagate(err, "")
}

func (r *Repository) RevokeForGivenUserAndDevice(ctx context.Context, userID int64, deviceID uuid.UUID) error {
	_, err := r.DB.ExecContext(ctx, "UPDATE casting SET is_deleted=true where id=$1 and cast_user=$2", deviceID, userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to revoke token for given user and device")
	}
	return nil
}
