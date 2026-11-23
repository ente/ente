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

type EmailSubscriptionBackfillCounts struct {
	Matched, Unmatched, AfterCutoff, Existing, OptOutConflicts, Subscribed, Suppressed int64
}

func (r *EmailSubscriptionRepository) BackfillProductMails(ctx context.Context, preferences map[string]bool, createdBefore int64, apply bool) (EmailSubscriptionBackfillCounts, error) {
	var counts EmailSubscriptionBackfillCounts
	if len(preferences) == 0 {
		return counts, nil
	}
	hashes := make([]string, 0, len(preferences))
	subscribed := make([]bool, 0, len(preferences))
	for hash, preference := range preferences {
		hashes = append(hashes, hash)
		subscribed = append(subscribed, preference)
	}
	changes := "SELECT subscribed FROM candidates WHERE existing IS NULL"
	if apply {
		changes = `
			INSERT INTO email_subscriptions (user_id, email_type, subscribed)
			SELECT user_id, $4, subscribed FROM candidates WHERE existing IS NULL
			ON CONFLICT (user_id, email_type) DO NOTHING
			RETURNING subscribed`
	}
	err := r.DB.QueryRowContext(ctx, `
		WITH matched AS (
			SELECT u.user_id, u.creation_time, source.subscribed
			FROM UNNEST($1::TEXT[], $2::BOOLEAN[]) AS source(email_hash, subscribed)
			JOIN users u ON u.email_hash = source.email_hash
			WHERE u.encrypted_email IS NOT NULL
		), candidates AS (
			SELECT m.user_id, m.subscribed, es.subscribed AS existing
			FROM matched m
			LEFT JOIN email_subscriptions es ON es.user_id = m.user_id AND es.email_type = $4
			WHERE m.creation_time < $3
		), changes AS (`+changes+`)
		SELECT
			(SELECT count(*) FROM matched),
			(SELECT count(*) FROM matched WHERE creation_time >= $3),
			(SELECT count(*) FROM candidates WHERE existing IS NOT NULL),
			(SELECT count(*) FROM candidates WHERE existing AND NOT subscribed),
			count(*) FILTER (WHERE subscribed),
			count(*) FILTER (WHERE NOT subscribed)
		FROM changes`, pq.Array(hashes), pq.Array(subscribed), createdBefore, ente.ProductMailsEmailType).
		Scan(&counts.Matched, &counts.AfterCutoff, &counts.Existing, &counts.OptOutConflicts, &counts.Subscribed, &counts.Suppressed)
	counts.Unmatched = int64(len(preferences)) - counts.Matched
	return counts, err
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
