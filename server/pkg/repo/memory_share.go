package repo

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
	"github.com/lib/pq"
	"github.com/spf13/viper"
)

// MemoryShareRepository persists memory share rows and their files.
type MemoryShareRepository struct {
	DB         *sql.DB
	memoryHost string
}

// NewMemoryShareRepository builds a repository using the configured public memories host.
func NewMemoryShareRepository(db *sql.DB) *MemoryShareRepository {
	memoryHost := viper.GetString("apps.public-memories")
	if memoryHost == "" {
		memoryHost = "https://memories.ente.com"
	}
	return &MemoryShareRepository{
		DB:         db,
		memoryHost: memoryHost,
	}
}

// GetMemoryShareURL constructs the public URL for a share token.
func (r *MemoryShareRepository) GetMemoryShareURL(accessToken string) string {
	return fmt.Sprintf("%s/%s", r.memoryHost, accessToken)
}

// Create inserts a memory share and returns the saved row.
func (r *MemoryShareRepository) Create(ctx context.Context, share ente.MemoryShare) (ente.MemoryShare, error) {
	now := time.Microseconds()
	err := r.DB.QueryRowContext(ctx, `
		INSERT INTO memory_shares
		(user_id, type, memory_hash, metadata_cipher, metadata_nonce,
		 mem_enc_key, mem_key_decryption_nonce, access_token, is_deleted, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
		RETURNING id`,
		share.UserID, share.Type, share.MemoryHash, share.MetadataCipher, share.MetadataNonce,
		share.EncryptedKey, share.KeyDecryptionNonce, share.AccessToken,
		false, now, now).Scan(&share.ID)
	if err != nil {
		if pgErr, ok := err.(*pq.Error); ok && pgErr.Code == "23505" {
			return share, ente.ErrAccessTokenInUse
		}
		return share, stacktrace.Propagate(err, "failed to insert memory share")
	}
	share.CreatedAt = now
	share.UpdatedAt = now
	share.URL = r.GetMemoryShareURL(share.AccessToken)
	return share, nil
}

// CreateWithFiles atomically creates the share and its file rows so we never persist an empty share.
func (r *MemoryShareRepository) CreateWithFiles(ctx context.Context, share ente.MemoryShare, files []ente.MemoryShareFile) (ente.MemoryShare, error) {
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return share, stacktrace.Propagate(err, "failed to begin transaction")
	}
	defer tx.Rollback()

	now := time.Microseconds()

	err = tx.QueryRowContext(ctx, `
		INSERT INTO memory_shares
		(user_id, type, memory_hash, metadata_cipher, metadata_nonce,
		 mem_enc_key, mem_key_decryption_nonce, access_token, is_deleted, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
		RETURNING id`,
		share.UserID, share.Type, share.MemoryHash, share.MetadataCipher, share.MetadataNonce,
		share.EncryptedKey, share.KeyDecryptionNonce, share.AccessToken,
		false, now, now).Scan(&share.ID)
	if err != nil {
		if pgErr, ok := err.(*pq.Error); ok && pgErr.Code == "23505" {
			return share, ente.ErrAccessTokenInUse
		}
		return share, stacktrace.Propagate(err, "failed to insert memory share")
	}

	for _, file := range files {
		_, err = tx.ExecContext(ctx, `
			INSERT INTO memory_share_files
			(memory_share_id, file_id, file_owner_id, position, file_enc_key, file_key_decryption_nonce, created_at)
			VALUES ($1, $2, $3, $4, $5, $6, $7)`,
			share.ID, file.FileID, file.FileOwnerID, file.Position, file.EncryptedKey, file.KeyDecryptionNonce, now)
		if err != nil {
			return share, stacktrace.Propagate(err, "failed to insert share file")
		}
	}

	if err = tx.Commit(); err != nil {
		return share, stacktrace.Propagate(err, "failed to commit transaction")
	}

	share.CreatedAt = now
	share.UpdatedAt = now
	share.URL = r.GetMemoryShareURL(share.AccessToken)
	return share, nil
}

// AddFiles appends files to an existing memory share.
func (r *MemoryShareRepository) AddFiles(ctx context.Context, shareID int64, files []ente.MemoryShareFile) error {
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "failed to begin transaction")
	}
	defer tx.Rollback()

	now := time.Microseconds()
	for _, file := range files {
		_, err = tx.ExecContext(ctx, `
			INSERT INTO memory_share_files
			(memory_share_id, file_id, file_owner_id, position, file_enc_key, file_key_decryption_nonce, created_at)
			VALUES ($1, $2, $3, $4, $5, $6, $7)`,
			shareID, file.FileID, file.FileOwnerID, file.Position, file.EncryptedKey, file.KeyDecryptionNonce, now)
		if err != nil {
			return stacktrace.Propagate(err, "failed to insert share file")
		}
	}

	if err = tx.Commit(); err != nil {
		return stacktrace.Propagate(err, "failed to commit transaction")
	}
	return nil
}

// GetByID fetches a memory share by primary key.
func (r *MemoryShareRepository) GetByID(ctx context.Context, id int64) (*ente.MemoryShare, error) {
	share := &ente.MemoryShare{}
	err := r.DB.QueryRowContext(ctx, `
		SELECT id, user_id, type, COALESCE(memory_hash, ''), metadata_cipher, metadata_nonce,
		       mem_enc_key, mem_key_decryption_nonce, access_token, is_deleted, created_at, updated_at
		FROM memory_shares WHERE id = $1`, id).Scan(
		&share.ID, &share.UserID, &share.Type, &share.MemoryHash, &share.MetadataCipher, &share.MetadataNonce,
		&share.EncryptedKey, &share.KeyDecryptionNonce, &share.AccessToken,
		&share.IsDeleted, &share.CreatedAt, &share.UpdatedAt)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, stacktrace.Propagate(ente.ErrNotFound, "memory share not found")
		}
		return nil, stacktrace.Propagate(err, "failed to get memory share")
	}
	share.URL = r.GetMemoryShareURL(share.AccessToken)
	return share, nil
}

// GetByAccessToken fetches a memory share using its public token.
func (r *MemoryShareRepository) GetByAccessToken(ctx context.Context, token string) (*ente.MemoryShare, error) {
	share := &ente.MemoryShare{}
	err := r.DB.QueryRowContext(ctx, `
		SELECT id, user_id, type, COALESCE(memory_hash, ''), metadata_cipher, metadata_nonce,
		       mem_enc_key, mem_key_decryption_nonce, access_token, is_deleted, created_at, updated_at
		FROM memory_shares WHERE access_token = $1`, token).Scan(
		&share.ID, &share.UserID, &share.Type, &share.MemoryHash, &share.MetadataCipher, &share.MetadataNonce,
		&share.EncryptedKey, &share.KeyDecryptionNonce, &share.AccessToken,
		&share.IsDeleted, &share.CreatedAt, &share.UpdatedAt)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, stacktrace.Propagate(ente.ErrNotFound, "memory share not found")
		}
		return nil, stacktrace.Propagate(err, "failed to get memory share by token")
	}
	share.URL = r.GetMemoryShareURL(share.AccessToken)
	return share, nil
}

// GetFiles returns all file rows for a memory share.
func (r *MemoryShareRepository) GetFiles(ctx context.Context, shareID int64) ([]ente.MemoryShareFile, error) {
	rows, err := r.DB.QueryContext(ctx, `
		SELECT id, memory_share_id, file_id, file_owner_id, position, file_enc_key, file_key_decryption_nonce, created_at
		FROM memory_share_files
		WHERE memory_share_id = $1
		ORDER BY position ASC, id ASC`, shareID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to query share files")
	}
	defer rows.Close()

	var files []ente.MemoryShareFile
	for rows.Next() {
		var file ente.MemoryShareFile
		if err = rows.Scan(&file.ID, &file.MemoryShareID, &file.FileID, &file.FileOwnerID,
			&file.Position, &file.EncryptedKey, &file.KeyDecryptionNonce, &file.CreatedAt); err != nil {
			return nil, stacktrace.Propagate(err, "failed to scan share file")
		}
		files = append(files, file)
	}
	return files, nil
}

// GetFileIDs returns just the file IDs for a memory share.
func (r *MemoryShareRepository) GetFileIDs(ctx context.Context, shareID int64) ([]int64, error) {
	rows, err := r.DB.QueryContext(ctx, `
		SELECT file_id
		FROM memory_share_files
		WHERE memory_share_id = $1
		ORDER BY position ASC, id ASC`, shareID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to query file IDs")
	}
	defer rows.Close()

	var fileIDs []int64
	for rows.Next() {
		var fileID int64
		if err = rows.Scan(&fileID); err != nil {
			return nil, stacktrace.Propagate(err, "failed to scan file ID")
		}
		fileIDs = append(fileIDs, fileID)
	}
	return fileIDs, nil
}

// GetByUserID returns all non-deleted shares created by a user.
func (r *MemoryShareRepository) GetByUserID(ctx context.Context, userID int64) ([]ente.MemoryShare, error) {
	activeCreatedAfter := ente.ActiveMemoryShareCreatedAfter()
	rows, err := r.DB.QueryContext(ctx, `
		SELECT id, user_id, type, COALESCE(memory_hash, ''), metadata_cipher, metadata_nonce,
		       mem_enc_key, mem_key_decryption_nonce, access_token, is_deleted, created_at, updated_at
		FROM memory_shares
		WHERE user_id = $1 AND is_deleted = false AND created_at > $2
		ORDER BY created_at DESC`, userID, activeCreatedAfter)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to query user shares")
	}
	defer rows.Close()

	var shares []ente.MemoryShare
	for rows.Next() {
		var share ente.MemoryShare
		if err = rows.Scan(&share.ID, &share.UserID, &share.Type, &share.MemoryHash, &share.MetadataCipher, &share.MetadataNonce,
			&share.EncryptedKey, &share.KeyDecryptionNonce, &share.AccessToken,
			&share.IsDeleted, &share.CreatedAt, &share.UpdatedAt); err != nil {
			return nil, stacktrace.Propagate(err, "failed to scan memory share")
		}
		share.URL = r.GetMemoryShareURL(share.AccessToken)
		shares = append(shares, share)
	}
	return shares, nil
}

// Delete soft-deletes a memory share owned by the given user.
func (r *MemoryShareRepository) Delete(ctx context.Context, shareID int64, userID int64) error {
	result, err := r.DB.ExecContext(ctx, `
		UPDATE memory_shares SET is_deleted = true, updated_at = $1
		WHERE id = $2 AND user_id = $3 AND is_deleted = false`,
		time.Microseconds(), shareID, userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to delete memory share")
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return stacktrace.Propagate(err, "failed to get rows affected")
	}
	if rowsAffected == 0 {
		return stacktrace.Propagate(ente.ErrNotFound, "memory share not found or not owned by user")
	}
	return nil
}

// GetFileOwnerMap returns a fileID->ownerID map for a share.
func (r *MemoryShareRepository) GetFileOwnerMap(ctx context.Context, shareID int64) (map[int64]int64, error) {
	rows, err := r.DB.QueryContext(ctx, `
		SELECT file_id, file_owner_id FROM memory_share_files WHERE memory_share_id = $1`, shareID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to query file owner map")
	}
	defer rows.Close()

	ownerMap := make(map[int64]int64)
	for rows.Next() {
		var fileID, ownerID int64
		if err = rows.Scan(&fileID, &ownerID); err != nil {
			return nil, stacktrace.Propagate(err, "failed to scan file owner")
		}
		ownerMap[fileID] = ownerID
	}
	return ownerMap, nil
}

// GetFileByID fetches a specific file entry for a share.
func (r *MemoryShareRepository) GetFileByID(ctx context.Context, shareID int64, fileID int64) (*ente.MemoryShareFile, error) {
	file := &ente.MemoryShareFile{}
	err := r.DB.QueryRowContext(ctx, `
		SELECT id, memory_share_id, file_id, file_owner_id, position, file_enc_key, file_key_decryption_nonce, created_at
		FROM memory_share_files
		WHERE memory_share_id = $1 AND file_id = $2
		ORDER BY position ASC, id ASC
		LIMIT 1`, shareID, fileID).Scan(
		&file.ID, &file.MemoryShareID, &file.FileID, &file.FileOwnerID,
		&file.Position, &file.EncryptedKey, &file.KeyDecryptionNonce, &file.CreatedAt)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, stacktrace.Propagate(ente.ErrNotFound, "file not found in share")
		}
		return nil, stacktrace.Propagate(err, "failed to get file by ID")
	}
	return file, nil
}

// FileExistsInShare reports whether a file belongs to a share and returns the ownerID.
func (r *MemoryShareRepository) FileExistsInShare(ctx context.Context, shareID int64, fileID int64) (bool, int64, error) {
	var ownerID int64
	err := r.DB.QueryRowContext(ctx, `
		SELECT file_owner_id FROM memory_share_files
		WHERE memory_share_id = $1 AND file_id = $2`, shareID, fileID).Scan(&ownerID)
	if err != nil {
		if err == sql.ErrNoRows {
			return false, 0, nil
		}
		return false, 0, stacktrace.Propagate(err, "failed to check file existence")
	}
	return true, ownerID, nil
}

// GetFilesWithKeys returns file entries and re-encrypted keys for the requested file IDs.
func (r *MemoryShareRepository) GetFilesWithKeys(ctx context.Context, shareID int64, fileIDs []int64) ([]ente.MemoryShareFile, error) {
	rows, err := r.DB.QueryContext(ctx, `
		SELECT id, memory_share_id, file_id, file_owner_id, position, file_enc_key, file_key_decryption_nonce, created_at
		FROM memory_share_files
		WHERE memory_share_id = $1 AND file_id = ANY($2)
		ORDER BY position ASC, id ASC`, shareID, pq.Array(fileIDs))
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to query files with keys")
	}
	defer rows.Close()

	var files []ente.MemoryShareFile
	for rows.Next() {
		var file ente.MemoryShareFile
		if err = rows.Scan(&file.ID, &file.MemoryShareID, &file.FileID, &file.FileOwnerID,
			&file.Position, &file.EncryptedKey, &file.KeyDecryptionNonce, &file.CreatedAt); err != nil {
			return nil, stacktrace.Propagate(err, "failed to scan file with keys")
		}
		files = append(files, file)
	}
	return files, nil
}
