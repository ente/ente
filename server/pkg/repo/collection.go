package repo

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"github.com/ente/museum/pkg/repo/public"
	"strconv"
	t "time"

	"github.com/prometheus/client_golang/prometheus"

	"github.com/sirupsen/logrus"

	"github.com/ente/stacktrace"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/crypto"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/lib/pq"
)

type CollectionRepository struct {
	DB                  *sql.DB
	FileRepo            *FileRepository
	CollectionLinkRepo  *public.CollectionLinkRepo
	TrashRepo           *TrashRepository
	SecretEncryptionKey []byte
	QueueRepo           *QueueRepository
	LatencyLogger       *prometheus.HistogramVec
}

type SharedCollection struct {
	CollectionID int64
	ToUserID     int64
	FromUserID   int64
}

func (repo *CollectionRepository) Create(c ente.Collection) (ente.Collection, error) {

	if !ente.App(c.App).IsValidForCollection() {
		return ente.Collection{}, ente.ErrInvalidApp
	}

	err := repo.DB.QueryRow(`INSERT INTO collections(owner_id, encrypted_key, key_decryption_nonce, name, encrypted_name, name_decryption_nonce, type, attributes, updation_time, magic_metadata, pub_magic_metadata, app) 
        VALUES($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12) RETURNING collection_id`,
		c.Owner.ID, c.EncryptedKey, c.KeyDecryptionNonce, c.Name, c.EncryptedName, c.NameDecryptionNonce, c.Type, c.Attributes, c.UpdationTime, c.MagicMetadata, c.PublicMagicMetadata, c.App).Scan(&c.ID)
	if err != nil {
		if err.Error() == "pq: duplicate key value violates unique constraint \"collections_favorites_constraint_index\"" ||
			err.Error() == "pq: duplicate key value violates unique constraint \"collections_favorites_constraint_index_v2\"" {
			return ente.Collection{}, ente.ErrFavoriteCollectionAlreadyExist
		} else if err.Error() == "pq: duplicate key value violates unique constraint \"collections_uncategorized_constraint_index_v2\"" {
			return ente.Collection{}, ente.ErrUncategorizeCollectionAlreadyExists
		}
	}
	return c, stacktrace.Propagate(err, "")
}

func (repo *CollectionRepository) Get(collectionID int64) (ente.Collection, error) {
	row := repo.DB.QueryRow(`SELECT collection_id, app, owner_id, encrypted_key, key_decryption_nonce, name, encrypted_name, name_decryption_nonce, type, attributes, updation_time, is_deleted, magic_metadata, pub_magic_metadata
		FROM collections
		WHERE collection_id = $1`, collectionID)
	var c ente.Collection
	var name, encryptedName, nameDecryptionNonce sql.NullString
	if err := row.Scan(&c.ID, &c.App, &c.Owner.ID, &c.EncryptedKey, &c.KeyDecryptionNonce, &name, &encryptedName, &nameDecryptionNonce, &c.Type, &c.Attributes, &c.UpdationTime, &c.IsDeleted, &c.MagicMetadata, &c.PublicMagicMetadata); err != nil {
		return c, stacktrace.Propagate(err, "")
	}
	if name.Valid && len(name.String) > 0 {
		c.Name = name.String
	} else {
		c.EncryptedName = encryptedName.String
		c.NameDecryptionNonce = nameDecryptionNonce.String
	}
	app := ente.Photos
	if len(c.App) > 0 && ente.App(c.App).IsValid() {
		app = ente.App(c.App)
	}
	urlMap, err := repo.CollectionLinkRepo.GetCollectionToActivePublicURLMap(context.Background(), []int64{collectionID}, app)
	if err != nil {
		return ente.Collection{}, stacktrace.Propagate(err, "failed to get publicURL info")
	}
	if publicUrls, ok := urlMap[collectionID]; ok {
		c.PublicURLs = publicUrls
	}
	return c, nil
}

func (repo *CollectionRepository) GetWithSharingDetailsForUser(collectionID int64, actorUserID int64) (ente.Collection, error) {
	c, err := repo.Get(collectionID)
	if err != nil {
		return c, stacktrace.Propagate(err, "")
	}
	sharees, err := repo.GetSharees(collectionID)
	if err != nil {
		return ente.Collection{}, stacktrace.Propagate(err, "failed to get sharees info")
	}
	c.Sharees = sharees

	var encryptedEmail, nonce []byte
	err = repo.DB.QueryRow(`SELECT encrypted_email, email_decryption_nonce FROM users WHERE user_id = $1`, c.Owner.ID).
		Scan(&encryptedEmail, &nonce)
	if err != nil {
		if err == sql.ErrNoRows {
			return c, nil
		}
		return ente.Collection{}, stacktrace.Propagate(err, "failed to fetch owner email")
	}
	if len(encryptedEmail) > 0 && len(nonce) > 0 {
		email, err := crypto.Decrypt(encryptedEmail, repo.SecretEncryptionKey, nonce)
		if err != nil {
			return ente.Collection{}, stacktrace.Propagate(err, "failed to decrypt owner email")
		}
		c.Owner.Email = email
	}
	if actorUserID != c.Owner.ID {
		var encryptedKey sql.NullString
		err := repo.DB.QueryRow(`SELECT encrypted_key FROM collection_shares WHERE collection_id = $1 AND to_user_id = $2 AND is_deleted = $3`,
			collectionID, actorUserID, false).Scan(&encryptedKey)
		if err != nil {
			return ente.Collection{}, stacktrace.Propagate(err, "failed to fetch sharee encrypted key")
		}
		if !encryptedKey.Valid {
			return ente.Collection{}, stacktrace.Propagate(fmt.Errorf("share key missing for user %d collection %d", actorUserID, collectionID), "")
		}
		c.EncryptedKey = encryptedKey.String
	}
	return c, nil
}
func (repo *CollectionRepository) GetCollectionByType(userID int64, collectionType string, app string) (ente.Collection, error) {
	row := repo.DB.QueryRow(`SELECT collection_id, owner_id, encrypted_key, key_decryption_nonce, name, encrypted_name, name_decryption_nonce, type, attributes, updation_time, is_deleted, magic_metadata
        FROM collections
        WHERE owner_id = $1 and type = $2 and app = $3`, userID, collectionType, app)
	var c ente.Collection
	var name, encryptedName, nameDecryptionNonce sql.NullString
	if err := row.Scan(&c.ID, &c.Owner.ID, &c.EncryptedKey, &c.KeyDecryptionNonce, &name, &encryptedName, &nameDecryptionNonce, &c.Type, &c.Attributes, &c.UpdationTime, &c.IsDeleted, &c.MagicMetadata); err != nil {
		return c, stacktrace.Propagate(err, "")
	}
	if name.Valid && len(name.String) > 0 {
		c.Name = name.String
	} else {
		c.EncryptedName = encryptedName.String
		c.NameDecryptionNonce = nameDecryptionNonce.String
	}
	return c, nil
}

func (repo *CollectionRepository) GetCollectionsOwnedByUserV2(userID int64, updationTime int64, app ente.App, limit *int64) ([]ente.Collection, error) {
	query := `
		SELECT 
c.collection_id, c.owner_id, c.encrypted_key,c.key_decryption_nonce, c.name, c.encrypted_name, c.name_decryption_nonce, c.type, c.app, c.attributes, c.updation_time, c.is_deleted, c.magic_metadata, c.pub_magic_metadata,
users.user_id, users.encrypted_email, users.email_decryption_nonce, cs.role_type,
pct.access_token, pct.valid_till, pct.device_limit, pct.created_at, pct.updated_at, pct.pw_hash, pct.pw_nonce, pct.mem_limit, pct.ops_limit, pct.enable_download, pct.enable_collect, pct.enable_comment, pct.enable_join, pct.min_role 
    FROM collections c
    LEFT JOIN collection_shares cs
    ON (cs.collection_id = c.collection_id AND cs.is_deleted = false)
    LEFT JOIN users 
    ON (cs.to_user_id = users.user_id AND users.encrypted_email IS NOT NULL)
    LEFT JOIN public_collection_tokens pct
    ON (pct.collection_id = c.collection_id and pct.is_disabled=FALSE)
    WHERE c.owner_id = $1 AND c.updation_time > $2 and c.app = $3`
	args := []interface{}{userID, updationTime, string(app)}

	if limit != nil {
		query += " ORDER BY c.updation_time ASC LIMIT $4"
		args = append(args, *limit)
	}
	rows, err := repo.DB.Query(query, args...)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	collectionIDToValMap := map[int64]*ente.Collection{}
	addPublicUrlMap := map[string]bool{}
	result := make([]ente.Collection, 0)
	for rows.Next() {
		var c ente.Collection
		var name, encryptedName, nameDecryptionNonce sql.NullString
		var pctDeviceLimit sql.NullInt32
		var pctEnableDownload, pctEnableCollect, pctEnableComment, pctEnableJoin sql.NullBool
		var shareUserID, pctValidTill, pctCreatedAt, pctUpdatedAt, pctMemLimit, pctOpsLimit sql.NullInt64
		var encryptedEmail, nonce []byte
		var shareeRoleType, pctToken, pctPwHash, pctPwNonce, pctMinRole sql.NullString

		if err := rows.Scan(&c.ID, &c.Owner.ID, &c.EncryptedKey, &c.KeyDecryptionNonce, &name, &encryptedName, &nameDecryptionNonce, &c.Type, &c.App, &c.Attributes, &c.UpdationTime, &c.IsDeleted, &c.MagicMetadata, &c.PublicMagicMetadata,
			&shareUserID, &encryptedEmail, &nonce, &shareeRoleType,
			&pctToken, &pctValidTill, &pctDeviceLimit, &pctCreatedAt, &pctUpdatedAt, &pctPwHash, &pctPwNonce, &pctMemLimit, &pctOpsLimit, &pctEnableDownload, &pctEnableCollect, &pctEnableComment, &pctEnableJoin, &pctMinRole); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}

		if _, ok := collectionIDToValMap[c.ID]; !ok {
			if name.Valid && len(name.String) > 0 {
				c.Name = name.String
			} else {
				c.EncryptedName = encryptedName.String
				c.NameDecryptionNonce = nameDecryptionNonce.String
			}
			c.Sharees = make([]ente.CollectionUser, 0)
			c.PublicURLs = make([]ente.PublicURL, 0)
			collectionIDToValMap[c.ID] = &c

		}
		currentCollection := collectionIDToValMap[c.ID]
		if shareUserID.Valid {
			sharedUser := ente.CollectionUser{
				ID:   shareUserID.Int64,
				Role: ente.ConvertStringToCollectionParticipantRole(shareeRoleType.String),
			}
			email, err := crypto.Decrypt(encryptedEmail, repo.SecretEncryptionKey, nonce)
			if err != nil {
				return nil, stacktrace.Propagate(err, "")
			}
			sharedUser.Email = email
			currentCollection.Sharees = append(currentCollection.Sharees, sharedUser)
		}

		if pctToken.Valid {
			if _, ok := addPublicUrlMap[pctToken.String]; !ok {
				addPublicUrlMap[pctToken.String] = true
				url := ente.PublicURL{
					URL:             repo.CollectionLinkRepo.GetAlbumUrl(app, pctToken.String),
					DeviceLimit:     int(pctDeviceLimit.Int32),
					ValidTill:       pctValidTill.Int64,
					EnableDownload:  pctEnableDownload.Bool,
					EnableCollect:   pctEnableCollect.Bool,
					EnableComment:   pctEnableComment.Bool,
					PasswordEnabled: pctPwNonce.Valid,
					EnableJoin:      pctEnableJoin.Bool,
				}
				if pctPwNonce.Valid {
					url.Nonce = &pctPwNonce.String
					url.MemLimit = &pctMemLimit.Int64
					url.OpsLimit = &pctOpsLimit.Int64
				}
				if pctMinRole.Valid {
					role := ente.ConvertStringToCollectionParticipantRole(pctMinRole.String)
					rolePtr := role
					url.MinRole = &rolePtr
				}
				currentCollection.PublicURLs = append(currentCollection.PublicURLs, url)
			}
		}
	}
	for _, collection := range collectionIDToValMap {
		result = append(result, *collection)
	}
	return result, nil
}

func (repo *CollectionRepository) GetCollectionsSharedWithUser(userID int64, updationTime int64, app ente.App, limit *int64) ([]ente.Collection, error) {
	query := `
		SELECT collections.collection_id, collections.owner_id, users.encrypted_email, users.email_decryption_nonce, collection_shares.encrypted_key, collections.name, collections.encrypted_name, collections.name_decryption_nonce, collections.type, collections.app, collections.pub_magic_metadata, collection_shares.magic_metadata, collections.updation_time, collection_shares.is_deleted, collection_shares.role_type, collection_shares.shared_at
		FROM collections
		INNER JOIN users
			ON collections.owner_id = users.user_id
		INNER JOIN collection_shares
			ON collections.collection_id = collection_shares.collection_id AND collection_shares.to_user_id = $1 AND (collection_shares.updation_time > $2 OR collections.updation_time > $2) AND users.encrypted_email IS NOT NULL AND app = $3`
	args := []interface{}{userID, updationTime, string(app)}
	if limit != nil {
		query += " ORDER BY collections.updation_time ASC LIMIT $4"
		args = append(args, *limit)
	}

	rows, err := repo.DB.Query(query, args...)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()

	collections := make([]ente.Collection, 0)
	shareeRoleByCollection := make(map[int64]ente.CollectionParticipantRole)
	for rows.Next() {
		var c ente.Collection
		var collectionName, encryptedName, nameDecryptionNonce sql.NullString
		var encryptedEmail, emailDecryptionNonce []byte
		var roleType sql.NullString
		var sharedAt sql.NullInt64
		if err := rows.Scan(&c.ID, &c.Owner.ID, &encryptedEmail, &emailDecryptionNonce, &c.EncryptedKey, &collectionName, &encryptedName, &nameDecryptionNonce, &c.Type, &c.App, &c.PublicMagicMetadata, &c.SharedMagicMetadata, &c.UpdationTime, &c.IsDeleted, &roleType, &sharedAt); err != nil {
			return collections, stacktrace.Propagate(err, "")
		}
		if sharedAt.Valid {
			sharedAtValue := sharedAt.Int64
			c.SharedAt = &sharedAtValue
		}
		if collectionName.Valid && len(collectionName.String) > 0 {
			c.Name = collectionName.String
		} else {
			c.EncryptedName = encryptedName.String
			c.NameDecryptionNonce = nameDecryptionNonce.String
		}
		// Unshared collections appear deleted, and their former owner's email may
		// no longer be decryptable.
		if c.IsDeleted {
			c.Owner.Email = ""
		} else {
			email, err := crypto.Decrypt(encryptedEmail, repo.SecretEncryptionKey, emailDecryptionNonce)
			if err != nil {
				return collections, stacktrace.Propagate(err, "failed to decrypt email")
			}
			c.Owner.Email = email
		}
		// TODO: Pull this information in the previous query
		if c.IsDeleted {
			// Don't expose other sharees after deletion or unsharing.
			c.Sharees = make([]ente.CollectionUser, 0)
		} else {
			sharees, err := repo.GetSharees(c.ID)
			if err != nil {
				return collections, stacktrace.Propagate(err, "")
			}
			c.Sharees = sharees
		}
		role := ente.ConvertStringToCollectionParticipantRole(roleType.String)
		if role == ente.UNKNOWN {
			role = ente.VIEWER
		}
		shareeRoleByCollection[c.ID] = role
		collections = append(collections, c)
	}

	collectionIDs := make([]int64, 0, len(collections))
	for _, collection := range collections {
		if collection.IsDeleted {
			continue
		}
		collectionIDs = append(collectionIDs, collection.ID)
	}
	if len(collectionIDs) > 0 {
		urlMap, err := repo.CollectionLinkRepo.GetCollectionToActivePublicURLMap(context.Background(), collectionIDs, app)
		if err != nil {
			return nil, stacktrace.Propagate(err, "failed to get public URLs")
		}
		for idx := range collections {
			if collections[idx].IsDeleted {
				collections[idx].PublicURLs = []ente.PublicURL{}
				continue
			}
			role := shareeRoleByCollection[collections[idx].ID]
			collections[idx].PublicURLs = ente.FilterPublicURLsForRole(urlMap[collections[idx].ID], role)
		}
	} else {
		for idx := range collections {
			collections[idx].PublicURLs = []ente.PublicURL{}
		}
	}
	return collections, nil
}

func (repo *CollectionRepository) GetCollectionIDsSharedWithUser(userID int64) ([]int64, error) {
	rows, err := repo.DB.Query(`
		SELECT collection_id
		FROM collection_shares
		WHERE collection_shares.to_user_id = $1
		AND collection_shares.is_deleted = $2`, userID, false)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()

	cIDs := make([]int64, 0)
	for rows.Next() {
		var cID int64
		if err := rows.Scan(&cID); err != nil {
			return cIDs, stacktrace.Propagate(err, "")
		}
		cIDs = append(cIDs, cID)
	}
	return cIDs, nil
}

func (repo *CollectionRepository) FilterNonDeletedCollectionIDs(collectionIDs []int64, app ente.App) ([]int64, error) {
	if len(collectionIDs) == 0 {
		return nil, nil
	}
	rows, err := repo.DB.Query(`
		SELECT collection_id
		FROM collections
		WHERE collection_id = ANY($1)
		  AND is_deleted = FALSE
		  AND app = $2
	`, pq.Array(collectionIDs), app)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()

	result := make([]int64, 0, len(collectionIDs))
	for rows.Next() {
		var collectionID int64
		if err := rows.Scan(&collectionID); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		result = append(result, collectionID)
	}
	if err := rows.Err(); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return result, nil
}

func (repo *CollectionRepository) GetCollectionsSharedWithOrByUser(userID int64) ([]int64, error) {
	rows, err := repo.DB.Query(`
		SELECT collection_id
		FROM collection_shares
		WHERE (to_user_id = $1 OR from_user_id = $1)
		AND is_deleted = $2`, userID, false)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()

	cIDs := make([]int64, 0)
	for rows.Next() {
		var cID int64
		if err := rows.Scan(&cID); err != nil {
			return cIDs, stacktrace.Propagate(err, "")
		}
		cIDs = append(cIDs, cID)
	}
	return cIDs, nil

}

func (repo *CollectionRepository) GetCollectionIDsOwnedByUser(userID int64) (map[int64]bool, error) {
	rows, err := repo.DB.Query(`
		SELECT collection_id, is_deleted
		FROM collections
		WHERE owner_id = $1
		AND is_deleted = $2`, userID, false)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()

	result := make(map[int64]bool, 0)

	for rows.Next() {
		var cID int64
		var isDeleted bool
		if err := rows.Scan(&cID, &isDeleted); err != nil {
			return result, stacktrace.Propagate(err, "")
		}
		result[cID] = isDeleted
	}
	return result, nil
}

func (repo *CollectionRepository) GetAllSharedCollections(ctx context.Context, userID int64) ([]SharedCollection, error) {
	rows, err := repo.DB.QueryContext(ctx, `SELECT collection_id, to_user_id, from_user_id
		FROM collection_shares
		WHERE (to_user_id = $1 or from_user_id = $1)
		AND is_deleted = $2`, userID, false)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	result := make([]SharedCollection, 0)
	for rows.Next() {
		logrus.Info("reading row")
		var sharedCollection SharedCollection
		if err := rows.Scan(&sharedCollection.CollectionID, &sharedCollection.ToUserID, &sharedCollection.FromUserID); err != nil {
			logrus.WithError(err).Info("failed to scan")
			return result, stacktrace.Propagate(err, "")
		}
		result = append(result, sharedCollection)
	}
	return result, nil
}

func (repo *CollectionRepository) GetCollectionShareeRole(cID int64, userID int64) (*ente.CollectionParticipantRole, error) {
	var role *ente.CollectionParticipantRole
	err := repo.DB.QueryRow(`(SELECT role_type FROM collection_shares WHERE collection_id = $1 AND to_user_id = $2 AND is_deleted = $3)`,
		cID, userID, false).Scan(&role)
	return role, stacktrace.Propagate(err, "")
}

func (repo *CollectionRepository) GetOwnerID(collectionID int64) (int64, error) {
	row := repo.DB.QueryRow(`SELECT owner_id FROM collections WHERE collection_id = $1`, collectionID)
	var ownerID int64
	err := row.Scan(&ownerID)
	return ownerID, stacktrace.Propagate(err, "failed to get collection owner")
}

func (repo *CollectionRepository) Share(
	collectionID int64,
	fromUserID int64,
	toUserID int64,
	encryptedKey string,
	role ente.CollectionParticipantRole,
	updationTime int64) error {
	context := context.Background()
	tx, err := repo.DB.BeginTx(context, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()
	if role != ente.VIEWER && role != ente.COLLABORATOR && role != ente.ADMIN {
		err = fmt.Errorf("invalid role %s", string(role))
		return stacktrace.Propagate(err, "")
	}
	_, err = tx.ExecContext(context, `INSERT INTO collection_shares(collection_id, from_user_id, to_user_id, encrypted_key, updation_time, role_type, shared_at) VALUES($1, $2, $3, $4, $5, $6, $7)
			ON CONFLICT (collection_id, from_user_id, to_user_id)
			DO UPDATE SET
				is_deleted = FALSE,
				updation_time = $5,
				role_type = $6,
				shared_at = CASE
					WHEN collection_shares.is_deleted = TRUE THEN $7
					ELSE collection_shares.shared_at
				END`,
		collectionID, fromUserID, toUserID, encryptedKey, updationTime, role, updationTime)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	_, err = tx.ExecContext(context, `UPDATE collections SET updation_time = $1 WHERE collection_id = $2`, updationTime, collectionID)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	err = tx.Commit()
	return stacktrace.Propagate(err, "")
}

// ShareAutomatically creates a share without modifying a prior share.
func (repo *CollectionRepository) ShareAutomatically(
	ctx context.Context,
	collectionID int64,
	fromUserID int64,
	toUserID int64,
	encryptedKey string,
	role ente.CollectionParticipantRole,
	updationTime int64,
) (ente.CollectionShareStatus, error) {
	if role != ente.VIEWER && role != ente.COLLABORATOR && role != ente.ADMIN {
		return "", stacktrace.Propagate(fmt.Errorf("invalid role %s", role), "")
	}
	tx, err := repo.DB.BeginTx(ctx, nil)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()

	result, err := tx.ExecContext(ctx, `INSERT INTO collection_shares(
			collection_id, from_user_id, to_user_id, encrypted_key, updation_time,
			role_type, shared_at
		) VALUES($1, $2, $3, $4, $5, $6, $7)
		ON CONFLICT (collection_id, from_user_id, to_user_id)
		DO NOTHING
	`, collectionID, fromUserID, toUserID, encryptedKey, updationTime, role, updationTime)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	if affected == 0 {
		var isDeleted bool
		err := tx.QueryRowContext(ctx, `SELECT is_deleted
			FROM collection_shares
			WHERE collection_id = $1 AND from_user_id = $2 AND to_user_id = $3`,
			collectionID, fromUserID, toUserID).
			Scan(&isDeleted)
		if err != nil {
			return "", stacktrace.Propagate(err, "")
		}
		if isDeleted {
			return ente.CollectionBlockedPriorRemoval, nil
		}
		return ente.CollectionAlreadyShared, nil
	}

	if _, err = tx.ExecContext(ctx, `UPDATE collections SET updation_time = $1 WHERE collection_id = $2`, updationTime, collectionID); err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	if err := tx.Commit(); err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	return ente.CollectionShared, nil
}

func (repo *CollectionRepository) UpdateShareeMetadata(
	collectionID int64,
	ownerUserID int64,
	shareeUserID int64,
	metadata ente.MagicMetadata,
	updationTime int64) error {
	context := context.Background()
	tx, err := repo.DB.BeginTx(context, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	sqlResult, err := tx.ExecContext(context, `UPDATE collection_shares SET magic_metadata = $1, updation_time = $2  WHERE collection_id = $3 AND from_user_id = $4 AND to_user_id = $5 AND is_deleted = $6`,
		metadata, updationTime, collectionID, ownerUserID, shareeUserID, false)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	affected, err := sqlResult.RowsAffected()
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	if affected != 1 {
		tx.Rollback()
		err = fmt.Errorf("invalid number of rows affected %d", affected)
		return stacktrace.Propagate(err, "")
	}

	_, err = tx.ExecContext(context, `UPDATE collections SET updation_time = $1 WHERE collection_id = $2`, updationTime, collectionID)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	err = tx.Commit()
	return stacktrace.Propagate(err, "")
}

func (repo *CollectionRepository) UnShare(collectionID int64, toUserID int64) error {
	_, err := repo.UnShareContext(context.Background(), collectionID, toUserID)
	return err
}

func (repo *CollectionRepository) UnShareContext(
	ctx context.Context,
	collectionID int64,
	toUserID int64,
) (ente.CollectionShareStatus, error) {
	updationTime := time.Microseconds()
	tx, err := repo.DB.BeginTx(ctx, nil)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()

	status := ente.CollectionAlreadyUnshared
	var isDeleted bool
	err = tx.QueryRowContext(ctx, `SELECT is_deleted
		FROM collection_shares
		WHERE collection_id = $1 AND to_user_id = $2
		FOR UPDATE`, collectionID, toUserID).Scan(&isDeleted)
	if errors.Is(err, sql.ErrNoRows) {
		return ente.CollectionNotShared, nil
	}
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	if !isDeleted {
		status = ente.CollectionUnshared
	}
	_, err = tx.ExecContext(ctx, `UPDATE collection_shares
		SET is_deleted = TRUE, updation_time = $1
		WHERE collection_id = $2 AND to_user_id = $3 AND is_deleted = FALSE`,
		updationTime, collectionID, toUserID)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}

	_, err = tx.ExecContext(ctx, `UPDATE collection_files
		SET is_deleted = TRUE, updation_time = $1
		WHERE collection_id = $2 AND f_owner_id = $3 AND is_deleted = FALSE`,
		updationTime, collectionID, toUserID)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	if _, err = tx.ExecContext(ctx, `UPDATE collections SET updation_time = $1
		WHERE collection_id = $2`, updationTime, collectionID); err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	if err := tx.Commit(); err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	return status, nil
}

func (repo *CollectionRepository) AddFiles(
	ctx context.Context,
	collectionID int64,
	collectionOwnerID int64,
	files []ente.CollectionFileItem,
	fileOwnerID int64,
) error {
	tx, err := repo.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()

	fileIDs := make([]int64, 0, len(files))
	for _, file := range files {
		fileIDs = append(fileIDs, file.ID)
	}
	if err := lockFiles(ctx, tx, fileOwnerID, fileIDs); err != nil {
		return stacktrace.Propagate(err, "")
	}
	updationTime := time.Microseconds()
	trashedOrDeletedFileIDs, err := repo.TrashRepo.getFilesInTrashOrDeleted(ctx, tx, fileOwnerID, fileIDs)
	if err != nil {
		return stacktrace.Propagate(err, "failed to check trash state")
	}
	if len(trashedOrDeletedFileIDs) > 0 {
		return stacktrace.Propagate(&ente.ErrFileInTrash, "")
	}
	if err := upsertCollectionFiles(ctx, tx, collectionID, collectionOwnerID, files, fileOwnerID, updationTime); err != nil {
		return stacktrace.Propagate(err, "")
	}
	_, err = tx.ExecContext(ctx, `UPDATE collections SET updation_time = $1
		 WHERE collection_id = $2`, updationTime, collectionID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	err = tx.Commit()
	return stacktrace.Propagate(err, "")
}

func upsertCollectionFiles(
	ctx context.Context,
	tx *sql.Tx,
	collectionID int64,
	collectionOwnerID int64,
	files []ente.CollectionFileItem,
	fileOwnerID int64,
	updationTime int64,
) error {
	if len(files) == 0 {
		return nil
	}

	fileIDs := make([]int64, 0, len(files))
	encryptedKeys := make([]string, 0, len(files))
	keyDecryptionNonces := make([]string, 0, len(files))
	seenFileIDs := make(map[int64]struct{}, len(files))
	for _, file := range files {
		if _, ok := seenFileIDs[file.ID]; ok {
			continue
		}
		seenFileIDs[file.ID] = struct{}{}
		fileIDs = append(fileIDs, file.ID)
		encryptedKeys = append(encryptedKeys, file.EncryptedKey)
		keyDecryptionNonces = append(keyDecryptionNonces, file.KeyDecryptionNonce)
	}

	_, err := tx.ExecContext(ctx, `INSERT INTO collection_files
			(collection_id, file_id, encrypted_key, key_decryption_nonce, is_deleted, updation_time, c_owner_id, f_owner_id)
		SELECT $1, input.file_id, input.encrypted_key, input.key_decryption_nonce, FALSE, $2, $3, $4
		FROM unnest($5::bigint[], $6::text[], $7::text[])
			AS input(file_id, encrypted_key, key_decryption_nonce)
		ORDER BY input.file_id
		ON CONFLICT ON CONSTRAINT unique_collection_files_cid_fid
		DO UPDATE SET
			is_deleted = EXCLUDED.is_deleted,
			updation_time = EXCLUDED.updation_time,
			action_user = NULL,
			action = NULL,
			created_at = CASE
				WHEN collection_files.is_deleted = TRUE AND EXCLUDED.is_deleted = FALSE
					THEN now_utc_micro_seconds()
				ELSE collection_files.created_at
			END`,
		collectionID,
		updationTime,
		collectionOwnerID,
		fileOwnerID,
		pq.Array(fileIDs),
		pq.Array(encryptedKeys),
		pq.Array(keyDecryptionNonces),
	)
	return stacktrace.Propagate(err, "")
}

func (repo *CollectionRepository) RestoreFiles(ctx context.Context, userID int64, collectionID int64, newCollectionFiles []ente.CollectionFileItem) error {
	fileIDs := make([]int64, 0, len(newCollectionFiles))
	for _, newFile := range newCollectionFiles {
		fileIDs = append(fileIDs, newFile.ID)
	}

	tx, err := repo.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()
	if err := lockFiles(ctx, tx, userID, fileIDs); err != nil {
		return stacktrace.Propagate(err, "")
	}
	updationTime := time.Microseconds()
	_, canRestoreAllFiles, err := repo.TrashRepo.getFilesInTrashState(ctx, tx, userID, fileIDs)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if !canRestoreAllFiles {
		return stacktrace.Propagate(ente.ErrBadRequest, "some fileIDs are not restorable")
	}

	if err := upsertCollectionFiles(ctx, tx, collectionID, userID, newCollectionFiles, userID, updationTime); err != nil {
		return stacktrace.Propagate(err, "")
	}
	_, err = tx.ExecContext(ctx, `UPDATE collections SET updation_time = $1
		 WHERE collection_id = $2`, updationTime, collectionID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}

	_, err = tx.ExecContext(ctx, `UPDATE trash SET is_restored = true
		 WHERE user_id = $1 and file_id = ANY ($2)`, userID, pq.Array(fileIDs))
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	return stacktrace.Propagate(tx.Commit(), "")
}

func (repo *CollectionRepository) RemoveFilesV3(context context.Context, collectionID int64, collectionOwnerID int64, fileIDs []int64) error {
	updationTime := time.Microseconds()
	ownerToFileIDs, err := repo.FileRepo.GetOwnerToFileIDsMap(context, fileIDs)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if _, ok := ownerToFileIDs[collectionOwnerID]; ok {
		return errors.New("can not remove files owned by album owner")
	}

	tx, err := repo.DB.BeginTx(context, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	_, err = tx.ExecContext(context, `UPDATE collection_files 
		SET is_deleted = $1, updation_time = $2 WHERE collection_id = $3 AND file_id = ANY($4)`,
		true, updationTime, collectionID, pq.Array(fileIDs))
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	_, err = tx.ExecContext(context, `UPDATE collections SET updation_time = $1
		WHERE collection_id = $2`, updationTime, collectionID)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	err = tx.Commit()
	return stacktrace.Propagate(err, "")
}

func (repo *CollectionRepository) SuggestAction(ctx context.Context, collectionID int64, actorUserID int64, fileIDs []int64, action string) error {
	if len(fileIDs) == 0 {
		return nil
	}
	updationTime := time.Microseconds()
	tx, err := repo.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	_, err = tx.ExecContext(ctx, `UPDATE collection_files
            SET action_user = $1, action = $2, updation_time = $3
            WHERE collection_id = $4 AND file_id = ANY($5)`,
		actorUserID, action, updationTime, collectionID, pq.Array(fileIDs))
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	_, err = tx.ExecContext(ctx, `UPDATE collections SET updation_time = $1 WHERE collection_id = $2`, updationTime, collectionID)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	return tx.Commit()
}

func (repo *CollectionRepository) MoveFiles(ctx context.Context,
	toCollectionID int64, fromCollectionID int64,
	fileItems []ente.CollectionFileItem,
	collectionOwner int64,
	fileOwner int64,
) error {
	if collectionOwner != fileOwner {
		return fmt.Errorf("move is not supported when collection and file onwer are different")
	}
	tx, err := repo.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()
	fileIDs := make([]int64, 0, len(fileItems))
	for _, file := range fileItems {
		fileIDs = append(fileIDs, file.ID)
	}
	if err := lockFiles(ctx, tx, fileOwner, fileIDs); err != nil {
		return stacktrace.Propagate(err, "")
	}
	updationTime := time.Microseconds()
	trashedOrDeletedFileIDs, err := repo.TrashRepo.getFilesInTrashOrDeleted(ctx, tx, fileOwner, fileIDs)
	if err != nil {
		return stacktrace.Propagate(err, "failed to check trash state")
	}
	if len(trashedOrDeletedFileIDs) > 0 {
		return stacktrace.Propagate(&ente.ErrFileInTrash, "")
	}
	if err := upsertCollectionFiles(ctx, tx, toCollectionID, collectionOwner, fileItems, fileOwner, updationTime); err != nil {
		return stacktrace.Propagate(err, "")
	}
	_, err = tx.ExecContext(ctx, `UPDATE collection_files 
		SET is_deleted = $1, updation_time = $2 WHERE collection_id = $3 AND file_id = ANY($4)`,
		true, updationTime, fromCollectionID, pq.Array(fileIDs))
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	_, err = tx.ExecContext(ctx, `UPDATE collections SET updation_time = $1
		 WHERE (collection_id = $2 or collection_id = $3 )`, updationTime, toCollectionID, fromCollectionID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	return stacktrace.Propagate(tx.Commit(), "")
}

func (repo *CollectionRepository) GetDiff(collectionID int64, sinceTime int64, limit int) ([]ente.File, error) {
	startTime := t.Now()
	defer func() {
		repo.LatencyLogger.WithLabelValues("CollectionRepo.GetDiff").
			Observe(float64(t.Since(startTime).Milliseconds()))
	}()
	rows, err := repo.DB.Query(`
        SELECT files.file_id, files.owner_id, collection_files.collection_id, collection_files.c_owner_id,
            collection_files.encrypted_key, collection_files.key_decryption_nonce,
            files.file_decryption_header, files.thumbnail_decryption_header,
            files.metadata_decryption_header, files.encrypted_metadata, files.magic_metadata, files.pub_magic_metadata, 
            files.info, collection_files.action_user, collection_files.action, collection_files.is_deleted, collection_files.updation_time, collection_files.created_at
        FROM files
        INNER JOIN collection_files
        ON collection_files.file_id = files.file_id
            AND collection_files.collection_id = $1
            AND collection_files.updation_time > $2
        ORDER BY collection_files.updation_time LIMIT $3`,
		collectionID, sinceTime, limit)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return convertRowsToFiles(rows)
}

func (repo *CollectionRepository) GetFilesWithVersion(collectionID int64, updateAtTime int64) ([]ente.File, error) {
	startTime := t.Now()
	defer func() {
		repo.LatencyLogger.WithLabelValues("CollectionRepo.GetFilesWithVersion").
			Observe(float64(t.Since(startTime).Milliseconds()))
	}()
	rows, err := repo.DB.Query(`
        SELECT files.file_id, files.owner_id, collection_files.collection_id, collection_files.c_owner_id,
            collection_files.encrypted_key, collection_files.key_decryption_nonce,
            files.file_decryption_header, files.thumbnail_decryption_header,
            files.metadata_decryption_header, files.encrypted_metadata, files.magic_metadata, files.pub_magic_metadata,
            files.info, collection_files.action_user, collection_files.action, collection_files.is_deleted, collection_files.updation_time, collection_files.created_at
        FROM files
        INNER JOIN collection_files
        ON collection_files.file_id = files.file_id
            AND collection_files.collection_id = $1
            AND collection_files.updation_time = $2`,
		collectionID, updateAtTime)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return convertRowsToFiles(rows)
}

func (repo *CollectionRepository) GetFile(collectionID int64, fileID int64) ([]ente.File, error) {
	rows, err := repo.DB.Query(`
        SELECT files.file_id, files.owner_id, collection_files.collection_id, collection_files.c_owner_id,
            collection_files.encrypted_key, collection_files.key_decryption_nonce,
            files.file_decryption_header, files.thumbnail_decryption_header,
            files.metadata_decryption_header, files.encrypted_metadata, files.magic_metadata, files.pub_magic_metadata,
            files.info, collection_files.action_user, collection_files.action, collection_files.is_deleted, collection_files.updation_time, collection_files.created_at
        FROM files
        INNER JOIN collection_files
        ON collection_files.file_id = files.file_id
            AND collection_files.collection_id = $1
            AND collection_files.file_id = $2`,
		collectionID, fileID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	files, err := convertRowsToFiles(rows)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return files, nil
}

func (repo *CollectionRepository) GetSharees(cID int64) ([]ente.CollectionUser, error) {
	rows, err := repo.DB.Query(`
		SELECT users.user_id, users.encrypted_email, users.email_decryption_nonce, collection_shares.role_type
		FROM users
		INNER JOIN collection_shares
		ON (collection_shares.collection_id = $1 AND collection_shares.to_user_id = users.user_id AND collection_shares.is_deleted = $2 AND users.encrypted_email IS NOT NULL)`,
		cID, false)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()

	users := make([]ente.CollectionUser, 0)
	for rows.Next() {
		var user ente.CollectionUser
		var encryptedEmail, nonce []byte
		if err := rows.Scan(&user.ID, &encryptedEmail, &nonce, &user.Role); err != nil {
			return users, stacktrace.Propagate(err, "")
		}
		email, err := crypto.Decrypt(encryptedEmail, repo.SecretEncryptionKey, nonce)
		if err != nil {
			return users, stacktrace.Propagate(err, "")
		}
		user.Email = email
		users = append(users, user)
	}
	return users, nil
}

func convertRowsToFileId(rows *sql.Rows) ([]int64, error) {
	fileIDs := make([]int64, 0)
	defer rows.Close()
	for rows.Next() {
		var fileID int64
		if err := rows.Scan(&fileID); err != nil {
			return fileIDs, stacktrace.Propagate(err, "")
		}
		fileIDs = append(fileIDs, fileID)
	}
	return fileIDs, nil
}

func (repo *CollectionRepository) TrashV3(ctx context.Context, collectionID int64) error {
	log := logrus.WithFields(logrus.Fields{
		"deleting_collection": collectionID,
	})
	collection, err := repo.Get(collectionID)
	if err != nil {
		log.WithError(err).Error("failed to get collection")
		return stacktrace.Propagate(err, "")
	}
	ownerID := collection.Owner.ID
	fileIDs, err := repo.GetCollectionFileIDs(collectionID, ownerID)
	if err != nil {
		log.WithError(err).Error("failed to get fileIDs")
		return stacktrace.Propagate(err, "")
	}
	log.WithField("file_count", len(fileIDs)).Info("Fetched fileIDs")
	batchSize := 2000
	for i := 0; i < len(fileIDs); i += batchSize {
		end := min(i+batchSize, len(fileIDs))
		batch := fileIDs[i:end]
		err := repo.FileRepo.VerifyFileOwner(ctx, batch, ownerID, log)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
		items := make([]ente.TrashItemRequest, 0)
		for _, fileID := range batch {
			items = append(items, ente.TrashItemRequest{
				FileID:       fileID,
				CollectionID: collectionID,
			})
		}
		err = repo.TrashRepo.TrashFiles(ctx, ownerID, ente.TrashRequest{OwnerID: ownerID, TrashItems: items})
		if err != nil {
			log.WithError(err).Error("failed to trash file")
			return stacktrace.Propagate(err, "")
		}
	}
	count, err := repo.GetCollectionsFilesCount(collectionID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if count != 0 {
		removedFiles, removeErr := repo.removeAllFilesAddedByOthers(collectionID, ownerID)
		if removeErr != nil {
			return stacktrace.Propagate(removeErr, "")
		}
		if count != removedFiles {
			return fmt.Errorf("investigate: collection %d still has %d files which are not deleted", collectionID, removedFiles-count)
		} else {
			logrus.WithField("collection_id", collectionID).
				WithField("file_count", count).
				WithField("removed_files", removedFiles).
				Info("All files are removed from the collection")
			return nil
		}
	}
	return nil
}

func (repo *CollectionRepository) removeAllFilesAddedByOthers(collectionID int64, cOwnerID int64) (int64, error) {
	var fileIDs []int64
	rows, err := repo.DB.Query(`SELECT file_id FROM collection_files WHERE collection_id = $1 AND is_deleted=false AND f_owner_id IS NOT NULL AND c_owner_id IS NOT NULL AND f_owner_id <> c_owner_id`, collectionID)
	if err != nil {
		return 0, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	for rows.Next() {
		var fileID int64
		if err := rows.Scan(&fileID); err != nil {
			return 0, stacktrace.Propagate(err, "")
		}
		fileIDs = append(fileIDs, fileID)
	}
	if len(fileIDs) == 0 {
		return 0, nil
	}
	removeErr := repo.RemoveFilesV3(context.Background(), collectionID, cOwnerID, fileIDs)
	if removeErr != nil {
		return 0, stacktrace.Propagate(removeErr, "")
	}
	return int64(len(fileIDs)), nil
}

func (repo *CollectionRepository) ScheduleDelete(collectionID int64) error {
	updationTime := time.Microseconds()
	ctx := context.Background()
	tx, err := repo.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	_, err = tx.ExecContext(ctx, `UPDATE collection_shares 
		SET is_deleted = $1, updation_time = $2 
		WHERE collection_id = $3`, true, updationTime, collectionID)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	_, err = tx.ExecContext(ctx, `UPDATE collections 
		SET is_deleted = $1, updation_time = $2 
		WHERE collection_id = $3`, true, updationTime, collectionID)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	err = repo.QueueRepo.AddItems(ctx, tx, TrashCollectionQueueV3, []string{strconv.FormatInt(collectionID, 10)})
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	err = tx.Commit()
	return stacktrace.Propagate(err, "")
}

func (repo *CollectionRepository) Rename(collectionID int64, encryptedName string, nameDecryptionNonce string) error {
	updationTime := time.Microseconds()
	_, err := repo.DB.Exec(`UPDATE collections 
				SET encrypted_name = $1,
					name_decryption_nonce=$2,
					updation_time=$3
				WHERE collection_id = $4`,
		encryptedName, nameDecryptionNonce, updationTime, collectionID)
	return stacktrace.Propagate(err, "")
}

func (repo *CollectionRepository) UpdateMagicMetadata(ctx context.Context,
	collectionID int64,
	magicMetadata ente.MagicMetadata,
	isPublicMetadata bool,
) error {
	updationTime := time.Microseconds()
	magicMetadata.Version = magicMetadata.Version + 1
	var err error
	if isPublicMetadata {
		_, err = repo.DB.ExecContext(ctx, `UPDATE collections
    				SET pub_magic_metadata = $1,
    				    updation_time=$2
					WHERE collection_id = $3`,
			magicMetadata, updationTime, collectionID)
	} else {
		_, err = repo.DB.ExecContext(ctx, `UPDATE collections 
				SET magic_metadata = $1,
					updation_time=$2
				WHERE collection_id = $3`,
			magicMetadata, updationTime, collectionID)
	}
	return stacktrace.Propagate(err, "")
}
