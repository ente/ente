package s3config

import (
	"fmt"
	"github.com/ente/museum/ente"
	"strings"
)

type ObjectBucketConfig struct {
	PrimaryBucket  string   `mapstructure:"primaryBucket"`
	ReplicaBuckets []string `mapstructure:"replicaBuckets"`
}

type FileDataConfig struct {
	ObjectBucketConfig map[string]ObjectBucketConfig `mapstructure:"file-data-config"`
}

func (f FileDataConfig) HasConfig(objectType ente.ObjectType) bool {
	if objectType == "" || objectType == ente.FILE || objectType == ente.THUMBNAIL {
		panic(fmt.Sprintf("Unsupported object type: %s", objectType))
	}

	_, ok := f.ObjectBucketConfig[key(objectType)]
	return ok
}

func (f FileDataConfig) GetPrimaryBucketID(objectType ente.ObjectType) string {
	config, ok := f.ObjectBucketConfig[key(objectType)]
	if !ok {
		panic(fmt.Sprintf("No config for object type: %s, use HasConfig", key(objectType)))
	}
	return config.PrimaryBucket
}

func (f FileDataConfig) GetReplicaBuckets(objectType ente.ObjectType) []string {
	config, ok := f.ObjectBucketConfig[key(objectType)]
	if !ok {
		panic(fmt.Sprintf("No config for object type: %s, use HasConfig", key(objectType)))
	}
	return config.ReplicaBuckets
}

func key(oType ente.ObjectType) string {
	return strings.ToLower(string(oType))
}
