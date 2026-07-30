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

type ReadMarkersController struct {
	ReadMarkersRepo *repo.ReadMarkersRepository
}

func (c *ReadMarkersController) GetUnreadStatus(ctx context.Context, viewerSpace *repo.SpaceRecord) (*models.SpaceUnreadStatusResponse, error) {
	notificationsUnread, err := c.ReadMarkersRepo.HasUnreadNotifications(ctx, viewerSpace.SpaceID)
	if err != nil {
		return nil, err
	}
	return &models.SpaceUnreadStatusResponse{
		NotificationsUnread: notificationsUnread,
	}, nil
}

func (c *ReadMarkersController) MarkNotificationsRead(ctx context.Context, viewerSpace *repo.SpaceRecord, friendSpaceID string) (*models.SpaceUnreadStatusResponse, error) {
	if strings.TrimSpace(friendSpaceID) == "" {
		return nil, ente.NewBadRequestWithMessage("friendSpaceId is required")
	}
	readAt, err := c.ReadMarkersRepo.GetLatestConversationActivityAt(ctx, viewerSpace.SpaceID, friendSpaceID)
	if err != nil {
		if errors.Is(stacktrace.RootCause(err), sql.ErrNoRows) {
			return nil, ente.ErrPermissionDenied
		}
		return nil, err
	}
	if err := c.ReadMarkersRepo.UpsertNotificationReadMarker(ctx, viewerSpace.SpaceID, friendSpaceID, readAt); err != nil {
		return nil, err
	}
	return c.GetUnreadStatus(ctx, viewerSpace)
}
