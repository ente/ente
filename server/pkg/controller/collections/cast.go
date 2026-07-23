package collections

import (
	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/stacktrace"
	"github.com/gin-contrib/requestid"
	"github.com/gin-gonic/gin"
	log "github.com/sirupsen/logrus"
)

func (c *CollectionController) GetCastCollection(ctx *gin.Context) (*ente.Collection, error) {
	castCtx := auth.GetCastCtx(ctx)
	collection, err := c.CollectionRepo.Get(castCtx.CollectionID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	if collection.IsDeleted {
		return nil, stacktrace.Propagate(ente.ErrNotFound, "collection is deleted")
	}
	return &collection, nil
}

// GetCastDiff returns the changes in the collections since a timestamp, along with hasMore bool flag.
func (c *CollectionController) GetCastDiff(ctx *gin.Context, sinceTime int64) ([]ente.File, bool, error) {
	castCtx := auth.GetCastCtx(ctx)
	collectionID := castCtx.CollectionID
	reqContextLogger := log.WithFields(log.Fields{
		"collection_id": collectionID,
		"since_time":    sinceTime,
		"req_id":        requestid.Get(ctx),
	})
	diff, hasMore, err := c.getDiff(collectionID, sinceTime, CollectionDiffLimit, reqContextLogger)
	if err != nil {
		return nil, false, stacktrace.Propagate(err, "")
	}
	// hide private metadata before returning files info in diff
	for idx := range diff {
		if diff[idx].MagicMetadata != nil {
			diff[idx].MagicMetadata = nil
		}
		// For cast diffs, treat action markers as deleted and strip action details
		if diff[idx].Action != nil && !diff[idx].IsDeleted {
			if *diff[idx].Action == ente.ActionRemove || *diff[idx].Action == ente.ActionDeleteSuggested {
				diff[idx].IsDeleted = true
			}
		}
		diff[idx].Action = nil
		diff[idx].ActionUserID = nil
		if diff[idx].Metadata.EncryptedData == "-" && !diff[idx].IsDeleted {
			// This indicates that the file is deleted, but we still have a stale entry in the collection
			reqContextLogger.WithFields(log.Fields{
				"file_id":    diff[idx].ID,
				"updated_at": diff[idx].UpdationTime,
			}).Warning("stale collection_file found")
			diff[idx].IsDeleted = true
		}
	}
	return diff, hasMore, nil
}
