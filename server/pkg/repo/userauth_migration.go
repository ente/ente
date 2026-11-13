package repo

import (
	"context"
	"time"

	"github.com/ente/stacktrace"
)

const plaintextTokenBatchSize = 5000

// MigratePlaintextTokens clears legacy plaintext tokens (2026-09-02).
func (repo *UserAuthRepository) MigratePlaintextTokens(ctx context.Context) (int64, error) {
	var migrated int64
	for {
		result, err := repo.DB.ExecContext(ctx, `WITH batch AS (
			SELECT token_hash FROM tokens
			WHERE token IS NOT NULL
			ORDER BY token
			LIMIT $1
			FOR UPDATE
		)
		UPDATE tokens SET token = NULL
		FROM batch
		WHERE tokens.token_hash = batch.token_hash`, plaintextTokenBatchSize)
		if err != nil {
			return migrated, stacktrace.Propagate(err, "failed to clear plaintext tokens")
		}
		count, err := result.RowsAffected()
		if err != nil {
			return migrated, stacktrace.Propagate(err, "failed to count cleared plaintext tokens")
		}
		migrated += count
		if count < plaintextTokenBatchSize {
			return migrated, nil
		}
		time.Sleep(time.Second)
	}
}
