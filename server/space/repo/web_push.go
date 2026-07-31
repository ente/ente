package repo

import (
	"context"
	"database/sql"
	"errors"

	"github.com/ente/museum/ente/base"
	timeutil "github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
)

const spaceWebPushLinkSubscriptionLimit = 10000

// ErrSpaceWebPushLinkSubscriptionLimit prevents an individual public link from growing without bound.
var ErrSpaceWebPushLinkSubscriptionLimit = errors.New("space web push link subscription limit reached")

func (r *WebPushRepository) UpsertAccountSubscription(
	ctx context.Context,
	sessionTokenHash []byte,
	endpoint, p256dh, auth string,
) (string, error) {
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()

	var sessionExists int
	if err := tx.QueryRowContext(ctx, `
		SELECT 1
		FROM space_browser_sessions
		WHERE token_hash = $1
		FOR UPDATE
	`, sessionTokenHash).Scan(&sessionExists); err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	if _, err := tx.ExecContext(ctx, `
		DELETE FROM space_web_push_subscriptions
		WHERE session_token_hash = $1 AND endpoint <> $2
	`, sessionTokenHash, endpoint); err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	if _, err := tx.ExecContext(ctx, `
		UPDATE space_web_push_subscriptions
		SET p256dh = $2, auth = $3
		WHERE endpoint = $1
	`, endpoint, p256dh, auth); err != nil {
		return "", stacktrace.Propagate(err, "")
	}

	targetID := base.MustNewID("wpt")
	if err := tx.QueryRowContext(ctx, `
		INSERT INTO space_web_push_subscriptions (
			target_id, endpoint, session_token_hash, p256dh, auth
		)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (endpoint) WHERE session_token_hash IS NOT NULL
		DO UPDATE SET
			session_token_hash = EXCLUDED.session_token_hash,
			p256dh = EXCLUDED.p256dh,
			auth = EXCLUDED.auth
		RETURNING target_id
	`, targetID, endpoint, sessionTokenHash, p256dh, auth).Scan(&targetID); err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	if err := tx.Commit(); err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	return targetID, nil
}

func (r *WebPushRepository) UpsertLinkSubscription(
	ctx context.Context,
	linkID int64,
	endpoint, p256dh, auth string,
) (string, error) {
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()

	var activeLinkID int64
	if err := tx.QueryRowContext(ctx, `
		SELECT link_id
		FROM space_links
		WHERE link_id = $1 AND active = TRUE
		FOR UPDATE
	`, linkID).Scan(&activeLinkID); err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	var subscriptionCount int
	var endpointExists bool
	if err := tx.QueryRowContext(ctx, `
		SELECT COUNT(*), COUNT(*) FILTER (WHERE endpoint = $2) > 0
		FROM space_web_push_subscriptions
		WHERE link_id = $1
	`, activeLinkID, endpoint).Scan(&subscriptionCount, &endpointExists); err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	if !endpointExists && subscriptionCount >= spaceWebPushLinkSubscriptionLimit {
		return "", ErrSpaceWebPushLinkSubscriptionLimit
	}
	if _, err := tx.ExecContext(ctx, `
		UPDATE space_web_push_subscriptions
		SET p256dh = $2, auth = $3
		WHERE endpoint = $1
	`, endpoint, p256dh, auth); err != nil {
		return "", stacktrace.Propagate(err, "")
	}

	targetID := base.MustNewID("wpt")
	if err := tx.QueryRowContext(ctx, `
		INSERT INTO space_web_push_subscriptions (
			target_id, endpoint, link_id, p256dh, auth
		)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (endpoint, link_id)
		DO UPDATE SET
			p256dh = EXCLUDED.p256dh,
			auth = EXCLUDED.auth
		RETURNING target_id
	`, targetID, endpoint, activeLinkID, p256dh, auth).Scan(&targetID); err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	if err := tx.Commit(); err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	return targetID, nil
}

func (r *WebPushRepository) DeleteAccountSubscription(
	ctx context.Context,
	sessionTokenHash []byte,
	endpoint string,
) error {
	_, err := r.DB.ExecContext(ctx, `
		DELETE FROM space_web_push_subscriptions
		WHERE session_token_hash = $1 AND endpoint = $2
	`, sessionTokenHash, endpoint)
	return stacktrace.Propagate(err, "")
}

func (r *WebPushRepository) DeleteLinkSubscription(
	ctx context.Context,
	linkID int64,
	endpoint string,
) error {
	_, err := r.DB.ExecContext(ctx, `
		DELETE FROM space_web_push_subscriptions
		WHERE link_id = $1 AND endpoint = $2
	`, linkID, endpoint)
	return stacktrace.Propagate(err, "")
}

func (r *WebPushRepository) DeleteEndpoint(ctx context.Context, endpoint string) error {
	_, err := r.DB.ExecContext(ctx, `
		DELETE FROM space_web_push_subscriptions
		WHERE endpoint = $1
	`, endpoint)
	return stacktrace.Propagate(err, "")
}

func (r *WebPushRepository) ListActiveAccountSubscriptions(
	ctx context.Context,
	userID int64,
) ([]SpaceWebPushSubscriptionRecord, error) {
	rows, err := r.DB.QueryContext(ctx, `
		SELECT push.target_id, push.endpoint, push.p256dh, push.auth, FALSE
		FROM space_web_push_subscriptions push
		JOIN space_browser_sessions session
		  ON session.token_hash = push.session_token_hash
		 AND session.expires_at > $2
		JOIN users active_user
		  ON active_user.user_id = session.user_id
		 AND active_user.encrypted_email IS NOT NULL
		WHERE session.user_id = $1
	`, userID, timeutil.Microseconds())
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	return scanWebPushSubscriptions(rows)
}

func (r *WebPushRepository) ListPostSubscriptions(
	ctx context.Context,
	spaceID string,
) ([]SpaceWebPushSubscriptionRecord, error) {
	rows, err := r.DB.QueryContext(ctx, `
		SELECT push.target_id, push.endpoint, push.p256dh, push.auth, FALSE
		FROM space_web_push_subscriptions push
		JOIN space_browser_sessions session
		  ON session.token_hash = push.session_token_hash
		 AND session.expires_at > $2
		JOIN users active_user
		  ON active_user.user_id = session.user_id
		 AND active_user.encrypted_email IS NOT NULL
		WHERE EXISTS (
			SELECT 1
			FROM space_friend_shares friendship
			JOIN spaces friend_space
			  ON friend_space.space_id = friendship.friend_space_id
			WHERE friendship.space_id = $1
			  AND friend_space.owner_id = session.user_id
		)

		UNION ALL

		SELECT push.target_id, push.endpoint, push.p256dh, push.auth, TRUE
		FROM space_web_push_subscriptions push
		JOIN space_links link
		  ON link.link_id = push.link_id
		 AND link.active = TRUE
		JOIN spaces space
		  ON space.space_id = link.space_id
		JOIN users active_user
		  ON active_user.user_id = space.owner_id
		 AND active_user.encrypted_email IS NOT NULL
		WHERE link.space_id = $1
	`, spaceID, timeutil.Microseconds())
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	return scanWebPushSubscriptions(rows)
}

func scanWebPushSubscriptions(rows *sql.Rows) ([]SpaceWebPushSubscriptionRecord, error) {
	var subscriptions []SpaceWebPushSubscriptionRecord
	for rows.Next() {
		var subscription SpaceWebPushSubscriptionRecord
		if err := rows.Scan(
			&subscription.TargetID,
			&subscription.Endpoint,
			&subscription.P256dh,
			&subscription.Auth,
			&subscription.Public,
		); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		subscriptions = append(subscriptions, subscription)
	}
	return subscriptions, stacktrace.Propagate(rows.Err(), "")
}
