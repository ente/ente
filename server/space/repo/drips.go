package repo

import (
	"context"
	"database/sql"

	"github.com/ente/stacktrace"
	"github.com/lib/pq"
)

const defaultSpaceDripCandidateLimit = 500

type SpaceDripCandidate struct {
	UserID int64
}

func spaceDripCandidateLimit(limit int) int {
	if limit <= 0 {
		return defaultSpaceDripCandidateLimit
	}
	if limit > defaultSpaceDripCandidateLimit {
		return defaultSpaceDripCandidateLimit
	}
	return limit
}

func scanSpaceDripCandidates(rows *sql.Rows) ([]SpaceDripCandidate, error) {
	defer rows.Close()
	var out []SpaceDripCandidate
	for rows.Next() {
		var candidate SpaceDripCandidate
		if err := rows.Scan(&candidate.UserID); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		out = append(out, candidate)
	}
	return out, stacktrace.Propagate(rows.Err(), "")
}

func (r *DripsRepository) ListProfileMissingCandidates(ctx context.Context, now int64, threshold int64, excludeTemplateIDs []string, limit int) ([]SpaceDripCandidate, error) {
	rows, err := r.DB.QueryContext(ctx, `
		SELECT s.user_id
		FROM space_browser_sessions s
		JOIN users u ON u.user_id = s.user_id AND u.encrypted_email IS NOT NULL
		WHERE s.created_at <= $1
		  AND s.expires_at > $2
		  AND NOT EXISTS (
		      SELECT 1
		      FROM spaces owned
		      WHERE owned.owner_id = s.user_id
		  )
		  AND NOT EXISTS (
		      SELECT 1
		      FROM notification_history nh
		      WHERE nh.user_id = s.user_id
		        AND nh.template_id = ANY($3)
		)
		GROUP BY s.user_id
		ORDER BY MIN(s.created_at) ASC, s.user_id ASC
		LIMIT $4
	`, threshold, now, pq.Array(excludeTemplateIDs), spaceDripCandidateLimit(limit))
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return scanSpaceDripCandidates(rows)
}

func (r *DripsRepository) ListInvitePeopleCandidates(ctx context.Context, threshold int64, excludeTemplateIDs []string, limit int) ([]SpaceDripCandidate, error) {
	rows, err := r.DB.QueryContext(ctx, `
		SELECT s.owner_id
		FROM spaces s
		JOIN users u ON u.user_id = s.owner_id AND u.encrypted_email IS NOT NULL
		WHERE s.created_at <= $1
		  AND NOT EXISTS (
		      SELECT 1
		      FROM notification_history nh
		      WHERE nh.user_id = s.owner_id
		        AND nh.template_id = ANY($2)
		  )
		  AND NOT EXISTS (
		      SELECT 1
		      FROM space_friend_shares f
		      WHERE f.space_id = s.space_id
		  )
		  AND NOT EXISTS (
		      SELECT 1
		      FROM space_friend_requests fr
		      WHERE fr.requester_space_id = s.space_id
		        OR fr.target_space_id = s.space_id
		  )
		ORDER BY s.created_at ASC, s.owner_id ASC
		LIMIT $3
	`, threshold, pq.Array(excludeTemplateIDs), spaceDripCandidateLimit(limit))
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return scanSpaceDripCandidates(rows)
}

func (r *DripsRepository) ListFirstPostCandidates(ctx context.Context, threshold int64, excludeTemplateIDs []string, limit int) ([]SpaceDripCandidate, error) {
	rows, err := r.DB.QueryContext(ctx, `
		WITH first_friend AS (
			SELECT s.owner_id AS user_id, MIN(f.created_at) AS event_at
			FROM spaces s
			JOIN users u ON u.user_id = s.owner_id AND u.encrypted_email IS NOT NULL
			JOIN space_friend_shares f ON f.space_id = s.space_id
			WHERE f.created_at <= $1
			GROUP BY s.owner_id
		)
		SELECT ff.user_id
		FROM first_friend ff
		WHERE NOT EXISTS (
		      SELECT 1
		      FROM notification_history nh
		      WHERE nh.user_id = ff.user_id
		        AND nh.template_id = ANY($2)
		  )
		  AND NOT EXISTS (
		      SELECT 1
		      FROM spaces owned
		      JOIN space_posts p ON p.space_id = owned.space_id
		      WHERE owned.owner_id = ff.user_id
		  )
		ORDER BY ff.event_at ASC, ff.user_id ASC
		LIMIT $3
	`, threshold, pq.Array(excludeTemplateIDs), spaceDripCandidateLimit(limit))
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return scanSpaceDripCandidates(rows)
}

func (r *DripsRepository) ListFeedbackCandidates(ctx context.Context, threshold int64, excludeTemplateIDs []string, limit int) ([]SpaceDripCandidate, error) {
	rows, err := r.DB.QueryContext(ctx, `
		WITH eligible_spaces AS MATERIALIZED (
			SELECT s.space_id, s.owner_id
			FROM spaces s
			JOIN users u ON u.user_id = s.owner_id AND u.encrypted_email IS NOT NULL
			WHERE NOT EXISTS (
			      SELECT 1
			      FROM notification_history nh
			      WHERE nh.user_id = s.owner_id
			        AND nh.template_id = ANY($2)
			  )
		),
		activities AS (
			SELECT s.owner_id AS user_id, p.created_at AS event_at
			FROM eligible_spaces s
			JOIN space_posts p ON p.space_id = s.space_id
			WHERE p.created_at <= $1

			UNION ALL

			SELECT s.owner_id AS user_id, m.created_at AS event_at
			FROM eligible_spaces s
			JOIN space_messages m ON m.sender_space_id = s.space_id
			WHERE m.kind = 'post_reply'
			  AND m.created_at <= $1
		),
		first_activity AS (
			SELECT user_id, MIN(event_at) AS event_at
			FROM activities
			GROUP BY user_id
		)
		SELECT fa.user_id
		FROM first_activity fa
		ORDER BY fa.event_at ASC, fa.user_id ASC
		LIMIT $3
	`, threshold, pq.Array(excludeTemplateIDs), spaceDripCandidateLimit(limit))
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return scanSpaceDripCandidates(rows)
}
