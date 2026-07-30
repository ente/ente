package public

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"github.com/ente/museum/ente/base"
	"github.com/lib/pq"
	"github.com/spf13/viper"

	"github.com/ente/museum/ente"
	"github.com/ente/stacktrace"
)

// FileLinkRepository defines the methods for inserting, updating and
// retrieving entities related to public file
type FileLinkRepository struct {
	DB         *sql.DB
	photoHost  string
	lockerHost string
}

// NewFileLinkRepo ..
func NewFileLinkRepo(db *sql.DB) *FileLinkRepository {
	albumHost := viper.GetString("apps.public-albums")
	if albumHost == "" {
		albumHost = "https://albums.ente.com"
	}
	lockerHost := viper.GetString("apps.public-locker")
	if lockerHost == "" {
		lockerHost = "https://share.ente.com"
	}
	return &FileLinkRepository{
		DB:         db,
		photoHost:  albumHost,
		lockerHost: lockerHost,
	}
}

func (pcr *FileLinkRepository) FileLink(app ente.App, token string) string {
	if app == ente.Locker {
		return fmt.Sprintf("%s/%s", pcr.lockerHost, token)
	}
	return fmt.Sprintf("%s/file/?t=%s", pcr.photoHost, token)
}

func (pcr *FileLinkRepository) Insert(
	ctx context.Context,
	req ente.CreateFileUrl,
	ownerID int64,
	token string,
) (*string, error) {
	tx, err := pcr.DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to begin transaction for file token insert")
	}
	defer tx.Rollback()

	if err = ensureAccessTokenAvailable(ctx, tx, token); err != nil {
		return nil, err
	}

	id, err := base.NewID("pft")
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to generate new ID for public file token")
	}

	_, err = tx.ExecContext(ctx, `INSERT INTO public_file_tokens 
    (id, file_id, owner_id, access_token, app, encrypted_file_key, encrypted_file_key_nonce, kdf_nonce, kdf_mem_limit, kdf_ops_limit, encrypted_share_key) 
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)`,
		id,
		req.FileID,
		ownerID,
		token,
		string(req.App),
		req.EncryptedFileKey,
		req.EncryptedFileKeyNonce,
		req.KdfNonce,
		req.KdfMemLimit,
		req.KdfOpsLimit,
		req.EncryptedShareKey,
	)
	if err != nil {
		if err.Error() == "pq: duplicate key value violates unique constraint \"public_active_file_link_unique_idx\"" {
			return nil, ente.ErrActiveLinkAlreadyExists
		}
		return nil, stacktrace.Propagate(err, "failed to insert")
	}

	if err = tx.Commit(); err != nil {
		return nil, stacktrace.Propagate(err, "failed to commit file token insert")
	}

	return id, nil
}

// UpdateLinkSecretIfEmpty updates link key metadata if it hasn't been set already.
func (pcr *FileLinkRepository) UpdateLinkSecretIfEmpty(
	ctx context.Context,
	linkID string,
	data ente.CreateFileUrl,
) error {
	if data.EncryptedFileKey == nil &&
		data.EncryptedFileKeyNonce == nil &&
		data.KdfNonce == nil &&
		data.KdfMemLimit == nil &&
		data.KdfOpsLimit == nil &&
		data.EncryptedShareKey == nil {
		return nil
	}
	_, err := pcr.DB.ExecContext(ctx, `
		UPDATE public_file_tokens
		SET encrypted_file_key = COALESCE(encrypted_file_key, $1),
		    encrypted_file_key_nonce = COALESCE(encrypted_file_key_nonce, $2),
		    kdf_nonce = COALESCE(kdf_nonce, $3),
		    kdf_mem_limit = COALESCE(kdf_mem_limit, $4),
		    kdf_ops_limit = COALESCE(kdf_ops_limit, $5),
		    encrypted_share_key = COALESCE(encrypted_share_key, $6)
		WHERE id = $7`,
		data.EncryptedFileKey,
		data.EncryptedFileKeyNonce,
		data.KdfNonce,
		data.KdfMemLimit,
		data.KdfOpsLimit,
		data.EncryptedShareKey,
		linkID,
	)
	return stacktrace.Propagate(err, "failed to update link secret metadata")
}

// GetActiveFileUrlToken will return ente.CollectionLinkRow for given collection ID
// Note: The token could be expired or deviceLimit is already reached
func (pcr *FileLinkRepository) GetActiveFileUrlToken(ctx context.Context, fileID int64) (*ente.FileLinkRow, error) {
	row := pcr.DB.QueryRowContext(ctx, `SELECT id, file_id, owner_id, access_token, valid_till, device_limit, 
       is_disabled, pw_hash, pw_nonce, mem_limit, ops_limit, enable_download,
       encrypted_file_key, encrypted_file_key_nonce, kdf_nonce, kdf_mem_limit, kdf_ops_limit, encrypted_share_key FROM 
                                                   public_file_tokens WHERE file_id = $1 and is_disabled = FALSE`,
		fileID)

	ret := ente.FileLinkRow{}
	err := row.Scan(&ret.LinkID, &ret.FileID, &ret.OwnerID, &ret.Token, &ret.ValidTill, &ret.DeviceLimit,
		&ret.IsDisabled, &ret.PassHash, &ret.Nonce, &ret.MemLimit, &ret.OpsLimit, &ret.EnableDownload,
		&ret.EncryptedFileKey, &ret.EncryptedFileKeyNonce, &ret.KdfNonce, &ret.KdfMemLimit, &ret.KdfOpsLimit, &ret.EncryptedShareKey)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &ret, nil
}
func (pcr *FileLinkRepository) GetFileUrls(ctx context.Context, userID int64, sinceTime int64, limit int64, app ente.App) ([]*ente.FileLinkRow, error) {
	if limit <= 0 {
		limit = 500
	}
	query := `SELECT id, file_id, owner_id, is_disabled, valid_till, device_limit, enable_download, pw_hash, pw_nonce, mem_limit, ops_limit,
	   created_at, updated_at, encrypted_file_key, encrypted_file_key_nonce, kdf_nonce, kdf_mem_limit, kdf_ops_limit, encrypted_share_key
	   FROM public_file_tokens
	   WHERE owner_id = $1 AND created_at > $2 AND app = $3 ORDER BY updated_at DESC LIMIT $4`
	rows, err := pcr.DB.QueryContext(ctx, query, userID, sinceTime, string(app), limit)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to get public file urls")
	}
	defer rows.Close()

	var result []*ente.FileLinkRow
	for rows.Next() {
		var row ente.FileLinkRow
		err = rows.Scan(&row.LinkID, &row.FileID, &row.OwnerID, &row.IsDisabled,
			&row.ValidTill, &row.DeviceLimit, &row.EnableDownload,
			&row.PassHash, &row.Nonce, &row.MemLimit,
			&row.OpsLimit, &row.CreatedAt, &row.UpdatedAt,
			&row.EncryptedFileKey, &row.EncryptedFileKeyNonce, &row.KdfNonce, &row.KdfMemLimit, &row.KdfOpsLimit, &row.EncryptedShareKey)
		if err != nil {
			return nil, stacktrace.Propagate(err, "failed to scan public file url row")
		}
		result = append(result, &row)
	}
	return result, nil
}

func (pcr *FileLinkRepository) DisableLinkForFiles(ctx context.Context, fileIDs []int64) error {
	if len(fileIDs) == 0 {
		return nil
	}
	query := `UPDATE public_file_tokens SET is_disabled = TRUE WHERE file_id = ANY($1)`
	_, err := pcr.DB.ExecContext(ctx, query, pq.Array(fileIDs))
	if err != nil {
		return stacktrace.Propagate(err, "failed to disable public file links")
	}
	return nil
}

// DisableLinksForUser will disable all public file links for the given user
func (pcr *FileLinkRepository) DisableLinksForUser(ctx context.Context, userID int64) error {
	_, err := pcr.DB.ExecContext(ctx, `UPDATE public_file_tokens SET is_disabled = TRUE WHERE owner_id = $1`, userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to disable public file link")
	}
	return nil
}

func (pcr *FileLinkRepository) GetFileUrlRowByToken(ctx context.Context, accessToken string) (*ente.FileLinkRow, error) {
	result, err := pcr.getActiveFileUrlRowByToken(ctx, accessToken)
	if err == nil {
		return result, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return nil, stacktrace.Propagate(err, "failed to get active public file url summary by token")
	}
	result, err = pcr.getDisabledFileUrlRowByToken(ctx, accessToken)
	if err == nil {
		return result, nil
	}
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ente.ErrNotFound
	}
	return nil, stacktrace.Propagate(err, "failed to get disabled public file url summary by token")
}

func (pcr *FileLinkRepository) getActiveFileUrlRowByToken(ctx context.Context, accessToken string) (*ente.FileLinkRow, error) {
	row := pcr.DB.QueryRowContext(ctx,
		`SELECT id, file_id, owner_id, is_disabled, valid_till, device_limit, enable_download, pw_hash, pw_nonce, mem_limit, ops_limit,
       created_at, updated_at, encrypted_file_key, encrypted_file_key_nonce, kdf_nonce, kdf_mem_limit, kdf_ops_limit, encrypted_share_key
		from public_file_tokens
		where access_token = $1 and is_disabled = FALSE
`, accessToken)
	return scanFileLinkRow(row)
}

func (pcr *FileLinkRepository) getDisabledFileUrlRowByToken(ctx context.Context, accessToken string) (*ente.FileLinkRow, error) {
	row := pcr.DB.QueryRowContext(ctx,
		`SELECT id, file_id, owner_id, is_disabled, valid_till, device_limit, enable_download, pw_hash, pw_nonce, mem_limit, ops_limit,
       created_at, updated_at, encrypted_file_key, encrypted_file_key_nonce, kdf_nonce, kdf_mem_limit, kdf_ops_limit, encrypted_share_key
		from public_file_tokens
		where access_token = $1 and is_disabled = TRUE
		limit 1
`, accessToken)
	return scanFileLinkRow(row)
}

func scanFileLinkRow(row interface{ Scan(dest ...any) error }) (*ente.FileLinkRow, error) {
	var result = ente.FileLinkRow{}
	err := row.Scan(&result.LinkID, &result.FileID, &result.OwnerID, &result.IsDisabled, &result.ValidTill, &result.DeviceLimit, &result.EnableDownload, &result.PassHash, &result.Nonce, &result.MemLimit, &result.OpsLimit, &result.CreatedAt, &result.UpdatedAt, &result.EncryptedFileKey, &result.EncryptedFileKeyNonce, &result.KdfNonce, &result.KdfMemLimit, &result.KdfOpsLimit, &result.EncryptedShareKey)
	if err != nil {
		return nil, err
	}
	return &result, nil
}

func (pcr *FileLinkRepository) GetFileUrlRowByFileID(ctx context.Context, fileID int64) (*ente.FileLinkRow, error) {
	row := pcr.DB.QueryRowContext(ctx,
		`SELECT id, file_id, access_token, owner_id, is_disabled, enable_download, valid_till, device_limit, pw_hash, pw_nonce, mem_limit, ops_limit,
	   created_at, updated_at, encrypted_file_key, encrypted_file_key_nonce, kdf_nonce, kdf_mem_limit, kdf_ops_limit, encrypted_share_key
		from public_file_tokens 
		where file_id = $1 and is_disabled = FALSE`, fileID)
	var result = ente.FileLinkRow{}
	err := row.Scan(&result.LinkID, &result.FileID, &result.Token, &result.OwnerID, &result.IsDisabled, &result.EnableDownload, &result.ValidTill, &result.DeviceLimit, &result.PassHash, &result.Nonce, &result.MemLimit, &result.OpsLimit, &result.CreatedAt, &result.UpdatedAt, &result.EncryptedFileKey, &result.EncryptedFileKeyNonce, &result.KdfNonce, &result.KdfMemLimit, &result.KdfOpsLimit, &result.EncryptedShareKey)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, ente.ErrNotFound
		}
		return nil, stacktrace.Propagate(err, "failed to get public file url summary by file ID")
	}
	return &result, nil
}

// UpdateLink will update the row for corresponding public file token
func (pcr *FileLinkRepository) UpdateLink(ctx context.Context, pct ente.FileLinkRow) error {
	_, err := pcr.DB.ExecContext(ctx, `UPDATE public_file_tokens SET valid_till = $1, device_limit = $2, 
                                    pw_hash = $3, pw_nonce = $4, mem_limit = $5, ops_limit = $6, enable_download = $7  
                                where id = $8`,
		pct.ValidTill, pct.DeviceLimit, pct.PassHash, pct.Nonce, pct.MemLimit, pct.OpsLimit, pct.EnableDownload, pct.LinkID)
	return stacktrace.Propagate(err, "failed to update public file token")
}

func (pcr *FileLinkRepository) GetUniqueAccessCount(ctx context.Context, linkId string) (int64, error) {
	row := pcr.DB.QueryRowContext(ctx, `SELECT count(*) FROM public_file_tokens_access_history WHERE id = $1`, linkId)
	var count int64 = 0
	err := row.Scan(&count)
	if err != nil {
		return -1, stacktrace.Propagate(err, "")
	}
	return count, nil
}

func (pcr *FileLinkRepository) RecordAccessHistory(ctx context.Context, shareID string, ip string, ua string) error {
	_, err := pcr.DB.ExecContext(ctx, `INSERT INTO public_file_tokens_access_history 
    (id, ip, user_agent) VALUES ($1, $2, $3) 
    ON CONFLICT ON CONSTRAINT unique_access_id_ip_ua DO NOTHING;`,
		shareID, ip, ua)
	return stacktrace.Propagate(err, "failed to record access history")
}

// AccessedInPast returns true if the given ip, ua agent combination has accessed the url in the past
func (pcr *FileLinkRepository) AccessedInPast(ctx context.Context, shareID string, ip string, ua string) (bool, error) {
	row := pcr.DB.QueryRowContext(ctx, `select id from public_file_tokens_access_history where id =$1 and ip = $2 and user_agent = $3`,
		shareID, ip, ua)
	var tempID string
	err := row.Scan(&tempID)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	return true, stacktrace.Propagate(err, "failed to record access history")
}

// CleanupAccessHistory public_file_tokens_access_history where public_collection_tokens is disabled and the last updated time is older than 30 days
func (pcr *FileLinkRepository) CleanupAccessHistory(ctx context.Context) error {
	_, err := pcr.DB.ExecContext(ctx, `DELETE FROM public_file_tokens_access_history WHERE id IN (SELECT id FROM public_file_tokens WHERE is_disabled = TRUE AND updated_at < (now_utc_micro_seconds() - (24::BIGINT * 30 * 60 * 60 * 1000 * 1000)))`)
	if err != nil {
		return stacktrace.Propagate(err, "failed to clean up public file access history")
	}
	return nil
}
