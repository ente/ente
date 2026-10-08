package repo

import (
	"context"
	"database/sql"

	"github.com/ente/museum/ente/base"
	"github.com/ente/stacktrace"
)

type PokesRepository struct {
	DB *sql.DB
}

func (r *PokesRepository) Create(ctx context.Context, senderSpaceID, recipientSpaceID, requestID string) (bool, error) {
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return false, stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()
	var friendSpaceID string
	if err := tx.QueryRowContext(ctx, `
        SELECT friend_space_id FROM space_friend_shares
        WHERE space_id = $1 AND friend_space_id = $2 FOR SHARE
    `, recipientSpaceID, senderSpaceID).Scan(&friendSpaceID); err != nil {
		return false, stacktrace.Propagate(err, "")
	}
	pokeID := base.MustNewID("wpk")
	result, err := tx.ExecContext(ctx, `
        INSERT INTO space_pokes (poke_id, sender_space_id, recipient_space_id, client_request_id)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (sender_space_id, recipient_space_id, client_request_id) DO NOTHING
    `, pokeID, senderSpaceID, recipientSpaceID, requestID)
	if err != nil {
		return false, stacktrace.Propagate(err, "")
	}
	count, err := result.RowsAffected()
	if err != nil {
		return false, stacktrace.Propagate(err, "")
	}
	if count == 0 {
		return false, nil
	}
	if _, err := tx.ExecContext(ctx, `
        INSERT INTO space_notifications (notification_id, recipient_space_id, actor_space_id, kind, poke_id, created_at)
        SELECT $1, recipient_space_id, sender_space_id, 'poke', poke_id, created_at
        FROM space_pokes WHERE poke_id = $2
    `, base.MustNewID("wnot"), pokeID); err != nil {
		return false, stacktrace.Propagate(err, "")
	}
	if err := tx.Commit(); err != nil {
		return false, stacktrace.Propagate(err, "")
	}
	return true, nil
}
