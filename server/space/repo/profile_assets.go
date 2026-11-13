package repo

import (
	"context"
	"database/sql"
	"fmt"
	"strings"

	"github.com/ente/stacktrace"
)

const (
	ProfileAssetTypeAvatar = "avatar"
	ProfileAssetTypeCover  = "cover"
)

type profileAssetRecord struct {
	SpaceID   string
	AssetType string
	ObjectID  string
	BucketID  string
	Size      sql.NullInt64
}

func ProfileAssetObjectKey(spaceID, assetType, objectID string) string {
	return fmt.Sprintf("space/%s/%s/%s", strings.TrimSpace(spaceID), strings.TrimSpace(assetType), strings.TrimSpace(objectID))
}

func ParseProfileAssetObjectKey(objectKey string) (spaceID, assetType, objectID string, ok bool) {
	parts := strings.Split(strings.TrimSpace(objectKey), "/")
	if len(parts) != 4 || parts[0] != "space" || parts[1] == "" || parts[3] == "" {
		return "", "", "", false
	}
	if !IsProfileAssetType(parts[2]) || !IsProfileAssetObjectID(parts[3]) {
		return "", "", "", false
	}
	return parts[1], parts[2], parts[3], true
}

func IsProfileAssetType(assetType string) bool {
	assetType = strings.TrimSpace(assetType)
	return assetType == ProfileAssetTypeAvatar || assetType == ProfileAssetTypeCover
}

func IsProfileAssetObjectID(objectID string) bool {
	objectID = strings.TrimSpace(objectID)
	return objectID != "" && !strings.Contains(objectID, "/")
}

func getProfileAssetsForUpdateTx(ctx context.Context, tx *sql.Tx, spaceID string) (map[string]profileAssetRecord, error) {
	rows, err := tx.QueryContext(ctx, `
		SELECT space_id, asset_type, object_id, bucket_id, size
		FROM space_profile_assets
		WHERE space_id = $1
		FOR UPDATE
	`, spaceID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()

	assets := make(map[string]profileAssetRecord)
	for rows.Next() {
		var rec profileAssetRecord
		if err := rows.Scan(&rec.SpaceID, &rec.AssetType, &rec.ObjectID, &rec.BucketID, &rec.Size); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		assets[rec.AssetType] = rec
	}
	return assets, stacktrace.Propagate(rows.Err(), "")
}

func upsertProfileAssetTx(ctx context.Context, tx *sql.Tx, spaceID, assetType, objectID, bucketID string, size int64, keyVersion int) error {
	var sizeValue any
	if size > 0 {
		sizeValue = size
	}
	_, err := tx.ExecContext(ctx, `
		INSERT INTO space_profile_assets (space_id, asset_type, object_id, bucket_id, size, key_version)
		VALUES ($1, $2, $3, $4, $5, $6)
		ON CONFLICT (space_id, asset_type)
		DO UPDATE SET object_id = EXCLUDED.object_id,
		              bucket_id = EXCLUDED.bucket_id,
		              size = EXCLUDED.size,
		              key_version = EXCLUDED.key_version
	`, spaceID, assetType, objectID, bucketID, sizeValue, keyVersion)
	return stacktrace.Propagate(err, "")
}

func deleteProfileAssetTx(ctx context.Context, tx *sql.Tx, spaceID, assetType string) error {
	_, err := tx.ExecContext(ctx, `
		DELETE FROM space_profile_assets
		WHERE space_id = $1 AND asset_type = $2
	`, spaceID, assetType)
	return stacktrace.Propagate(err, "")
}

func queueProfileAssetCleanupTx(ctx context.Context, tx *sql.Tx, asset profileAssetRecord, clearSpaceID bool) error {
	size := int64(1)
	if asset.Size.Valid && asset.Size.Int64 > 0 {
		size = asset.Size.Int64
	}
	spaceID := sql.NullString{}
	if !clearSpaceID {
		spaceID = sql.NullString{String: asset.SpaceID, Valid: true}
	}
	return QueueObjectCleanupTx(ctx, tx, SpaceTempObjectRecord{
		ObjectKey:    ProfileAssetObjectKey(asset.SpaceID, asset.AssetType, asset.ObjectID),
		SpaceID:      spaceID,
		Purpose:      asset.AssetType,
		BucketID:     asset.BucketID,
		ExpectedSize: size,
	})
}

func updateProfileAssetTx(ctx context.Context, tx *sql.Tx, spaceID, assetType string, update *ProfileAssetUpdate, remove bool, previous profileAssetRecord, keyVersion int) error {
	hadPrevious := previous.ObjectID != ""
	if remove {
		if err := deleteProfileAssetTx(ctx, tx, spaceID, assetType); err != nil {
			return err
		}
		if hadPrevious {
			return queueProfileAssetCleanupTx(ctx, tx, previous, false)
		}
		return nil
	}
	if update == nil {
		return nil
	}
	objectID := strings.TrimSpace(update.ObjectID)
	if !IsProfileAssetObjectID(objectID) {
		return sql.ErrNoRows
	}
	if err := upsertProfileAssetTx(ctx, tx, spaceID, assetType, objectID, update.BucketID, update.Size, keyVersion); err != nil {
		return err
	}
	objectKey := ProfileAssetObjectKey(spaceID, assetType, objectID)
	if err := ConsumeTempObjectTx(ctx, tx, objectKey, assetType, &spaceID); err != nil {
		return stacktrace.Propagate(err, "failed to consume staged space profile upload")
	}
	if hadPrevious && previous.ObjectID != objectID {
		return queueProfileAssetCleanupTx(ctx, tx, previous, false)
	}
	return nil
}
