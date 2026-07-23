package public

import (
	"context"
	"database/sql"
	"errors"
	"fmt"

	"github.com/spf13/viper"

	"github.com/ente/museum/ente"
	"github.com/ente/stacktrace"
	"github.com/lib/pq"
)

// CollectionLinkRepo defines the methods for inserting, updating and
// retrieving entities related to public collections
type CollectionLinkRepo struct {
	DB         *sql.DB
	albumHost  string
	lockerHost string
}

// NewCollectionLinkRepository ..
func NewCollectionLinkRepository(db *sql.DB, albumHost string) *CollectionLinkRepo {
	if albumHost == "" {
		albumHost = "https://albums.ente.com"
	}
	lockerHost := viper.GetString("apps.public-locker")
	if lockerHost == "" {
		lockerHost = "https://share.ente.com"
	}
	return &CollectionLinkRepo{
		DB:         db,
		albumHost:  albumHost,
		lockerHost: lockerHost,
	}
}

func (pcr *CollectionLinkRepo) GetAlbumUrl(app ente.App, token string) string {
	if app == ente.Locker {
		return fmt.Sprintf("%s/c/%s", pcr.lockerHost, token)
	}
	return fmt.Sprintf("%s/?t=%s", pcr.albumHost, token)
}

func (pcr *CollectionLinkRepo) Insert(ctx context.Context,
	cID int64, token string, validTill int64, deviceLimit int, enableCollect bool, enableComment bool, enableJoin *bool) error {
	// default value for enableJoin is true
	join := true
	if enableJoin != nil {
		join = *enableJoin
	}
	tx, err := pcr.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "failed to begin transaction for collection token insert")
	}
	defer tx.Rollback()

	if err = ensureAccessTokenAvailable(ctx, tx, token); err != nil {
		return err
	}

	_, err = tx.ExecContext(ctx, `INSERT INTO public_collection_tokens
    (collection_id, access_token, valid_till, device_limit, enable_collect, enable_comment, enable_join) VALUES ($1, $2, $3, $4, $5, $6, $7)`,
		cID, token, validTill, deviceLimit, enableCollect, enableComment, join)
	if err != nil && err.Error() == "pq: duplicate key value violates unique constraint \"public_active_collection_unique_idx\"" {
		return ente.ErrActiveLinkAlreadyExists
	}
	if err != nil {
		return stacktrace.Propagate(err, "failed to insert")
	}

	if err = tx.Commit(); err != nil {
		return stacktrace.Propagate(err, "failed to commit collection token insert")
	}
	return nil
}

func (pcr *CollectionLinkRepo) DisableSharing(ctx context.Context, cID int64) error {
	_, err := pcr.DB.ExecContext(ctx, `UPDATE public_collection_tokens SET is_disabled = true where
                                                             collection_id = $1 and is_disabled = false`, cID)
	return stacktrace.Propagate(err, "failed to disable sharing")
}

// GetCollectionToActivePublicURLMap will return map of collectionID to PublicURLs which are not disabled yet.
// Note: The url could be expired or deviceLimit is already reached
func (pcr *CollectionLinkRepo) GetCollectionToActivePublicURLMap(ctx context.Context, collectionIDs []int64, app ente.App) (map[int64][]ente.PublicURL, error) {
	rows, err := pcr.DB.QueryContext(ctx, `SELECT collection_id, access_token, valid_till, device_limit, enable_download, enable_collect, enable_comment, enable_join, min_role, pw_nonce, mem_limit, ops_limit FROM
                                                   public_collection_tokens WHERE collection_id = ANY($1) and is_disabled = FALSE`,
		pq.Array(collectionIDs))
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	result := make(map[int64][]ente.PublicURL, 0)
	for _, cID := range collectionIDs {
		result[cID] = make([]ente.PublicURL, 0)
	}
	for rows.Next() {
		publicUrl := ente.PublicURL{}
		var collectionID int64
		var accessToken string
		var nonce *string
		var opsLimit, memLimit *int64
		var minRole sql.NullString
		if err = rows.Scan(&collectionID, &accessToken, &publicUrl.ValidTill, &publicUrl.DeviceLimit, &publicUrl.EnableDownload, &publicUrl.EnableCollect, &publicUrl.EnableComment, &publicUrl.EnableJoin, &minRole, &nonce, &memLimit, &opsLimit); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		publicUrl.URL = pcr.GetAlbumUrl(app, accessToken)
		if minRole.Valid {
			role := ente.ConvertStringToCollectionParticipantRole(minRole.String)
			rolePtr := role
			publicUrl.MinRole = &rolePtr
		}
		if nonce != nil {
			publicUrl.Nonce = nonce
			publicUrl.MemLimit = memLimit
			publicUrl.OpsLimit = opsLimit
			publicUrl.PasswordEnabled = true
		}
		result[collectionID] = append(result[collectionID], publicUrl)
	}
	return result, nil
}

// GetActiveCollectionLinkRow will return ente.CollectionLinkRow for given collection ID
// Note: The token could be expired or deviceLimit is already reached
func (pcr *CollectionLinkRepo) GetActiveCollectionLinkRow(ctx context.Context, collectionID int64) (ente.CollectionLinkRow, error) {
	row := pcr.DB.QueryRowContext(ctx, `SELECT id, collection_id, access_token, valid_till, device_limit,
       is_disabled, pw_hash, pw_nonce, mem_limit, ops_limit, enable_download, enable_collect, enable_comment, enable_join, min_role FROM
                                                   public_collection_tokens WHERE collection_id = $1 and is_disabled = FALSE`,
		collectionID)

	//defer rows.Close()
	ret := ente.CollectionLinkRow{}
	var minRole sql.NullString
	err := row.Scan(&ret.ID, &ret.CollectionID, &ret.Token, &ret.ValidTill, &ret.DeviceLimit,
		&ret.IsDisabled, &ret.PassHash, &ret.Nonce, &ret.MemLimit, &ret.OpsLimit, &ret.EnableDownload, &ret.EnableCollect, &ret.EnableComment, &ret.EnableJoin, &minRole)
	if err != nil {
		return ente.CollectionLinkRow{}, stacktrace.Propagate(err, "")
	}
	if minRole.Valid {
		role := ente.ConvertStringToCollectionParticipantRole(minRole.String)
		rolePtr := role
		ret.MinRole = &rolePtr
	}
	return ret, nil
}

// UpdatePublicCollectionToken will update the row for corresponding public collection token
func (pcr *CollectionLinkRepo) UpdatePublicCollectionToken(ctx context.Context, pct ente.CollectionLinkRow) error {
	var minRole interface{}
	if pct.MinRole != nil {
		minRole = string(*pct.MinRole)
	}
	_, err := pcr.DB.ExecContext(ctx, `UPDATE public_collection_tokens SET valid_till = $1, device_limit = $2,
                                    pw_hash = $3, pw_nonce = $4, mem_limit = $5, ops_limit = $6, enable_download = $7, enable_collect = $8, enable_comment = $9, enable_join = $10, min_role = $11
                                where id = $12`,
		pct.ValidTill, pct.DeviceLimit, pct.PassHash, pct.Nonce, pct.MemLimit, pct.OpsLimit, pct.EnableDownload, pct.EnableCollect, pct.EnableComment, pct.EnableJoin, minRole, pct.ID)
	return stacktrace.Propagate(err, "failed to update public collection token")
}

// Report-abuse functionality removed; DB left intact.

func (pcr *CollectionLinkRepo) GetUniqueAccessCount(ctx context.Context, shareId int64) (int64, error) {
	row := pcr.DB.QueryRowContext(ctx, `SELECT count(*) FROM public_collection_access_history WHERE share_id = $1`, shareId)
	var count int64 = 0
	err := row.Scan(&count)
	if err != nil {
		return -1, stacktrace.Propagate(err, "")
	}
	return count, nil
}

func (pcr *CollectionLinkRepo) RecordAccessHistory(ctx context.Context, shareID int64, ip string, ua string) error {
	_, err := pcr.DB.ExecContext(ctx, `INSERT INTO public_collection_access_history
    (share_id, ip, user_agent) VALUES ($1, $2, $3)
    ON CONFLICT ON CONSTRAINT unique_access_sid_ip_ua DO NOTHING;`,
		shareID, ip, ua)
	return stacktrace.Propagate(err, "failed to record access history")
}

// AccessedInPast returns true if the given ip, ua agent combination has accessed the url in the past
func (pcr *CollectionLinkRepo) AccessedInPast(ctx context.Context, shareID int64, ip string, ua string) (bool, error) {
	row := pcr.DB.QueryRowContext(ctx, `select share_id from public_collection_access_history where share_id =$1 and ip = $2 and user_agent = $3`,
		shareID, ip, ua)
	var tempID int64
	err := row.Scan(&tempID)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	return true, stacktrace.Propagate(err, "failed to record access history")
}

func (pcr *CollectionLinkRepo) GetCollectionSummaryByToken(ctx context.Context, accessToken string) (ente.PublicCollectionSummary, error) {
	row := pcr.DB.QueryRowContext(ctx,
		`SELECT sct.id, sct.collection_id, sct.is_disabled, sct.valid_till, sct.device_limit, sct.pw_hash, sct.enable_comment,
       sct.created_at, sct.updated_at, count(ah.share_id)
		from public_collection_tokens sct
		LEFT JOIN public_collection_access_history ah ON sct.id = ah.share_id
		where access_token = $1
		group by sct.id`, accessToken)
	var result = ente.PublicCollectionSummary{}
	err := row.Scan(&result.ID, &result.CollectionID, &result.IsDisabled, &result.ValidTill, &result.DeviceLimit,
		&result.PassHash, &result.EnableComment, &result.CreatedAt, &result.UpdatedAt, &result.DeviceAccessCount)
	if err != nil {
		return ente.PublicCollectionSummary{}, stacktrace.Propagate(err, "failed to get public collection summary")
	}
	return result, nil
}

func (pcr *CollectionLinkRepo) GetActivePublicTokenForUser(ctx context.Context, userID int64) ([]int64, error) {
	rows, err := pcr.DB.QueryContext(ctx, `select pt.collection_id from public_collection_tokens pt left join collections c on pt.collection_id = c.collection_id where pt.is_disabled = FALSE and c.owner_id= $1;`, userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	result := make([]int64, 0)
	for rows.Next() {
		var collectionID int64
		err = rows.Scan(&collectionID)
		if err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		result = append(result, collectionID)
	}
	return result, nil
}

// CleanupAccessHistory public_collection_access_history where public_collection_tokens is disabled and the last updated time is older than 30 days
func (pcr *CollectionLinkRepo) CleanupAccessHistory(ctx context.Context) error {
	_, err := pcr.DB.ExecContext(ctx, `DELETE FROM public_collection_access_history WHERE share_id IN (SELECT id FROM public_collection_tokens WHERE is_disabled = TRUE AND updated_at < (now_utc_micro_seconds() - (24::BIGINT * 30 * 60 * 60 * 1000 * 1000)))`)
	if err != nil {
		return stacktrace.Propagate(err, "failed to clean up public collection access history")
	}
	return nil
}
