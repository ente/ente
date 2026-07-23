package controller

import (
	"context"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/repo"
)

type CollectionActionsController struct {
	Repo *repo.CollectionActionsRepository
}

func (c *CollectionActionsController) ListPendingRemoveActions(ctx context.Context, userID int64, updatedAfter int64, limit int) ([]ente.CollectionAction, error) {
	return c.Repo.ListPendingRemoveActions(ctx, userID, updatedAfter, limit)
}

func (c *CollectionActionsController) ListPendingDeleteSuggestions(ctx context.Context, userID int64, updatedAfter int64, limit int) ([]ente.CollectionAction, error) {
	return c.Repo.ListPendingDeleteSuggestions(ctx, userID, updatedAfter, limit)
}

func (c *CollectionActionsController) RejectDeleteSuggestions(ctx context.Context, userID int64, fileIDs []int64) (int64, error) {
	return c.Repo.RejectDeleteSuggestions(ctx, userID, fileIDs)
}
