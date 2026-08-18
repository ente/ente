package authenticaor

import (
	"github.com/ente/museum/ente"
	model "github.com/ente/museum/ente/userentity"
	"github.com/ente/museum/pkg/repo/userentity"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
)

type Controller struct {
	Repo *userentity.Repository
}

func (c *Controller) CreateKey(ctx *gin.Context, req model.EntityKeyRequest) error {
	userID := auth.GetUserID(ctx.Request.Header)
	return c.Repo.CreateKey(ctx, userID, req)
}

func (c *Controller) EnsureKey(ctx *gin.Context, req model.EntityKeyRequest) (*model.EntityKey, error) {
	userID := auth.GetUserID(ctx.Request.Header)
	res, err := c.Repo.EnsureKey(ctx, userID, req)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &res, nil
}

func (c *Controller) GetKey(ctx *gin.Context, req model.GetEntityKeyRequest) (*model.EntityKey, error) {
	userID := auth.GetUserID(ctx.Request.Header)
	res, err := c.Repo.GetKey(ctx, userID, req.Type)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &res, nil
}

func (c *Controller) CreateEntity(ctx *gin.Context, req model.EntityDataRequest) (*model.EntityData, error) {
	userID := auth.GetUserID(ctx.Request.Header)
	if err := req.IsValid(userID); err != nil {
		return nil, stacktrace.Propagate(err, "invalid EntityDataRequest")
	}
	id, err := c.Repo.Create(ctx, userID, req)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to createEntity")
	}
	return c.Repo.Get(ctx, userID, id)
}

func (c *Controller) UpdateEntity(ctx *gin.Context, req model.UpdateEntityDataRequest) (*model.EntityData, error) {
	userID := auth.GetUserID(ctx.Request.Header)
	if err := req.IsValid(); err != nil {
		return nil, stacktrace.Propagate(err, "invalid UpdateEntityDataRequest")
	}
	err := c.Repo.Update(ctx, userID, req)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to updateEntity")
	}
	return c.Repo.Get(ctx, userID, req.ID)
}

func (c *Controller) Delete(ctx *gin.Context, entityID string) (bool, error) {
	userID := auth.GetUserID(ctx.Request.Header)
	return c.Repo.Delete(ctx, userID, entityID)
}

func (c *Controller) GetDiff(ctx *gin.Context, req model.GetEntityDiffRequest) ([]model.EntityData, error) {
	if req.Limit <= 0 || req.Limit > 5000 {
		return nil, ente.NewBadRequestWithMessage("limit must be between 1 and 5000")
	}
	userID := auth.GetUserID(ctx.Request.Header)
	return c.Repo.GetDiff(ctx, userID, req.Type, *req.SinceTime, req.Limit)
}
