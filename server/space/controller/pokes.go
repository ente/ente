package controller

import (
	"context"
	"database/sql"
	"errors"
	"strings"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/space/models"
	"github.com/ente/museum/space/repo"
	"github.com/ente/stacktrace"
)

type PokesController struct {
	PokesRepo        *repo.PokesRepository
	SpacesRepo       *repo.SpacesRepository
	ActivityNotifier SpaceActivityNotifier
	auth             authDeps
}

func (c *PokesController) Create(ctx context.Context, sender *repo.SpaceRecord, targetSpaceID string, req models.CreatePokeRequest) error {
	requestID := strings.TrimSpace(req.ClientRequestID)
	if requestID == "" || len(requestID) > 64 {
		return ente.NewBadRequestWithMessage("invalid poke request ID")
	}
	recipient, err := c.SpacesRepo.GetSpaceByID(ctx, strings.TrimSpace(targetSpaceID))
	if err != nil {
		return err
	}
	if recipient.OwnerID == sender.OwnerID {
		return ente.NewBadRequestWithMessage("cannot poke your own space")
	}
	if err := c.auth.requireActiveSpaceOwner(ctx, recipient); err != nil {
		return err
	}
	created, err := c.PokesRepo.Create(ctx, sender.SpaceID, recipient.SpaceID, requestID)
	if errors.Is(stacktrace.RootCause(err), sql.ErrNoRows) {
		return ente.ErrPermissionDenied
	}
	if err != nil {
		return err
	}
	if created {
		go c.ActivityNotifier.OnSpacePokeSent(spaceActivityActor(sender), recipient.OwnerID)
	}
	return nil
}
