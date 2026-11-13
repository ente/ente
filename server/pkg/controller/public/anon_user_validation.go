package public

import (
	"context"
	"database/sql"
	"errors"

	"github.com/ente/museum/ente"
	socialcontroller "github.com/ente/museum/pkg/controller/social"
	socialrepo "github.com/ente/museum/pkg/repo/social"
	"github.com/ente/stacktrace"
)

func ensureAnonUserForCollection(ctx context.Context, repo *socialrepo.AnonUsersRepository, collectionID int64, actor socialcontroller.Actor) error {
	if repo == nil || !actor.IsAnonymous() {
		return nil
	}
	if actor.AnonUserID == nil || *actor.AnonUserID == "" {
		return ente.ErrBadRequest
	}
	anonUser, err := repo.GetByID(ctx, *actor.AnonUserID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return ente.ErrAuthenticationRequired
		}
		return stacktrace.Propagate(err, "")
	}
	if anonUser.CollectionID != collectionID {
		return ente.ErrPermissionDenied
	}
	return nil
}
