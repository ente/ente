package s3config

import (
	"fmt"
	"strings"
)

type AttachmentConfig struct {
	ObjectBucketConfig map[string]ObjectBucketConfig `mapstructure:"attachment-config"`
}

func (a AttachmentConfig) HasConfig(attachmentType string) bool {
	_, ok := a.ObjectBucketConfig[attachmentKey(attachmentType)]
	return ok
}

func (a AttachmentConfig) GetPrimaryBucketID(attachmentType string) string {
	config, ok := a.ObjectBucketConfig[attachmentKey(attachmentType)]
	if !ok {
		panic(fmt.Sprintf("no config for attachment type: %s, use HasConfig", attachmentType))
	}
	return config.PrimaryBucket
}

func (a AttachmentConfig) GetReplicaBuckets(attachmentType string) []string {
	config, ok := a.ObjectBucketConfig[attachmentKey(attachmentType)]
	if !ok {
		panic(fmt.Sprintf("no config for attachment type: %s, use HasConfig", attachmentType))
	}
	return config.ReplicaBuckets
}

func attachmentKey(attachmentType string) string {
	return strings.ToLower(strings.TrimSpace(attachmentType))
}
