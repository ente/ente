package repo

import (
	"context"
	"database/sql"

	"github.com/ente/museum/ente"
	"github.com/lib/pq"
)

type EmailSubscriptionRepository struct {
	DB *sql.DB
}

func EnrollNewUserEmailSubscriptions(ctx context.Context, tx *sql.Tx, userID int64) error {
	_, err := tx.ExecContext(ctx, `
		INSERT INTO email_subscriptions (user_id, email_type, subscribed)
		VALUES ($1, $2, TRUE)`, userID, ente.ProductMailsEmailType)
	return err
}

func (r *EmailSubscriptionRepository) Unsubscribe(ctx context.Context, userID int64, emailType ente.EmailType) error {
	_, err := r.DB.ExecContext(ctx, `
		UPDATE email_subscriptions SET subscribed = FALSE
		WHERE user_id = $1 AND email_type = $2 AND subscribed`, userID, emailType)
	return err
}

func (r *EmailSubscriptionRepository) SubscribedUserIDs(ctx context.Context, userIDs []int64, emailType ente.EmailType) (map[int64]bool, error) {
	rows, err := r.DB.QueryContext(ctx, `
		SELECT user_id FROM email_subscriptions
		WHERE user_id = ANY($1) AND email_type = $2 AND subscribed`, pq.Array(userIDs), emailType)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	subscribed := make(map[int64]bool, len(userIDs))
	for rows.Next() {
		var userID int64
		if err := rows.Scan(&userID); err != nil {
			return nil, err
		}
		subscribed[userID] = true
	}
	return subscribed, rows.Err()
}
