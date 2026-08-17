package access

import (
	"github.com/ente/museum/ente"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
)

type GetCollectionParams struct {
	CollectionID   int64
	ActorUserID    int64
	IncludeDeleted bool
	VerifyOwner    bool
	// todo: Add accessType in params for verifying read/write/can-upload/owner types of access
}

type GetCollectionResponse struct {
	Collection ente.Collection
	Role       *ente.CollectionParticipantRole
}

func (c controllerImpl) GetCollection(ctx *gin.Context, req *GetCollectionParams) (*GetCollectionResponse, error) {
	collection, err := c.CollectionRepo.Get(req.CollectionID)
	role := ente.UNKNOWN
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}

	if req.VerifyOwner && req.ActorUserID != collection.Owner.ID {
		return nil, stacktrace.Propagate(ente.ErrPermissionDenied, "actor doesn't owns the collection")
	}

	if req.ActorUserID != collection.Owner.ID {
		shareeRole, err := c.CollectionRepo.GetCollectionShareeRole(req.CollectionID, req.ActorUserID)
		if err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		roleValue := *shareeRole
		role = roleValue
	} else {
		role = ente.OWNER
	}

	if !req.IncludeDeleted && collection.IsDeleted {
		return nil, stacktrace.Propagate(ente.ErrNotFound, "trying to access deleted collection")
	}

	return &GetCollectionResponse{
		Collection: collection,
		Role:       &role,
	}, nil
}
