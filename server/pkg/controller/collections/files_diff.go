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

func (c *CollectionController) GetDiffV2(ctx *gin.Context, cID int64, userID int64, sinceTime int64, includePending bool) ([]ente.File, bool, error) {
	reqContextLogger := log.WithFields(log.Fields{
		"user_id":       userID,
		"collection_id": cID,
		"since_time":    sinceTime,
		"req_id":        requestid.Get(ctx),
	})
	resp, err := c.AccessCtrl.GetCollection(ctx, &access.GetCollectionParams{
		CollectionID: cID,
		ActorUserID:  userID,
	})
	if err != nil {
		return nil, false, stacktrace.Propagate(err, "failed to verify access")
	}
	includePending = includePending && canModerate(*resp.Role)
	diff, hasMore, err := c.getDiff(cID, sinceTime, CollectionDiffLimit, includePending, reqContextLogger)
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
	scrubDeletedFiles(diff, includePending)
	return diff, hasMore, nil
}

func canModerate(role ente.CollectionParticipantRole) bool {
	return role == ente.OWNER || role == ente.ADMIN
}

func isPendingUpload(file ente.File) bool {
	return file.ModerationStatus != nil && *file.ModerationStatus == ente.ModerationPending
}

func scrubDeletedFiles(files []ente.File, includePending bool) {
	for idx := range files {
		file := &files[idx]
		pending := isPendingUpload(*file)
		if !file.IsDeleted && (!pending || includePending) {
			if !pending {
				file.ModerationStatus, file.AnonUserID = nil, nil
			}
			continue
		}
		files[idx] = ente.File{
			ID:                file.ID,
			OwnerID:           file.OwnerID,
			CollectionID:      file.CollectionID,
			CollectionOwnerID: file.CollectionOwnerID,
			Metadata: ente.FileAttributes{
				EncryptedData: "-",
			},
			IsDeleted:    true,
			UpdationTime: file.UpdationTime,
		}
	}
}

// Never split a version across pages. Results may be smaller or larger than
// limit so every row with the boundary timestamp stays together.
func (c *CollectionController) getDiff(cID int64, sinceTime int64, limit int, includePending bool, logger *log.Entry) ([]ente.File, bool, error) {
	diffLimitPlusOne, err := c.CollectionRepo.GetDiff(cID, sinceTime, limit+1, includePending)
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
	diff, err := c.CollectionRepo.GetFilesWithVersion(cID, lastFileVersion, includePending)
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
