package public

import (
	"context"
	"database/sql"
	"errors"
	"sort"

	"github.com/ente/museum/ente"
	socialentity "github.com/ente/museum/ente/social"
	socialcontroller "github.com/ente/museum/pkg/controller/social"
	"github.com/ente/museum/pkg/repo"
	socialrepo "github.com/ente/museum/pkg/repo/social"
	"github.com/ente/museum/pkg/utils/auth"
	emailUtil "github.com/ente/museum/pkg/utils/email"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
)

const maxCommentPayloadSize = 20 * 1024

// CommentsController handles comments exposed via public collection links.
type CommentsController struct {
	CommentCtrl   *socialcontroller.CommentsController
	CommentsRepo  *socialrepo.CommentsRepository
	ReactionsRepo *socialrepo.ReactionsRepository
	UserRepo      *repo.UserRepository
	UserAuthRepo  *repo.UserAuthRepository
	AnonUsersRepo *socialrepo.AnonUsersRepository
	JwtSecret     []byte
}

// CommentRequest models incoming payload for creating a comment.
type CommentRequest struct {
	ID              string  `json:"id"`
	FileID          *int64  `json:"fileID"`
	ParentCommentID *string `json:"parentCommentID"`
	Cipher          string  `json:"cipher" binding:"required"`
	Nonce           string  `json:"nonce" binding:"required"`
	AnonUserID      *string `json:"anonUserID"`
	AnonToken       string  `json:"anonToken"`
}

type CommentUpdateRequest struct {
	Cipher     string  `json:"cipher" binding:"required"`
	Nonce      string  `json:"nonce" binding:"required"`
	AnonUserID *string `json:"anonUserID"`
	AnonToken  string  `json:"anonToken"`
}

type CommentDeleteRequest struct {
	AnonUserID *string `json:"anonUserID"`
	AnonToken  string  `json:"anonToken"`
}

type participant struct {
	UserID      int64  `json:"userID"`
	EmailMasked string `json:"emailMasked"`
}

func (c *CommentsController) CreateComment(ctx *gin.Context, collectionID int64, req CommentRequest) (string, error) {
	if err := ensureCommentsFeatureEnabled(ctx); err != nil {
		return "", err
	}
	if len(req.Cipher) == 0 || len(req.Cipher) > maxCommentPayloadSize {
		return "", ente.ErrBadRequest
	}
	if err := validateEncryptedPayloadLength(req.Cipher, maxCommentBytes, &ente.ErrPublicCommentTooLong); err != nil {
		return "", err
	}
	if len(req.Nonce) == 0 {
		return "", ente.ErrBadRequest
	}
	actor, err := resolvePublicActor(ctx, c.UserAuthRepo, c.JwtSecret, req.AnonUserID, req.AnonToken, true)
	if err != nil {
		return "", err
	}
	if err := ensureAnonUserForCollection(ctx, c.AnonUsersRepo, collectionID, actor); err != nil {
		return "", err
	}
	createReq := socialcontroller.CreateCommentRequest{
		Actor:           actor,
		CollectionID:    collectionID,
		FileID:          req.FileID,
		ParentCommentID: req.ParentCommentID,
		Cipher:          req.Cipher,
		Nonce:           req.Nonce,
		ID:              req.ID,
		RequireAccess:   false,
	}
	return c.CommentCtrl.Create(ctx, createReq)
}

func (c *CommentsController) UpdateComment(ctx *gin.Context, collectionID int64, commentID string, req CommentUpdateRequest) error {
	if err := ensureCommentsFeatureEnabled(ctx); err != nil {
		return err
	}
	if len(req.Cipher) == 0 || len(req.Cipher) > maxCommentPayloadSize {
		return ente.ErrBadRequest
	}
	if err := validateEncryptedPayloadLength(req.Cipher, maxCommentBytes, &ente.ErrPublicCommentTooLong); err != nil {
		return err
	}
	if len(req.Nonce) == 0 {
		return ente.ErrBadRequest
	}
	actor, err := resolvePublicActor(ctx, c.UserAuthRepo, c.JwtSecret, req.AnonUserID, req.AnonToken, true)
	if err != nil {
		return err
	}
	if err := ensureAnonUserForCollection(ctx, c.AnonUsersRepo, collectionID, actor); err != nil {
		return err
	}
	updateReq := socialcontroller.UpdateCommentRequest{
		Actor:     actor,
		CommentID: commentID,
		Cipher:    req.Cipher,
		Nonce:     req.Nonce,
	}
	return c.CommentCtrl.UpdatePayload(ctx, updateReq)
}

func (c *CommentsController) DeleteComment(ctx *gin.Context, collectionID int64, commentID string, req CommentDeleteRequest) error {
	if err := ensureCommentsFeatureEnabled(ctx); err != nil {
		return err
	}
	if moderator, err := c.resolveModeratorActor(ctx); err != nil {
		return err
	} else if moderator != nil {
		return c.deleteCommentWithActor(ctx, commentID, *moderator, true)
	}
	actor, err := resolvePublicActor(ctx, c.UserAuthRepo, c.JwtSecret, req.AnonUserID, req.AnonToken, true)
	if err != nil {
		return err
	}
	if err := ensureAnonUserForCollection(ctx, c.AnonUsersRepo, collectionID, actor); err != nil {
		return err
	}
	return c.deleteCommentWithActor(ctx, commentID, actor, false)
}

func (c *CommentsController) ListComments(ctx *gin.Context, collectionID int64, since int64, limit int, fileID *int64) ([]socialentity.Comment, bool, error) {
	if err := ensureCommentsFeatureEnabled(ctx); err != nil {
		return nil, false, err
	}
	diffReq := socialcontroller.CommentDiffRequest{
		Actor:         socialcontroller.Actor{},
		CollectionID:  collectionID,
		Since:         since,
		Limit:         limit,
		FileID:        fileID,
		RequireAccess: false,
	}
	return c.CommentCtrl.Diff(ctx, diffReq)
}

func (c *CommentsController) Participants(ctx context.Context, collectionID int64) ([]participant, error) {
	ids := map[int64]struct{}{}
	commentIDs, err := c.CommentsRepo.GetActiveUserIDs(ctx, collectionID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	for _, id := range commentIDs {
		ids[id] = struct{}{}
	}
	reactionIDs, err := c.ReactionsRepo.GetActiveUserIDs(ctx, collectionID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	for _, id := range reactionIDs {
		ids[id] = struct{}{}
	}
	participants := make([]participant, 0, len(ids))
	for id := range ids {
		user, err := c.UserRepo.GetUserByIDInternal(id)
		if err != nil {
			continue
		}
		participants = append(participants, participant{
			UserID:      id,
			EmailMasked: emailUtil.GetMaskedEmailForPublic(user.Email),
		})
	}
	// Sort by userID for consistent ordering
	sort.Slice(participants, func(i, j int) bool {
		return participants[i].UserID < participants[j].UserID
	})
	return participants, nil
}

func (c *CommentsController) ListAnonProfiles(ctx *gin.Context, collectionID int64) ([]socialentity.AnonUser, error) {
	if err := ensureCommentsFeatureEnabled(ctx); err != nil {
		return nil, err
	}
	return c.AnonUsersRepo.ListByCollection(ctx, collectionID)
}

func ensureCommentsFeatureEnabled(ctx *gin.Context) error {
	if ctx == nil {
		return nil
	}
	if auth.MustGetPublicAccessContext(ctx).EnableComment {
		return nil
	}
	return &ente.ErrPublicCommentDisabled
}

func (c *CommentsController) resolveModeratorActor(ctx *gin.Context) (*socialcontroller.Actor, error) {
	if c.UserAuthRepo == nil {
		return nil, nil
	}
	token := auth.GetToken(ctx)
	if token == "" {
		return nil, nil
	}
	app := auth.GetApp(ctx)
	userID, expired, err := c.UserAuthRepo.GetUserIDWithToken(token, app)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ente.ErrAuthenticationRequired
		}
		return nil, stacktrace.Propagate(err, "")
	}
	if expired {
		return nil, ente.ErrAuthenticationRequired
	}
	return &socialcontroller.Actor{UserID: &userID}, nil
}

func (c *CommentsController) deleteCommentWithActor(ctx *gin.Context, commentID string, actor socialcontroller.Actor, requireAccess bool) error {
	deleteReq := socialcontroller.DeleteCommentRequest{
		Actor:         actor,
		CommentID:     commentID,
		RequireAccess: requireAccess,
	}
	return c.CommentCtrl.Delete(ctx, deleteReq)
}
