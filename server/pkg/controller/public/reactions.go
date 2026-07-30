package public

import (
	"github.com/ente/museum/ente"
	socialentity "github.com/ente/museum/ente/social"
	socialcontroller "github.com/ente/museum/pkg/controller/social"
	"github.com/ente/museum/pkg/repo"
	socialrepo "github.com/ente/museum/pkg/repo/social"
	"github.com/gin-gonic/gin"
)

const reactionCipherLength = 156

// ReactionsController exposes reactions for public collections.
type ReactionsController struct {
	ReactionCtrl  *socialcontroller.ReactionsController
	ReactionsRepo *socialrepo.ReactionsRepository
	AnonUsersRepo *socialrepo.AnonUsersRepository
	UserAuthRepo  *repo.UserAuthRepository
	JwtSecret     []byte
}

type ReactionRequest struct {
	ID         string  `json:"id"`
	FileID     *int64  `json:"fileID"`
	CommentID  *string `json:"commentID"`
	Cipher     string  `json:"cipher" binding:"required"`
	Nonce      string  `json:"nonce" binding:"required"`
	AnonUserID *string `json:"anonUserID"`
	AnonToken  string  `json:"anonToken"`
}

type ReactionDeleteRequest struct {
	AnonUserID *string `json:"anonUserID"`
	AnonToken  string  `json:"anonToken"`
}

func (c *ReactionsController) UpsertReaction(ctx *gin.Context, collectionID int64, req ReactionRequest) (string, error) {
	if err := ensureCommentsFeatureEnabled(ctx); err != nil {
		return "", err
	}
	if len(req.Cipher) != reactionCipherLength || len(req.Nonce) == 0 {
		return "", ente.ErrBadRequest
	}
	actor, err := resolvePublicActor(ctx, c.UserAuthRepo, c.JwtSecret, req.AnonUserID, req.AnonToken, true)
	if err != nil {
		return "", err
	}
	if err := ensureAnonUserForCollection(ctx, c.AnonUsersRepo, collectionID, actor); err != nil {
		return "", err
	}
	upsertReq := socialcontroller.UpsertReactionRequest{
		Actor:         actor,
		ID:            req.ID,
		CollectionID:  collectionID,
		FileID:        req.FileID,
		CommentID:     req.CommentID,
		Cipher:        req.Cipher,
		Nonce:         req.Nonce,
		RequireAccess: false,
	}
	return c.ReactionCtrl.Upsert(ctx, upsertReq)
}

func (c *ReactionsController) DeleteReaction(ctx *gin.Context, collectionID int64, reactionID string, req ReactionDeleteRequest) error {
	if err := ensureCommentsFeatureEnabled(ctx); err != nil {
		return err
	}
	actor, err := resolvePublicActor(ctx, c.UserAuthRepo, c.JwtSecret, req.AnonUserID, req.AnonToken, true)
	if err != nil {
		return err
	}
	if err := ensureAnonUserForCollection(ctx, c.AnonUsersRepo, collectionID, actor); err != nil {
		return err
	}
	deleteReq := socialcontroller.ReactionDeleteRequest{
		Actor:         actor,
		ReactionID:    reactionID,
		RequireAccess: false,
	}
	return c.ReactionCtrl.Delete(ctx, deleteReq)
}

func (c *ReactionsController) ListReactions(ctx *gin.Context, collectionID int64, since int64, limit int, fileID *int64, commentID *string) ([]socialentity.Reaction, bool, error) {
	if err := ensureCommentsFeatureEnabled(ctx); err != nil {
		return nil, false, err
	}
	diffReq := socialcontroller.ReactionDiffRequest{
		Actor:         socialcontroller.Actor{},
		CollectionID:  collectionID,
		Since:         since,
		Limit:         limit,
		FileID:        fileID,
		CommentID:     commentID,
		RequireAccess: false,
	}
	return c.ReactionCtrl.Diff(ctx, diffReq)
}
