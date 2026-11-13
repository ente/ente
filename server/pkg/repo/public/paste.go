package public

import (
	"context"
	"database/sql"
	"errors"

	"github.com/ente/museum/ente"
	"github.com/ente/stacktrace"
	"github.com/lib/pq"
)

type PasteRepository struct {
	DB *sql.DB
}

func NewPasteRepository(db *sql.DB) *PasteRepository {
	return &PasteRepository{DB: db}
}

func (r *PasteRepository) Insert(
	ctx context.Context,
	id string,
	accessToken string,
	req *ente.CreatePasteRequest,
	expiresAt int64,
) error {
	_, err := r.DB.ExecContext(ctx, `INSERT INTO public_paste_tokens
		(id, access_token, encrypted_data, decryption_header, encrypted_paste_key, encrypted_paste_key_nonce, kdf_nonce, kdf_mem_limit, kdf_ops_limit, expires_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
		id,
		accessToken,
		req.EncryptedData,
		req.DecryptionHeader,
		req.EncryptedPasteKey,
		req.EncryptedPasteKeyNonce,
		req.KdfNonce,
		req.KdfMemLimit,
		req.KdfOpsLimit,
		expiresAt,
	)
	if err == nil {
		return nil
	}
	var pqErr *pq.Error
	if errors.As(err, &pqErr) && pqErr.Code == "23505" {
		return ente.ErrAccessTokenInUse
	}
	return stacktrace.Propagate(err, "failed to insert paste token")
}

func (r *PasteRepository) ExistsActiveByToken(ctx context.Context, accessToken string) (bool, error) {
	row := r.DB.QueryRowContext(ctx, `SELECT 1 FROM public_paste_tokens
		WHERE access_token = $1
		  AND expires_at > now_utc_micro_seconds()
		LIMIT 1`, accessToken)
	var ok int
	err := row.Scan(&ok)
	if err == nil {
		return true, nil
	}
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	return false, stacktrace.Propagate(err, "failed to check paste token")
}

func (r *PasteRepository) ConsumeByToken(
	ctx context.Context,
	accessToken string,
) (*ente.PastePayload, error) {
	row := r.DB.QueryRowContext(ctx, `DELETE FROM public_paste_tokens
		WHERE access_token = $1
		  AND expires_at > now_utc_micro_seconds()
		RETURNING encrypted_data, decryption_header, encrypted_paste_key, encrypted_paste_key_nonce, kdf_nonce, kdf_mem_limit, kdf_ops_limit`, accessToken)
	payload := ente.PastePayload{}
	if err := row.Scan(
		&payload.EncryptedData,
		&payload.DecryptionHeader,
		&payload.EncryptedPasteKey,
		&payload.EncryptedPasteKeyNonce,
		&payload.KdfNonce,
		&payload.KdfMemLimit,
		&payload.KdfOpsLimit,
	); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ente.ErrNotFound
		}
		return nil, stacktrace.Propagate(err, "failed to consume paste token")
	}
	return &payload, nil
}

func (r *PasteRepository) CleanupExpired(ctx context.Context) error {
	_, err := r.DB.ExecContext(ctx, `DELETE FROM public_paste_tokens
		WHERE expires_at <= now_utc_micro_seconds()`)
	if err != nil {
		return stacktrace.Propagate(err, "failed to clean up expired pastes")
	}
	return nil
}
