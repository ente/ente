package embedding

import (
	"context"
	"database/sql"
	"github.com/ente/stacktrace"
	"github.com/lib/pq"
)

// Repository defines the methods for inserting, updating and retrieving
// ML embedding
type Repository struct {
	DB *sql.DB
}

func (r *Repository) Delete(fileID int64) error {
	_, err := r.DB.Exec("DELETE FROM embeddings WHERE file_id = $1", fileID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	return nil
}

// GetDatacenters returns unique list of datacenters where derived embeddings are stored
func (r *Repository) GetDatacenters(ctx context.Context, fileID int64) ([]string, error) {
	rows, err := r.DB.QueryContext(ctx, `SELECT datacenters FROM embeddings WHERE file_id = $1`, fileID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	uniqueDatacenters := make(map[string]struct{})
	for rows.Next() {
		var datacenters []string
		err = rows.Scan(pq.Array(&datacenters))
		if err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		for _, dc := range datacenters {
			uniqueDatacenters[dc] = struct{}{}
		}
	}
	datacenters := make([]string, 0, len(uniqueDatacenters))
	for dc := range uniqueDatacenters {
		datacenters = append(datacenters, dc)
	}
	return datacenters, nil
}

// RemoveDatacenter removes the given datacenter from the list of datacenters
func (r *Repository) RemoveDatacenter(ctx context.Context, fileID int64, dc string) error {
	_, err := r.DB.ExecContext(ctx, `UPDATE embeddings SET datacenters = array_remove(datacenters, $1) WHERE file_id = $2`, dc, fileID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	return nil
}
