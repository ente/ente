package controller

import (
	"context"
	"database/sql"
	"errors"
	"strings"

	"github.com/ente/museum/ente"
	baserepo "github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/auth"
	spacerepo "github.com/ente/museum/space/repo"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
)

type viewerAuth struct {
	UserID  int64
	SpaceID string
}

type selectedSpaceAuth struct {
	Space *spacerepo.SpaceRecord
}

const selectedSpaceAuthKey = "space.selectedSpaceAuth"

type authDeps struct {
	UserAuthRepo *baserepo.UserAuthRepository
	SpacesRepo   *spacerepo.SpacesRepository
	FriendsRepo  *spacerepo.FriendsRepository
	SessionsRepo *spacerepo.SessionsRepository
}

func (a authDeps) requireUser(c *gin.Context) (int64, error) {
	userID := auth.GetUserID(c.Request.Header)
	if userID <= 0 {
		return 0, ente.ErrAuthenticationRequired
	}
	return userID, nil
}

func (a authDeps) resolveViewer(c *gin.Context, rawViewerSpaceID string) (*viewerAuth, error) {
	viewerSpaceID := strings.TrimSpace(rawViewerSpaceID)
	token := auth.GetToken(c)
	if token != "" && a.UserAuthRepo != nil {
		app := auth.GetApp(c)
		if app != ente.Photos {
			return nil, ente.ErrPermissionDenied
		}
		userID, expired, err := a.UserAuthRepo.GetUserIDWithToken(token, app)
		if err == nil && !expired && userID > 0 {
			viewer := &viewerAuth{UserID: userID}
			if viewerSpaceID != "" {
				space, err := a.requireSpaceOwner(c, userID, viewerSpaceID)
				if err != nil {
					return nil, err
				}
				viewer.SpaceID = space.SpaceID
			}
			return viewer, nil
		}
		if err != nil && !errors.Is(stacktrace.RootCause(err), sql.ErrNoRows) {
			return nil, err
		}
	}
	if sessionToken := strings.TrimSpace(c.GetHeader(SpaceBrowserSessionTokenHeader)); sessionToken != "" {
		session, err := validateBrowserSession(c, a.SessionsRepo, sessionToken)
		if err != nil {
			return nil, err
		}
		viewer := &viewerAuth{UserID: session.UserID}
		if viewerSpaceID != "" {
			space, err := a.requireSpaceOwner(c, session.UserID, viewerSpaceID)
			if err != nil {
				return nil, err
			}
			viewer.SpaceID = space.SpaceID
		}
		return viewer, nil
	}
	return nil, ente.ErrAuthenticationRequired
}

func (a authDeps) requireSelectedSpace(c *gin.Context, rawSpaceID string) (*spacerepo.SpaceRecord, error) {
	userID, err := a.requireUser(c)
	if err != nil {
		return nil, err
	}
	spaceID := strings.TrimSpace(rawSpaceID)
	if spaceID == "" {
		return nil, ente.NewBadRequestWithMessage("spaceId is required")
	}
	space, err := a.requireSpaceOwner(c, userID, spaceID)
	if err != nil {
		return nil, err
	}
	return space, nil
}

func setSelectedSpace(c *gin.Context, space *spacerepo.SpaceRecord) {
	c.Set(selectedSpaceAuthKey, selectedSpaceAuth{Space: space})
}

func selectedSpace(c *gin.Context) (*spacerepo.SpaceRecord, error) {
	value, ok := c.Get(selectedSpaceAuthKey)
	if !ok {
		return nil, ente.NewBadRequestWithMessage("selected space is required")
	}
	selected, ok := value.(selectedSpaceAuth)
	if !ok || selected.Space == nil || strings.TrimSpace(selected.Space.SpaceID) == "" {
		return nil, ente.NewBadRequestWithMessage("selected space is invalid")
	}
	return selected.Space, nil
}

func (a authDeps) requireSpaceOwner(ctx context.Context, ownerID int64, spaceID string) (*spacerepo.SpaceRecord, error) {
	space, err := a.SpacesRepo.GetSpaceByID(ctx, spaceID)
	if err != nil {
		return nil, err
	}
	if space.OwnerID != ownerID {
		return nil, ente.ErrPermissionDenied
	}
	return space, nil
}

func (a authDeps) canViewSpace(ctx context.Context, viewer *viewerAuth, space *spacerepo.SpaceRecord) error {
	if err := a.requireActiveSpaceOwner(ctx, space); err != nil {
		return err
	}
	switch {
	case viewer == nil:
		return ente.ErrAuthenticationRequired
	case viewer.UserID > 0:
		if viewer.UserID == space.OwnerID {
			return nil
		}
		if strings.TrimSpace(viewer.SpaceID) == "" {
			return ente.ErrPermissionDenied
		}
		_, err := a.FriendsRepo.GetShareForFriendAndSpace(ctx, viewer.SpaceID, space.SpaceID)
		if err != nil {
			if errors.Is(stacktrace.RootCause(err), sql.ErrNoRows) {
				return ente.ErrPermissionDenied
			}
			return err
		}
		return nil
	default:
		return ente.ErrAuthenticationRequired
	}
}

func (a authDeps) requireActiveSpaceOwner(ctx context.Context, space *spacerepo.SpaceRecord) error {
	active, err := a.SpacesRepo.IsOwnerActive(ctx, space.OwnerID)
	if err != nil {
		return err
	}
	if !active {
		return ente.ErrNotFound
	}
	return nil
}
