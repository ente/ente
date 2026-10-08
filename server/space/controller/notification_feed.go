package controller

import (
	"context"

	"github.com/ente/museum/space/models"
	"github.com/ente/museum/space/repo"
)

type NotificationsController struct {
	NotificationsRepo *repo.NotificationsRepository
	PostsRepo         *repo.PostsRepository
}

func (c *NotificationsController) List(ctx context.Context, space *repo.SpaceRecord, req models.ListNotificationsRequest) (*models.NotificationPage, error) {
	records, cursor, err := c.NotificationsRepo.List(ctx, space.SpaceID, req.Cursor, req.Limit)
	if err != nil {
		return nil, err
	}
	items := make([]models.NotificationResponse, 0, len(records))
	for _, record := range records {
		item := models.NotificationResponse{
			NotificationID: record.NotificationID,
			Kind:           record.Kind,
			Actors:         make([]models.SpaceActorResponse, 0, len(record.Actors)),
			ActorCount:     record.ActorCount,
			CreatedAt:      formatMicros(record.CreatedAt),
			Unread:         record.Unread,
		}
		if record.PostID.Valid {
			item.PostID = &record.PostID.Int64
		}
		if record.FriendRequestID.Valid {
			item.FriendRequestID = &record.FriendRequestID.Int64
		}
		for _, actor := range record.Actors {
			response := toActorResponse(actor, true)
			if record.Kind == "friend_request" {
				response.EncryptedProfile = ""
				response.Avatar = nil
			}
			item.Actors = append(item.Actors, response)
		}
		items = append(items, item)
	}
	latestPostCreatedAt, err := c.PostsRepo.LatestPostCreatedAt(ctx, space.SpaceID)
	if err != nil {
		return nil, err
	}
	page := &models.NotificationPage{Items: items, NextCursor: cursor}
	if latestPostCreatedAt > 0 {
		page.LatestPostCreatedAt = formatMicros(latestPostCreatedAt)
	}
	return page, nil
}

func (c *NotificationsController) Unread(ctx context.Context, space *repo.SpaceRecord) (*models.NotificationUnreadResponse, error) {
	unread, err := c.NotificationsRepo.HasUnread(ctx, space.SpaceID)
	if err != nil {
		return nil, err
	}
	return &models.NotificationUnreadResponse{Unread: unread}, nil
}

func (c *NotificationsController) MarkRead(ctx context.Context, space *repo.SpaceRecord, req models.ReadNotificationsRequest) error {
	return c.NotificationsRepo.MarkRead(ctx, space.SpaceID, req.NotificationIDs)
}
