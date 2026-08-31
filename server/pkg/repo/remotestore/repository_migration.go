package remotestore

import (
	"context"
	"database/sql"
	"strings"

	"github.com/ente/museum/ente"
	log "github.com/sirupsen/logrus"

	"github.com/ente/stacktrace"
)

// MigrateCustomDomainCanonicalValues backfills canonical domains (2026-08-24).
func (r *Repository) MigrateCustomDomainCanonicalValues(ctx context.Context) error {
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "failed to begin custom domain backfill")
	}
	defer tx.Rollback()

	rows, err := tx.QueryContext(ctx, `SELECT user_id, key_value, canonical_value FROM remote_store
		WHERE key_name = $1 FOR UPDATE`, ente.CustomDomain)
	if err != nil {
		return stacktrace.Propagate(err, "failed to fetch custom domains")
	}
	defer rows.Close()

	type domainRow struct {
		userID         int64
		value          string
		current        sql.NullString
		canonicalValue string
	}
	var domains []*domainRow
	domainsByCanonicalValue := make(map[string][]*domainRow)
	for rows.Next() {
		domain := &domainRow{}
		if err := rows.Scan(&domain.userID, &domain.value, &domain.current); err != nil {
			return stacktrace.Propagate(err, "failed to scan custom domain")
		}
		domains = append(domains, domain)
	}
	if err := rows.Err(); err != nil {
		return stacktrace.Propagate(err, "failed to read custom domains")
	}
	if err := rows.Close(); err != nil {
		return stacktrace.Propagate(err, "failed to close custom domain rows")
	}

	for _, domain := range domains {
		if strings.HasPrefix(domain.value, "_") {
			continue
		}
		if err := ente.ValidatePublicCustomDomain(domain.value); err != nil {
			log.WithField("user_id", domain.userID).WithError(err).Warn("Skipping invalid custom domain during backfill")
			continue
		}
		canonicalDomain, err := ente.CanonicalDomain(domain.value)
		if err != nil {
			log.WithField("user_id", domain.userID).WithError(err).Warn("Skipping invalid custom domain during backfill")
			continue
		}
		domain.canonicalValue = canonicalDomain
		domainsByCanonicalValue[canonicalDomain] = append(domainsByCanonicalValue[canonicalDomain], domain)
	}
	for _, group := range domainsByCanonicalValue {
		if len(group) == 1 {
			continue
		}
		userIDs := make([]int64, len(group))
		for i, domain := range group {
			userIDs[i] = domain.userID
			domain.canonicalValue = ""
		}
		log.WithField("user_ids", userIDs).Warn("Skipping colliding custom domains during backfill")
	}

	for _, domain := range domains {
		if domain.current.Valid && domain.current.String != domain.canonicalValue {
			if _, err := tx.ExecContext(ctx, `UPDATE remote_store SET canonical_value = NULL
				WHERE user_id = $1 AND key_name = $2`, domain.userID, ente.CustomDomain); err != nil {
				return stacktrace.Propagate(err, "failed to clear stale custom domain")
			}
		}
	}
	for _, domain := range domains {
		if domain.canonicalValue == "" || domain.current.Valid && domain.current.String == domain.canonicalValue {
			continue
		}
		if _, err := tx.ExecContext(ctx, `UPDATE remote_store SET canonical_value = $1
			WHERE user_id = $2 AND key_name = $3 AND canonical_value IS DISTINCT FROM $1`,
			domain.canonicalValue, domain.userID, ente.CustomDomain); err != nil {
			return stacktrace.Propagate(err, "failed to backfill custom domain")
		}
	}
	return stacktrace.Propagate(tx.Commit(), "failed to commit custom domain backfill")
}
