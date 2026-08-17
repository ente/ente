package collections

import (
	"fmt"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller/access"
	"github.com/ente/stacktrace"
	"github.com/gin-contrib/requestid"
	"github.com/gin-gonic/gin"
	log "github.com/sirupsen/logrus"
)

func (c *CollectionController) GetDiffV2(ctx *gin.Context, cID int64, userID int64, sinceTime int64) ([]ente.File, bool, error) {
	reqContextLogger := log.WithFields(log.Fields{
		"user_id":       userID,
		"collection_id": cID,
		"since_time":    sinceTime,
		"req_id":        requestid.Get(ctx),
	})
	_, err := c.AccessCtrl.GetCollection(ctx, &access.GetCollectionParams{
		CollectionID: cID,
		ActorUserID:  userID,
	})
	if err != nil {
		return nil, false, stacktrace.Propagate(err, "failed to verify access")
	}
	diff, hasMore, err := c.getDiff(cID, sinceTime, CollectionDiffLimit, reqContextLogger)
	if err != nil {
		return nil, false, stacktrace.Propagate(err, "")
	}
	for idx := range diff {
		if diff[idx].Action != nil && !diff[idx].IsDeleted {
			if *diff[idx].Action == ente.ActionRemove || *diff[idx].Action == ente.ActionDeleteSuggested {
				if diff[idx].OwnerID != userID { // non-owner view: mask as deleted
					diff[idx].IsDeleted = true
				}
			}
		}
		if diff[idx].OwnerID != userID {
			diff[idx].MagicMetadata = nil
			diff[idx].Action = nil
			diff[idx].ActionUserID = nil
		}
		if diff[idx].Metadata.EncryptedData == "-" && !diff[idx].IsDeleted {
			// "-" marks a deleted file whose collection entry is stale.
			log.WithFields(log.Fields{
				"file_id":       diff[idx].ID,
				"collection_id": cID,
				"updated_at":    diff[idx].UpdationTime,
			}).Warning("stale collection_file found")
			diff[idx].IsDeleted = true
		}
	}
	return diff, hasMore, nil
}

// Never split a version across pages. Results may be smaller or larger than
// limit so every row with the boundary timestamp stays together.
func (c *CollectionController) getDiff(cID int64, sinceTime int64, limit int, logger *log.Entry) ([]ente.File, bool, error) {
	diffLimitPlusOne, err := c.CollectionRepo.GetDiff(cID, sinceTime, limit+1)
	if err != nil {
		return nil, false, stacktrace.Propagate(err, "")
	}
	if len(diffLimitPlusOne) <= limit {
		return diffLimitPlusOne, false, nil
	}
	lastFileVersion := diffLimitPlusOne[limit].UpdationTime
	filteredDiffs := c.removeFilesWithVersion(diffLimitPlusOne, lastFileVersion)
	filteredDiffLen := len(filteredDiffs)

	if filteredDiffLen > 0 {
		if filteredDiffLen < limit {
			logger.
				WithField("last_file_version", lastFileVersion).
				WithField("filtered_diff_len", filteredDiffLen).
				Info(fmt.Sprintf("less than limit (%d) files in diff", limit))
		}
		return filteredDiffs, true, nil
	}
	diff, err := c.CollectionRepo.GetFilesWithVersion(cID, lastFileVersion)
	logger.
		WithField("last_file_version", lastFileVersion).
		WithField("count", len(diff)).
		Info(fmt.Sprintf("more than limit (%d) files with same version", limit))
	if err != nil {
		return nil, false, stacktrace.Propagate(err, "")
	}
	return diff, true, nil
}

// files must be sorted by increasing UpdationTime.
func (c *CollectionController) removeFilesWithVersion(files []ente.File, version int64) []ente.File {
	var i = len(files) - 1
	for ; i >= 0; i-- {
		if files[i].UpdationTime != version {
			break
		}
	}
	return files[0 : i+1]
}
