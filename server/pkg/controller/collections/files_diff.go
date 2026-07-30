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

// GetDiffV2 returns the changes in user's collections since a timestamp, along with hasMore bool flag.
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
	// hide private metadata before returning files info in diff
	for idx := range diff {
		// Treat action markers as soft-deletes for non-owners
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
			// This indicates that the file is deleted, but we still have a stale entry in the collection
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

// getDiff returns the diff in user's collection since a timestamp, along with hasMore bool flag.
// The function will never return partial result for a version. To maintain this promise, it will not be able to honor
// the limit parameter. Based on the db state, compared to the limit, the diff length can be
// less (case 1), more (case 2), or same (case 3, 4)
// Example: Assume we have 11 files with following versions: v0, v1, v1, v1, v1, v1, v1, v1, v2, v2, v2 (count = 7 v1, 3 v2)
// client has synced up till version v0.
// case 1: ( sinceTime: v0, limit = 8):
// The method will discard the entries with version v2 and return only 7 entries with version v1.
// case 2: (sinceTime: v0, limit 5):
// Instead of returning 5 entries with version V1, method will return all 7 entries with version v1.
// case 3: (sinceTime: v0, limit 7):
// The method will return all 7 entries with version V1.
// case 4: (sinceTime: v0, limit >=10):
// The method will all 10 entries in the diff
func (c *CollectionController) getDiff(cID int64, sinceTime int64, limit int, logger *log.Entry) ([]ente.File, bool, error) {
	// request for limit +1 files
	diffLimitPlusOne, err := c.CollectionRepo.GetDiff(cID, sinceTime, limit+1)
	if err != nil {
		return nil, false, stacktrace.Propagate(err, "")
	}
	if len(diffLimitPlusOne) <= limit {
		// case 4: all files changed after sinceTime are included.
		return diffLimitPlusOne, false, nil
	}
	lastFileVersion := diffLimitPlusOne[limit].UpdationTime
	filteredDiffs := c.removeFilesWithVersion(diffLimitPlusOne, lastFileVersion)
	filteredDiffLen := len(filteredDiffs)

	if filteredDiffLen > 0 { // case 1 or case 3
		if filteredDiffLen < limit {
			// logging case 1
			logger.
				WithField("last_file_version", lastFileVersion).
				WithField("filtered_diff_len", filteredDiffLen).
				Info(fmt.Sprintf("less than limit (%d) files in diff", limit))
		}
		return filteredDiffs, true, nil
	}
	// case 2
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

// removeFilesWithVersion returns filtered list of files are removing all files with given version.
// Important: The method assumes that files are sorted by increasing order of File.UpdationTime
func (c *CollectionController) removeFilesWithVersion(files []ente.File, version int64) []ente.File {
	var i = len(files) - 1
	for ; i >= 0; i-- {
		if files[i].UpdationTime != version {
			// found index (from end) where file's version is different from given version
			break
		}
	}
	return files[0 : i+1]
}
