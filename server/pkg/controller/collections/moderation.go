package collections

import (
	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller/access"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
)

func (c *CollectionController) ApprovePendingFiles(ctx *gin.Context, req ente.PendingFilesRequest) error {
	if _, err := c.getModeratedCollection(ctx, req.CollectionID); err != nil {
		return err
	}
	return stacktrace.Propagate(c.CollectionRepo.ApprovePendingFiles(ctx, req.CollectionID, req.FileIDs), "")
}

func (c *CollectionController) RejectPendingFiles(ctx *gin.Context, req ente.PendingFilesRequest) error {
	collection, err := c.getModeratedCollection(ctx, req.CollectionID)
	if err != nil {
		return err
	}
	_, err = c.trashPendingFiles(ctx, collection, req.FileIDs, nil, ente.ModerationRejected)
	return err
}

func (c *CollectionController) RemovePendingFile(ctx *gin.Context, fileID int64) error {
	guestID, ok := auth.GetPublicAnonUserID(ctx)
	if !ok {
		return stacktrace.Propagate(ente.ErrPermissionDenied, "")
	}
	collection, err := c.CollectionRepo.Get(auth.MustGetPublicAccessContext(ctx).CollectionID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	fileIDs, err := c.trashPendingFiles(ctx, collection, []int64{fileID}, guestID, ente.ModerationRemoved)
	if err != nil {
		return err
	}
	if len(fileIDs) == 0 {
		return stacktrace.Propagate(ente.ErrNotFound, "")
	}
	return stacktrace.Propagate(c.TrashRepo.Delete(ctx, collection.Owner.ID, fileIDs), "")
}

func (c *CollectionController) getModeratedCollection(ctx *gin.Context, collectionID int64) (ente.Collection, error) {
	resp, err := c.AccessCtrl.GetCollection(ctx, &access.GetCollectionParams{
		CollectionID: collectionID,
		ActorUserID:  auth.GetUserID(ctx.Request.Header),
	})
	if err != nil {
		return ente.Collection{}, stacktrace.Propagate(err, "")
	}
	if !canModerate(*resp.Role) {
		return ente.Collection{}, stacktrace.Propagate(ente.ErrPermissionDenied, "")
	}
	if resp.Collection.App != string(ente.Photos) {
		return ente.Collection{}, stacktrace.Propagate(ente.ErrBadRequest, "")
	}
	return resp.Collection, nil
}

func (c *CollectionController) trashPendingFiles(ctx *gin.Context, collection ente.Collection, fileIDs []int64, anonUserID *string, pendingStatus string) ([]int64, error) {
	pending, err := c.CollectionRepo.GetPendingFileIDs(ctx, collection.ID, fileIDs, anonUserID)
	if err != nil || len(pending) == 0 {
		return nil, stacktrace.Propagate(err, "")
	}
	items := make([]ente.TrashItemRequest, 0, len(pending))
	for _, fileID := range pending {
		items = append(items, ente.TrashItemRequest{FileID: fileID, CollectionID: collection.ID})
	}
	err = c.TrashRepo.TrashFiles(ctx, collection.Owner.ID, ente.TrashRequest{OwnerID: collection.Owner.ID, TrashItems: items}, pendingStatus)
	return pending, stacktrace.Propagate(err, "")
}
