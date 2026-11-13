package social

import (
	"context"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/stacktrace"
)

type fileCollectionRepository interface {
	GetCollectionFileState(ctx context.Context, collectionID, fileID int64) (repo.CollectionFileState, error)
}

func validateFileInCollection(ctx context.Context, files fileCollectionRepository, collectionID, fileID int64) error {
	state, err := files.GetCollectionFileState(ctx, collectionID, fileID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if state != repo.CollectionFileActive {
		return stacktrace.Propagate(ente.ErrPermissionDenied, "membership_%s", state)
	}
	return nil
}
