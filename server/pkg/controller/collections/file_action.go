package collections

import (
	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller/access"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	log "github.com/sirupsen/logrus"
)

// AddFiles adds files to a collection
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
	// Verify that the user owns each file
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

	// Verify that none of the files are in trash or permanently deleted
	trashedOrDeletedFileIDs, err := c.TrashRepo.GetFilesInTrashOrDeleted(ctx, userID, fileIDs)
	if err != nil {
		return stacktrace.Propagate(err, "failed to check trash state")
	}
	if len(trashedOrDeletedFileIDs) > 0 {
		log.WithFields(log.Fields{
			"user_id":                     userID,
			"collection_id":               cID,
			"trashed_or_deleted_file_ids": trashedOrDeletedFileIDs,
		}).Warn("attempt to add trashed or deleted files to collection")
		return stacktrace.Propagate(&ente.ErrFileInTrash, "")
	}

	err = c.CollectionRepo.AddFiles(cID, collectionOwnerID, files, filesOwnerID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	return nil
}

// RestoreFiles restore files from trash and add to the collection
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
	// Verify that the user owns each file
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
	err = c.CollectionRepo.RestoreFiles(ctx, userID, cID, files)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	return nil
}

// MoveFiles from one collection to another collection. Both the collections and files should belong to
// single user
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

	// Verify that the user owns each file
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

	// Verify that none of the files are in trash or permanently deleted
	trashedOrDeletedFileIDs, err := c.TrashRepo.GetFilesInTrashOrDeleted(ctx, userID, fileIDs)
	if err != nil {
		return stacktrace.Propagate(err, "failed to check trash state")
	}
	if len(trashedOrDeletedFileIDs) > 0 {
		log.WithFields(log.Fields{
			"user_id":                     userID,
			"from_collection_id":          req.FromCollectionID,
			"to_collection_id":            req.ToCollectionID,
			"trashed_or_deleted_file_ids": trashedOrDeletedFileIDs,
		}).Warn("attempt to move trashed or deleted files between collections")
		return stacktrace.Propagate(&ente.ErrFileInTrash, "")
	}

	err = c.CollectionRepo.MoveFiles(ctx, req.ToCollectionID, req.FromCollectionID, req.Files, userID, userID)
	return stacktrace.Propagate(err, "") // return nil if err is nil
}

// RemoveFilesV3 enforces all removal rules for shared collections:
//  1. accessCtrl must confirm the actor participates in the collection;
//  2. collaborators/viewers may only remove the files they added themselves;
//  3. the collection owner may remove files added by others but never their own;
//  4. admins can remove anyone's files, but a collection owner's files are only
//     queued for removal (REMOVE action + pending collection_action entry) so
//     the owner can act on them;
//  5. once the validations pass, non-owner files are deleted immediately via
//     CollectionRepo.RemoveFilesV3.
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

	// Validate requested files exist in the target collection and filter already-removed ones.
	fileIDsToRemove, err := c.CollectionRepo.FilterActiveFileIDsInCollection(ctx, req.CollectionID, req.FileIDs)
	if err != nil {
		return stacktrace.Propagate(err, "file not found in collection")
	}
	if len(fileIDsToRemove) == 0 {
		return nil
	}
	req.FileIDs = fileIDsToRemove

	// Partition fileIDs by owner
	ownerToFilesMap, err := c.FileRepo.GetOwnerToFileIDsMap(ctx, req.FileIDs)
	if err != nil {
		return stacktrace.Propagate(err, "failed to get owner to fileIDs map")
	}
	if err := c.isRemoveAllowed(ctx, actorUserID, collectionOwnerID, role, ownerToFilesMap); err != nil {
		return stacktrace.Propagate(err, "file removal check failed for others")
	}
	filesOwnedByCollectionOwner := ownerToFilesMap[collectionOwnerID]

	// Files owned by others (excluding owner)
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

	// If admin is trying to remove owner's files
	if len(filesOwnedByCollectionOwner) > 0 {
		if role != nil && *role == ente.ADMIN && actorUserID != collectionOwnerID {
			// Populate collection_files with action for owner's files
			if err := c.CollectionRepo.SuggestAction(ctx, req.CollectionID, actorUserID, filesOwnedByCollectionOwner, ente.ActionRemove); err != nil {
				return stacktrace.Propagate(err, "failed to set remove action for owner's files")
			}
			if err := c.CollectionActionsRepo.CreateBulk(ctx, collectionOwnerID, actorUserID, req.CollectionID, filesOwnedByCollectionOwner, nil, ente.ActionRemove, true); err != nil {
				return stacktrace.Propagate(err, "failed to create collection action REMOVE")
			}
		} else {
			// unless client is buggy, we should never reach here.
			return stacktrace.NewError("actor %d with role %s is not allowed to remove files owned by collectionOwner %d", actorUserID, *role, collectionOwnerID)
		}
	}
	// Remove files owned by others if allowed
	if len(others) > 0 {
		if err := c.CollectionRepo.RemoveFilesV3(ctx, req.CollectionID, collectionOwnerID, others); err != nil {
			return stacktrace.Propagate(err, "failed to remove files")
		}

	}
	return nil
}

// SuggestDeleteInSharedCollection allows collection owners/admins to nudge other
// participants to delete their files:
//  1. only OWNER/ADMIN roles pass the access check;
//  2. every file ID must belong to the collection and none may belong to the acting user;
//  3. the method internally reuses RemoveFilesV3 to enforce role-based rules and
//     to actually detach the files from the collection;
//  4. each remote owner then receives DELETE_SUGGESTED actions so their clients
//     can surface the pending delete request.
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
	// Only owner or admin can suggest
	if accessResp.Role == nil || (*accessResp.Role != ente.OWNER && *accessResp.Role != ente.ADMIN) {
		return stacktrace.Propagate(ente.ErrPermissionDenied, "role not allowed to suggest delete")
	}
	// Validate fileIDs exist in the collection and filter already-removed ones.
	fileIDsToRemove, err := c.CollectionRepo.FilterActiveFileIDsInCollection(ctx, req.CollectionID, req.FileIDs)
	if err != nil {
		return stacktrace.Propagate(err, "file not found in collection")
	}
	if len(fileIDsToRemove) == 0 {
		return nil
	}
	// Ensure none of the files belong to actor
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

// isRemoveAllowed verifies that given set of files can be removed from the collection or not
func (c *CollectionController) isRemoveAllowed(ctx *gin.Context,
	actorUserID int64,
	collectionOwnerID int64,
	role *ente.CollectionParticipantRole,
	ownerToFilesMap map[int64][]int64) error {

	// verify that none of the file belongs to the collection owner
	if _, ok := ownerToFilesMap[collectionOwnerID]; ok {
		if collectionOwnerID == actorUserID {
			return stacktrace.Propagate(ente.NewBadRequestWithMessage("can not remove files owned collection owner, admins can perform remove suggestion"), "")
		} else if role == nil || *role != ente.ADMIN {
			return stacktrace.Propagate(ente.NewBadRequestWithMessage("can not remove files owned by album owner"), "role %s", *role)
		}
	}
	// allow collection owner to remove files added by others
	if collectionOwnerID == actorUserID {
		return nil
	}
	// allow admins to remove files added by anyone else.
	if role != nil && *role == ente.ADMIN {
		return nil
	}
	// for collaborators and viewers, they should be only removing files added by themselfs.
	// verify that user is only trying to remove files owned by them
	if len(ownerToFilesMap) > 1 {
		return stacktrace.Propagate(ente.ErrPermissionDenied, "can not remove files owned by others")
	}
	// verify that user is only trying to remove files owned by them
	if _, ok := ownerToFilesMap[actorUserID]; !ok {
		return stacktrace.Propagate(ente.ErrPermissionDenied, "can not remove files owned by others")
	}
	return nil
}

func (c *CollectionController) IsCopyAllowed(ctx *gin.Context, actorUserID int64, req ente.CopyFileSyncRequest) error {
	// verify that srcCollectionID is accessible by actorUserID
	srcCollection, err := c.AccessCtrl.GetCollection(ctx, &access.GetCollectionParams{
		CollectionID: req.SrcCollectionID,
		ActorUserID:  actorUserID,
	})
	if err != nil {
		return stacktrace.Propagate(err, "failed to verify srcCollection access")
	}
	// verify that dstCollectionID is owned by actorUserID
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
	// verify that all FileIDs exists in the srcCollection
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
	// verify that none of the file belongs to actorUserID
	if _, ok := dsMap[actorUserID]; ok {
		return ente.NewBadRequestWithMessage("can not copy files owned by actor")
	}
	return nil
}
