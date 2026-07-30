package controller

import (
	"net/http"
	"strings"

	"github.com/ente/museum/ente"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/viper"
)

const spaceAssetsPrimaryBucketConfigKey = "space.assets.primaryBucket"

type spaceAssetBucketConfig interface {
	IsBucketActive(bucketID string) bool
}

func resolveSpaceAssetsBucketID(buckets spaceAssetBucketConfig) (string, error) {
	return validateSpaceAssetsBucketID(viper.GetString(spaceAssetsPrimaryBucketConfigKey), buckets)
}

func validateSpaceAssetsBucketID(rawBucketID string, buckets spaceAssetBucketConfig) (string, error) {
	bucketID := strings.TrimSpace(rawBucketID)
	if bucketID == "" {
		log.WithField("config_key", spaceAssetsPrimaryBucketConfigKey).Error("space asset bucket is not configured")
		return "", newSpaceAssetsUnavailableError()
	}
	if buckets == nil {
		log.WithFields(log.Fields{
			"bucket_id":   bucketID,
			"config_key":  spaceAssetsPrimaryBucketConfigKey,
			"config_type": "s3",
		}).Error("space asset bucket cannot be validated")
		return "", newSpaceAssetsUnavailableError()
	}
	if !buckets.IsBucketActive(bucketID) {
		log.WithFields(log.Fields{
			"bucket_id":  bucketID,
			"config_key": spaceAssetsPrimaryBucketConfigKey,
		}).Error("space asset bucket is not active")
		return "", newSpaceAssetsUnavailableError()
	}
	return bucketID, nil
}

func newSpaceAssetsUnavailableError() *ente.ApiError {
	return &ente.ApiError{
		Code:           ente.ErrorCode("SPACE_ASSETS_UNAVAILABLE"),
		Message:        "space asset storage is unavailable",
		HttpStatusCode: http.StatusServiceUnavailable,
	}
}
