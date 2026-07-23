package access

import (
	"github.com/ente/museum/ente"
	enteArray "github.com/ente/museum/pkg/utils/array"
	"github.com/ente/stacktrace"
	"github.com/gin-contrib/requestid"
	"github.com/gin-gonic/gin"
	log "github.com/sirupsen/logrus"
)

type VerifyFileOwnershipParams struct {
	// userID of the user trying to fetch the controller
	ActorUserId int64
	FileIDs     []int64
}

type CanAccessFileParams struct {
	ActorUserID int64
	FileIDs     []int64
}

// VerifyFileOwnership will return error if given fileIDs are not valid or don't belong to the ownerID
func (c controllerImpl) VerifyFileOwnership(ctx *gin.Context, req *VerifyFileOwnershipParams) error {
	if enteArray.ContainsDuplicateInInt64Array(req.FileIDs) {
		return stacktrace.Propagate(ente.ErrBadRequest, "duplicate fileIDs")
	}
	ownerID := req.ActorUserId
	logger := log.WithFields(log.Fields{
		"req_id": requestid.Get(ctx),
	})
	return c.FileRepo.VerifyFileOwner(ctx, req.FileIDs, ownerID, logger)
}
func (c controllerImpl) CanAccessFile(ctx *gin.Context, req *CanAccessFileParams) error {
	if enteArray.ContainsDuplicateInInt64Array(req.FileIDs) {
		return stacktrace.Propagate(ente.ErrBadRequest, "duplicate fileIDs")
	}

	ownerToFilesMap, err := c.FileRepo.GetOwnerToFileIDsMap(ctx, req.FileIDs)
	if err != nil {
		return stacktrace.Propagate(err, "failed to get owner to fileIDs map")
	}

	// Only fetch shared collections once when needed
	var sharedCollections []int64
	for owner, fileIDs := range ownerToFilesMap {
		if owner == req.ActorUserID {
			continue
		}

		// Lazy load collections only when we need to check permissions
		if sharedCollections == nil {
			sharedCollections, err = c.CollectionRepo.GetCollectionsSharedWithOrByUser(req.ActorUserID)
			if err != nil {
				return stacktrace.Propagate(err, "failed to get shared collections")
			}
		}
		if existsErr := c.CollectionRepo.DoAllFilesExistInGivenCollections(fileIDs, sharedCollections); existsErr != nil {
			log.WithFields(log.Fields{
				"req_id":            requestid.Get(ctx),
				"sharedCollections": sharedCollections,
				"fileIDs":           fileIDs,
			}).WithError(existsErr).Error("access check failed")
			return stacktrace.Propagate(ente.ErrPermissionDenied, "access denied")
		}
	}
	return nil
}
