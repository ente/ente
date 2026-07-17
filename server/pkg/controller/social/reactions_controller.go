package social

import (
	"github.com/ente/museum/ente"
	socialentity "github.com/ente/museum/ente/social"
	"github.com/ente/museum/pkg/controller/access"
	"github.com/ente/museum/pkg/repo"
	socialrepo "github.com/ente/museum/pkg/repo/social"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
)

// ReactionsController orchestrates reactions operations.
type ReactionsController struct {
	Repo           *socialrepo.ReactionsRepository
	CommentsRepo   *socialrepo.CommentsRepository
	CollectionRepo *repo.CollectionRepository
	AccessCtrl     access.Controller
}

// UpsertReactionRequest holds the payload for creating or updating a reaction.
type UpsertReactionRequest struct {
	Actor         Actor
	ID            string
	CollectionID  int64
	FileID        *int64
	CommentID     *string
	Cipher        string
	Nonce         string
	RequireAccess bool
}

// ReactionDiffRequest describes paging for reactions.
type ReactionDiffRequest struct {
	Actor         Actor
	CollectionID  int64
	Since         int64
	Limit         int
	FileID        *int64
	CommentID     *string
	RequireAccess bool
}

// ReactionDeleteRequest contains parameters to remove a reaction.
type ReactionDeleteRequest struct {
	Actor         Actor
	ReactionID    string
	RequireAccess bool
}

// Upsert creates or updates a reaction entry.
func (c *ReactionsController) Upsert(ctx *gin.Context, req UpsertReactionRequest) (string, error) {
	var err error
	req.ID, err = NormalizeReactionID(req.ID)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	if len(req.Cipher) == 0 || len(req.Nonce) == 0 {
		return "", ente.ErrBadRequest
	}
	userID, hasUserID := req.Actor.UserIDValue()
	if req.RequireAccess && req.Actor.IsAnonymous() {
		return "", ente.ErrAuthenticationRequired
	}
	if req.Actor.IsAnonymous() {
		if err := req.Actor.ValidateAnon(); err != nil {
			return "", err
		}
	} else if !hasUserID || userID <= 0 {
		return "", ente.ErrAuthenticationRequired
	}
	if req.RequireAccess {
		if _, err := c.AccessCtrl.GetCollection(ctx, &access.GetCollectionParams{
			CollectionID: req.CollectionID,
			ActorUserID:  userID,
		}); err != nil {
			return "", stacktrace.Propagate(err, "")
		}
	}
	if req.FileID != nil {
		if err := validateFileInCollection(ctx, c.CollectionRepo, req.CollectionID, *req.FileID); err != nil {
			return "", err
		}
	}

	var targetComment *socialentity.Comment
	if req.CommentID != nil {
		targetComment, err = c.CommentsRepo.GetByID(ctx, *req.CommentID)
		if err != nil {
			return "", stacktrace.Propagate(err, "")
		}
		if targetComment.CollectionID != req.CollectionID {
			return "", stacktrace.Propagate(ente.ErrBadRequest, "reaction commentID belongs to a different collection")
		}
		if targetComment.IsDeleted {
			return "", stacktrace.Propagate(ente.ErrBadRequest, "cannot react to a deleted comment")
		}
		if err := validateCommentReactionContext(targetComment, req.FileID); err != nil {
			return "", err
		}
	}

	reaction := socialentity.Reaction{
		ID:           req.ID,
		CollectionID: req.CollectionID,
		FileID:       req.FileID,
		CommentID:    req.CommentID,
		Cipher:       req.Cipher,
		Nonce:        req.Nonce,
	}
	if req.Actor.IsAnonymous() {
		reaction.UserID = -1
		reaction.AnonUserID = req.Actor.AnonUserID
	} else {
		reaction.UserID = userID
	}
	if targetComment != nil {
		// file_id must remain nil for reactions that target comments, we only use the request
		// file_id to validate that the caller has consistent context.
		reaction.FileID = nil
	}
	id, err := c.Repo.Upsert(ctx, reaction)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	return id, nil
}

// Diff returns reaction windows for the provided scope.
func (c *ReactionsController) Diff(ctx *gin.Context, req ReactionDiffRequest) ([]socialentity.Reaction, bool, error) {
	userID, hasUserID := req.Actor.UserIDValue()
	if req.RequireAccess {
		if !hasUserID || userID <= 0 {
			return nil, false, ente.ErrAuthenticationRequired
		}
		if _, err := c.AccessCtrl.GetCollection(ctx, &access.GetCollectionParams{
			CollectionID: req.CollectionID,
			ActorUserID:  userID,
		}); err != nil {
			return nil, false, stacktrace.Propagate(err, "")
		}
	}
	return c.Repo.GetDiff(ctx, req.CollectionID, req.Since, req.Limit, req.FileID, req.CommentID)
}

// Delete removes a reaction if the actor owns it.
func (c *ReactionsController) Delete(ctx *gin.Context, req ReactionDeleteRequest) error {
	userID, hasUserID := req.Actor.UserIDValue()
	reaction, err := c.Repo.GetByID(ctx, req.ReactionID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if req.Actor.IsAnonymous() {
		if err := req.Actor.ValidateAnon(); err != nil {
			return err
		}
		if reaction.AnonUserID == nil || req.Actor.AnonUserID == nil || *reaction.AnonUserID != *req.Actor.AnonUserID {
			return stacktrace.Propagate(ente.ErrPermissionDenied, "")
		}
	} else if !hasUserID || reaction.UserID != userID {
		return stacktrace.Propagate(ente.ErrPermissionDenied, "")
	}
	if req.RequireAccess {
		if !hasUserID || userID <= 0 {
			return ente.ErrAuthenticationRequired
		}
		if _, err := c.AccessCtrl.GetCollection(ctx, &access.GetCollectionParams{
			CollectionID: reaction.CollectionID,
			ActorUserID:  userID,
		}); err != nil {
			return stacktrace.Propagate(err, "")
		}
	}
	repoUserID := int64(-1)
	if hasUserID {
		repoUserID = userID
	}
	return c.Repo.SoftDeleteByID(ctx, req.ReactionID, repoUserID, req.Actor.AnonUserID)
}

func validateCommentReactionContext(comment *socialentity.Comment, requestedFileID *int64) error {
	if comment == nil {
		return nil
	}
	if comment.FileID != nil {
		switch {
		case requestedFileID == nil:
			return stacktrace.Propagate(ente.ErrBadRequest, "fileID is required when reacting to a file-scoped comment")
		case *requestedFileID != *comment.FileID:
			return stacktrace.Propagate(ente.ErrBadRequest, "fileID must match the target comment's fileID")
		}
		return nil
	}
	if requestedFileID != nil {
		return stacktrace.Propagate(ente.ErrBadRequest, "fileID must be omitted when reacting to a collection-level comment")
	}
	return nil
}
