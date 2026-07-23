package repo

import (
	"context"
	"database/sql"

	"github.com/ente/stacktrace"
)

func (r *AssetsRepository) GetAssetBucketID(ctx context.Context, spaceID, objectKey string) (string, error) {
	if keySpaceID, assetType, objectID, ok := ParseProfileAssetObjectKey(objectKey); ok {
		if keySpaceID != spaceID {
			return "", sql.ErrNoRows
		}
		return r.GetProfileAssetBucketID(ctx, spaceID, assetType, objectID)
	}
	var bucketID string
	err := r.DB.QueryRowContext(ctx, `
		SELECT a.bucket_id
		FROM space_post_assets a
		JOIN space_posts p ON p.post_id = a.post_id
		WHERE p.space_id = $1 AND a.object_key = $2 AND p.is_deleted = FALSE
		LIMIT 1
	`, spaceID, objectKey).Scan(&bucketID)
	return bucketID, stacktrace.Propagate(err, "")
}

func (r *AssetsRepository) GetProfileAssetBucketID(ctx context.Context, spaceID, assetType, objectID string) (string, error) {
	var bucketID string
	err := r.DB.QueryRowContext(ctx, `
		SELECT bucket_id
		FROM space_profile_assets
		WHERE space_id = $1 AND asset_type = $2 AND object_id = $3
	`, spaceID, assetType, objectID).Scan(&bucketID)
	return bucketID, stacktrace.Propagate(err, "")
}
