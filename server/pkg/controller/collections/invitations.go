package collections

import (
	"context"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/gin-gonic/gin"
)

func (c *CollectionController) GetPendingInvitations(ctx context.Context, userID int64, app ente.App) ([]ente.CollectionInvitation, error) {
	if app != ente.Photos {
		return []ente.CollectionInvitation{}, nil
	}
	return c.CollectionRepo.GetPendingInvitations(ctx, userID)
}

func (c *CollectionController) AcceptInvitations(ctx *gin.Context, request ente.AcceptCollectionInvitationsRequest) (ente.AcceptCollectionInvitationsResponse, error) {
	var response ente.AcceptCollectionInvitationsResponse
	if auth.GetApp(ctx) != ente.Photos {
		return response, ente.ErrPermissionDenied
	}
	userID := auth.GetUserID(ctx.Request.Header)
	acceptedIDs, err := c.CollectionRepo.AcceptInvitations(ctx.Request.Context(), userID, request.CollectionIDs)
	if err != nil {
		return response, err
	}
	response.AcceptedCollectionIDs = acceptedIDs
	response.Collections = make([]ente.Collection, 0, len(acceptedIDs))
	for _, collectionID := range acceptedIDs {
		collection, err := c.GetCollection(ctx, userID, collectionID)
		if err != nil {
			return ente.AcceptCollectionInvitationsResponse{}, err
		}
		response.Collections = append(response.Collections, collection)
	}
	return response, nil
}

func (c *CollectionController) RejectInvitation(ctx *gin.Context, request ente.RejectCollectionInvitationRequest) error {
	if auth.GetApp(ctx) != ente.Photos {
		return ente.ErrPermissionDenied
	}
	return c.CollectionRepo.RejectInvitation(ctx.Request.Context(), auth.GetUserID(ctx.Request.Header), request.CollectionID)
}
