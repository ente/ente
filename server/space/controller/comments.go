package controller

import (
	"context"
	"regexp"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/space/models"
	"github.com/ente/museum/space/repo"
)

var commentIDPattern = regexp.MustCompile(`^[A-Za-z0-9_-]{1,64}$`)

type CommentsController struct {
	Repo             *repo.CommentsRepository
	ActivityNotifier SpaceActivityNotifier
}

func discussionActor(actor repo.SpaceActorRecord, private bool) models.SpaceActorResponse {
	response := toActorResponse(actor, private)
	response.SpaceID = actor.SpaceID
	return response
}

func (c *CommentsController) List(ctx context.Context, space *repo.SpaceRecord, postID int64, cursor string) (*models.CommentPage, error) {
	records, next, err := c.Repo.List(ctx, space.SpaceID, postID, cursor)
	if err != nil {
		return nil, err
	}
	page := &models.CommentPage{Items: make([]models.CommentResponse, 0, len(records)), NextCursor: next}
	for _, record := range records {
		item := models.CommentResponse{
			CommentID: record.ID, ParentID: record.ParentID, ReplyToID: record.ReplyToID,
			Cipher: encodeSpaceField(record.Cipher), CreatedAt: formatMicros(record.CreatedAt),
			CanDelete:             record.CanDelete,
			Reactions:             make([]models.CommentReactionResponse, 0, len(record.Reactions)),
			UnreadNotificationIDs: record.UnreadNotificationIDs,
		}
		if record.Author.SpaceID != "" {
			author := discussionActor(record.Author, record.Private)
			item.Author = &author
		}
		for _, reaction := range record.Reactions {
			item.Reactions = append(item.Reactions, models.CommentReactionResponse{
				Actor: discussionActor(reaction.Actor, reaction.Private), Cipher: encodeSpaceField(reaction.Cipher), IsOwn: reaction.Actor.SpaceID == space.SpaceID,
			})
		}
		page.Items = append(page.Items, item)
	}
	return page, nil
}

func (c *CommentsController) Create(ctx context.Context, space *repo.SpaceRecord, postID int64, req models.CreateCommentRequest) error {
	if !commentIDPattern.MatchString(req.CommentID) || (req.ReplyToID != "" && !commentIDPattern.MatchString(req.ReplyToID)) {
		return ente.NewBadRequestWithMessage("invalid comment ID")
	}
	cipher, err := decodeEncodedSpaceField("cipher", req.Cipher, 24*1024, 18*1024)
	if err != nil {
		return err
	}
	created, err := c.Repo.CreateWithCreated(ctx, space.SpaceID, postID, req, cipher)
	if err != nil {
		return err
	}
	if created {
		c.notify(ctx, space, postID, req.CommentID, false)
	}
	return nil
}

func (c *CommentsController) React(ctx context.Context, space *repo.SpaceRecord, postID int64, commentID string, req *models.SetCommentReactionRequest, targetActor string) error {
	if req == nil {
		_, err := c.Repo.React(ctx, space.SpaceID, postID, commentID, nil, targetActor)
		return err
	}
	cipher, err := decodeEncodedSpaceField("cipher", req.Cipher, 2048, 1536)
	if err != nil {
		return err
	}
	notify, err := c.Repo.React(ctx, space.SpaceID, postID, commentID, cipher, "")
	if err != nil {
		return err
	}
	if notify {
		c.notify(ctx, space, postID, commentID, true)
	}
	return nil
}

func (c *CommentsController) notify(ctx context.Context, actor *repo.SpaceRecord, postID int64, commentID string, reaction bool) {
	recipients, owner, err := c.Repo.NotificationRecipients(ctx, actor.SpaceID, postID, commentID, reaction)
	if err != nil {
		return
	}
	go c.ActivityNotifier.OnSpaceComment(spaceActivityActor(actor), recipients, spaceActivityActor(&owner), postID, commentID)
}
