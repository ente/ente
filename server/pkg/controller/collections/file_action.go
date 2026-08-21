package collections

import (
	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller/access"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	log "github.com/sirupsen/logrus"
)

func (c *CollectionController) AddFiles(ctx *gin.Context, userID int64, files []ente.CollectionFileItem, cID int64) error {
	resp, err := c.AccessCtrl.GetCollection(ctx, &access.GetCollectionParams{
		CollectionID:   cID,
		ActorUserID:    userID,
		IncludeDeleted: false,
	})

	if err != nil {
		return stacktrace.Propagate(err, "failed to verify collection access")
	}
	app := auth.GetApp(ctx)
	if resp.Collection.App != string(app) {
		return stacktrace.Propagate(ente.ErrInvalidApp, "app mismatch collection: %s  request ctx app %s", resp.Collection.App, app)
	}
	if !resp.Role.CanAdd() {
		return stacktrace.Propagate(ente.ErrPermissionDenied, "user %d with role %s can not add files", userID, *resp.Role)
	}

	collectionOwnerID := resp.Collection.Owner.ID
	filesOwnerID := userID
	fileIDs := make([]int64, 0)
	for _, file := range files {
		fileIDs = append(fileIDs, file.ID)
	}
	err = c.AccessCtrl.VerifyFileOwnership(ctx, &access.VerifyFileOwnershipParams{
		ActorUserId: userID,
		FileIDs:     fileIDs,
	})

	if err != nil {
		return stacktrace.Propagate(err, "Failed to verify fileOwnership")
	}

	err = c.CollectionRepo.AddFiles(ctx.Request.Context(), cID, collectionOwnerID, files, filesOwnerID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	return nil
}

func (c *CollectionController) RestoreFiles(ctx *gin.Context, userID int64, cID int64, files []ente.CollectionFileItem) error {
	_, err := c.AccessCtrl.GetCollection(ctx, &access.GetCollectionParams{
		CollectionID:   cID,
		ActorUserID:    userID,
		IncludeDeleted: false,
		VerifyOwner:    true,
	})
	if err != nil {
		return stacktrace.Propagate(err, "failed to verify collection access")
	}
	for _, file := range files {
		// todo #perf find owners of all files
		ownerID, err := c.FileRepo.GetOwnerID(file.ID)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
		if ownerID != userID {
			log.WithFields(log.Fields{
				"file_id":  file.ID,
				"owner_id": ownerID,
				"user_id":  userID,
			}).Error("invalid ops: can't add file which isn't owned by user")
			return stacktrace.Propagate(ente.ErrPermissionDenied, "")
		}
	}
	err = c.CollectionRepo.RestoreFiles(ctx.Request.Context(), userID, cID, files)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	return nil
}

func (c *CollectionController) MoveFiles(ctx *gin.Context, req ente.MoveFilesRequest) error {
	userID := auth.GetUserID(ctx.Request.Header)
	r1, err := c.AccessCtrl.GetCollection(ctx, &access.GetCollectionParams{
		CollectionID:   req.FromCollectionID,
		ActorUserID:    userID,
		IncludeDeleted: false,
		VerifyOwner:    true,
	})
	if err != nil {
		return stacktrace.Propagate(err, "failed to verify if actor owns fromCollection")
	}

	r2, err2 := c.AccessCtrl.GetCollection(ctx, &access.GetCollectionParams{
		CollectionID:   req.ToCollectionID,
		ActorUserID:    userID,
		IncludeDeleted: false,
		VerifyOwner:    true,
	})
	if err2 != nil {
		return stacktrace.Propagate(err2, "failed to verify if actor owns toCollection")
	}

	if r2.Collection.App != r1.Collection.App {
		return stacktrace.Propagate(ente.ErrInvalidApp, "move across app not supported %s to %s", r1.Collection.App, r2.Collection.App)
	}

	fileIDs := make([]int64, 0)
	for _, file := range req.Files {
		fileIDs = append(fileIDs, file.ID)
	}
	err = c.AccessCtrl.VerifyFileOwnership(ctx, &access.VerifyFileOwnershipParams{
		ActorUserId: userID,
		FileIDs:     fileIDs,
	})
	if err != nil {
		return stacktrace.Propagate(err, "Failed to verify fileOwnership")
	}

	err = c.CollectionRepo.MoveFiles(ctx.Request.Context(), req.ToCollectionID, req.FromCollectionID, req.Files, userID, userID)
	return stacktrace.Propagate(err, "")
}

func (c *CollectionController) RemoveFilesV3(ctx *gin.Context, actorUserID int64, req ente.RemoveFilesV3Request) error {
	accessResp, err := c.AccessCtrl.GetCollection(ctx, &access.GetCollectionParams{
		CollectionID: req.CollectionID,
		ActorUserID:  actorUserID,
		VerifyOwner:  false,
	})
	if err != nil {
		return stacktrace.Propagate(err, "failed to verify collection access")
	}
	collectionOwnerID := accessResp.Collection.Owner.ID
	role := accessResp.Role

	fileIDsToRemove, err := c.CollectionRepo.FilterActiveFileIDsInCollection(ctx, req.CollectionID, req.FileIDs)
	if err != nil {
		return stacktrace.Propagate(err, "file not found in collection")
	}
	if len(fileIDsToRemove) == 0 {
		return nil
	}
	req.FileIDs = fileIDsToRemove

	ownerToFilesMap, err := c.FileRepo.GetOwnerToFileIDsMap(ctx, req.FileIDs)
	if err != nil {
		return stacktrace.Propagate(err, "failed to get owner to fileIDs map")
	}
	if err := c.isRemoveAllowed(ctx, actorUserID, collectionOwnerID, role, ownerToFilesMap); err != nil {
		return stacktrace.Propagate(err, "file removal check failed for others")
	}
	filesOwnedByCollectionOwner := ownerToFilesMap[collectionOwnerID]

	ownerFilesSet := make(map[int64]struct{}, len(filesOwnedByCollectionOwner))
	for _, fid := range filesOwnedByCollectionOwner {
		ownerFilesSet[fid] = struct{}{}
	}
	others := make([]int64, 0, len(req.FileIDs)-len(filesOwnedByCollectionOwner))
	for _, fid := range req.FileIDs {
		if _, found := ownerFilesSet[fid]; !found {
			others = append(others, fid)
		}
	}

	if len(filesOwnedByCollectionOwner) > 0 {
		if role != nil && *role == ente.ADMIN && actorUserID != collectionOwnerID {
			if err := c.CollectionRepo.SuggestAction(ctx, req.CollectionID, actorUserID, filesOwnedByCollectionOwner, ente.ActionRemove); err != nil {
				return stacktrace.Propagate(err, "failed to set remove action for owner's files")
			}
			if err := c.CollectionActionsRepo.CreateBulk(ctx, collectionOwnerID, actorUserID, req.CollectionID, filesOwnedByCollectionOwner, nil, ente.ActionRemove, true); err != nil {
				return stacktrace.Propagate(err, "failed to create collection action REMOVE")
			}
		} else {
			return stacktrace.NewError("actor %d with role %s is not allowed to remove files owned by collectionOwner %d", actorUserID, *role, collectionOwnerID)
		}
	}
	if len(others) > 0 {
		if err := c.CollectionRepo.RemoveFilesV3(ctx, req.CollectionID, collectionOwnerID, others); err != nil {
			return stacktrace.Propagate(err, "failed to remove files")
		}

	}
	return nil
}

func (c *CollectionController) SuggestDeleteInSharedCollection(ctx *gin.Context, req ente.SuggestDeleteRequest) error {
	actorUserID := auth.GetUserID(ctx.Request.Header)
	accessResp, err := c.AccessCtrl.GetCollection(ctx, &access.GetCollectionParams{
		CollectionID: req.CollectionID,
		ActorUserID:  actorUserID,
		VerifyOwner:  false,
	})
	if err != nil {
		return stacktrace.Propagate(err, "failed to verify collection access")
	}
	if accessResp.Role == nil || (*accessResp.Role != ente.OWNER && *accessResp.Role != ente.ADMIN) {
		return stacktrace.Propagate(ente.ErrPermissionDenied, "role not allowed to suggest delete")
	}
	fileIDsToRemove, err := c.CollectionRepo.FilterActiveFileIDsInCollection(ctx, req.CollectionID, req.FileIDs)
	if err != nil {
		return stacktrace.Propagate(err, "file not found in collection")
	}
	if len(fileIDsToRemove) == 0 {
		return nil
	}
	ownerMap, err := c.FileRepo.GetOwnerToFileIDsMap(ctx, fileIDsToRemove)
	if err != nil {
		return stacktrace.Propagate(err, "failed to get owner map")
	}
	if _, ok := ownerMap[actorUserID]; ok {
		return stacktrace.Propagate(ente.ErrPermissionDenied, "can not suggest delete for actor-owned files")
	}
	if removeErr := c.RemoveFilesV3(ctx, actorUserID, ente.RemoveFilesV3Request{
		CollectionID: req.CollectionID,
		FileIDs:      fileIDsToRemove,
	}); removeErr != nil {
		return stacktrace.Propagate(removeErr, "failed to remove files")
	}

	for uid, fids := range ownerMap {
		if err := c.CollectionActionsRepo.CreateBulk(ctx, uid, actorUserID, req.CollectionID, fids, nil, ente.ActionDeleteSuggested, true); err != nil {
			return stacktrace.Propagate(err, "failed to create collection actions for owner files")
		}
	}
	return nil
}

func (c *CollectionController) isRemoveAllowed(ctx *gin.Context,
	actorUserID int64,
	collectionOwnerID int64,
	role *ente.CollectionParticipantRole,
	ownerToFilesMap map[int64][]int64) error {

	if _, ok := ownerToFilesMap[collectionOwnerID]; ok {
		if collectionOwnerID == actorUserID {
			return stacktrace.Propagate(ente.NewBadRequestWithMessage("can not remove files owned collection owner, admins can perform remove suggestion"), "")
		} else if role == nil || *role != ente.ADMIN {
			return stacktrace.Propagate(ente.NewBadRequestWithMessage("can not remove files owned by album owner"), "role %s", *role)
		}
	}
	if collectionOwnerID == actorUserID {
		return nil
	}
	if role != nil && *role == ente.ADMIN {
		return nil
	}
	if len(ownerToFilesMap) > 1 {
		return stacktrace.Propagate(ente.ErrPermissionDenied, "can not remove files owned by others")
	}
	if _, ok := ownerToFilesMap[actorUserID]; !ok {
		return stacktrace.Propagate(ente.ErrPermissionDenied, "can not remove files owned by others")
	}
	return nil
}

func (c *CollectionController) IsCopyAllowed(ctx *gin.Context, actorUserID int64, req ente.CopyFileSyncRequest) error {
	srcCollection, err := c.AccessCtrl.GetCollection(ctx, &access.GetCollectionParams{
		CollectionID: req.SrcCollectionID,
		ActorUserID:  actorUserID,
	})
	if err != nil {
		return stacktrace.Propagate(err, "failed to verify srcCollection access")
	}
	dstCollection, err := c.AccessCtrl.GetCollection(ctx, &access.GetCollectionParams{
		CollectionID: req.DstCollection,
		ActorUserID:  actorUserID,
		VerifyOwner:  true,
	})
	if err != nil {
		return stacktrace.Propagate(err, "failed to ownership of the dstCollection access")
	}
	if srcCollection.Collection.App != dstCollection.Collection.App {
		return stacktrace.Propagate(ente.ErrInvalidApp, "copy across app not supported %s to %s", srcCollection.Collection.App, dstCollection.Collection.App)
	}
	fileIDs := make([]int64, len(req.CollectionFileItems))
	for idx, file := range req.CollectionFileItems {
		fileIDs[idx] = file.ID
	}
	if err := c.CollectionRepo.VerifyAllFileIDsExistsInCollection(ctx, req.SrcCollectionID, fileIDs); err != nil {
		return stacktrace.Propagate(err, "failed to verify fileIDs in srcCollection")
	}
	dsMap, err := c.FileRepo.GetOwnerToFileIDsMap(ctx, fileIDs)
	if err != nil {
		return err
	}
	if _, ok := dsMap[actorUserID]; ok {
		return ente.NewBadRequestWithMessage("can not copy files owned by actor")
	}
	return nil
}
