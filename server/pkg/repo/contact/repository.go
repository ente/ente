package contact

import (
	"database/sql"

	"github.com/ente/museum/pkg/repo"
)

const (
	ReplicationColumn = "replicated_buckets"
	DeletionColumn    = "delete_from_buckets"
	InflightRepColumn = "inflight_rep_buckets"
)

type Repository struct {
	DB                  *sql.DB
	ObjectCleanupRepo   *repo.ObjectCleanupRepository
	SecretEncryptionKey []byte
}
