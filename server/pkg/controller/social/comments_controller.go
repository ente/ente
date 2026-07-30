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

// CommentsController wires comment-specific business logic.
type CommentsController struct {
	Repo           *socialrepo.CommentsRepository
	CollectionRepo *repo.CollectionRepository
	AccessCtrl     access.Controller
}

// CreateCommentRequest encapsulates parameters for adding a comment.
type CreateCommentRequest struct {
	Actor           Actor
	CollectionID    int64
	FileID          *int64
	ParentCommentID *string
	Cipher          string
	Nonce           string
	ID              string
	RequireAccess   bool
}

// CommentDiffRequest describes the paging request for a collection's comments.
type CommentDiffRequest struct {
	Actor         Actor
	CollectionID  int64
	Since         int64
	Limit         int
	FileID        *int64
	RequireAccess bool
}

// UpdateCommentRequest holds the information needed to edit a comment.
type UpdateCommentRequest struct {
	Actor         Actor
	CommentID     string
	Cipher        string
	Nonce         string
	RequireAccess bool
}

// DeleteCommentRequest defines the delete operation parameters.
type DeleteCommentRequest struct {
	Actor         Actor
	CommentID     string
	RequireAccess bool
}

// Create inserts a new comment; returns the supplied ID on success.
func (c *CommentsController) Create(ctx *gin.Context, req CreateCommentRequest) (string, error) {
	var err error
	req.ID, err = NormalizeCommentID(req.ID)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	if len(req.Cipher) == 0 || len(req.Nonce) == 0 {
		return "", ente.ErrBadRequest
	}
	userID, hasUserID := req.Actor.UserIDValue()
	if req.Actor.IsAnonymous() {
		if err := req.Actor.ValidateAnon(); err != nil {
			return "", err
		}
	} else if !hasUserID || userID <= 0 {
		return "", ente.ErrAuthenticationRequired
	}
	if req.RequireAccess && req.Actor.IsAnonymous() {
		return "", ente.ErrPermissionDenied
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

	var parentComment *socialentity.Comment
	if req.ParentCommentID != nil {
		parentComment, err = c.Repo.GetByID(ctx, *req.ParentCommentID)
		if err != nil {
			return "", stacktrace.Propagate(err, "")
		}
		if parentComment.CollectionID != req.CollectionID {
			return "", stacktrace.Propagate(ente.ErrBadRequest, "parent comment belongs to a different collection")
		}
		if parentComment.IsDeleted {
			return "", stacktrace.Propagate(ente.ErrBadRequest, "cannot reply to a deleted comment")
		}
	}
	if err := validateReplyFileContext(parentComment, req.FileID); err != nil {
		return "", err
	}

	comment := socialentity.Comment{
		ID:              req.ID,
		CollectionID:    req.CollectionID,
		FileID:          req.FileID,
		ParentCommentID: req.ParentCommentID,
		UserID:          -1,
		AnonUserID:      req.Actor.AnonUserID,
		Cipher:          req.Cipher,
		Nonce:           req.Nonce,
	}
	if hasUserID {
		comment.UserID = userID
	}
	if len(req.Cipher) > 0 {
		comment.Cipher = req.Cipher
	}
	if len(req.Nonce) > 0 {
		comment.Nonce = req.Nonce
	}
	if err := c.Repo.Insert(ctx, comment); err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	return comment.ID, nil
}

// Diff returns a window of comments for the requested collection.
func (c *CommentsController) Diff(ctx *gin.Context, req CommentDiffRequest) ([]socialentity.Comment, bool, error) {
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
	return c.Repo.GetDiff(ctx, req.CollectionID, req.Since, req.Limit, req.FileID)
}

// UpdatePayload edits the encrypted payload of a comment.
func (c *CommentsController) UpdatePayload(ctx *gin.Context, req UpdateCommentRequest) error {
	if len(req.Cipher) == 0 || len(req.Nonce) == 0 {
		return ente.ErrBadRequest
	}
	userID, hasUserID := req.Actor.UserIDValue()
	comment, err := c.Repo.GetByID(ctx, req.CommentID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if req.Actor.IsAnonymous() {
		if err := req.Actor.ValidateAnon(); err != nil {
			return err
		}
		if comment.AnonUserID == nil || req.Actor.AnonUserID == nil || *comment.AnonUserID != *req.Actor.AnonUserID {
			return stacktrace.Propagate(ente.ErrPermissionDenied, "")
		}
	} else if !hasUserID || comment.UserID != userID {
		return stacktrace.Propagate(ente.ErrPermissionDenied, "")
	}
	return c.Repo.UpdateCipher(ctx, req.CommentID, req.Cipher, req.Nonce)
}

// Delete removes a comment if the actor is allowed to do so.
func (c *CommentsController) Delete(ctx *gin.Context, req DeleteCommentRequest) error {
	userID, hasUserID := req.Actor.UserIDValue()
	comment, err := c.Repo.GetByID(ctx, req.CommentID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	switch {
	case req.Actor.IsAnonymous():
		if err := req.Actor.ValidateAnon(); err != nil {
			return err
		}
		if comment.AnonUserID == nil || req.Actor.AnonUserID == nil || *comment.AnonUserID != *req.Actor.AnonUserID {
			return stacktrace.Propagate(ente.ErrPermissionDenied, "")
		}
	default:
		if !hasUserID {
			return stacktrace.Propagate(ente.ErrPermissionDenied, "")
		}
		if comment.UserID != userID {
			requiresAdminRole := req.RequireAccess || comment.AnonUserID != nil
			if !requiresAdminRole {
				return stacktrace.Propagate(ente.ErrPermissionDenied, "")
			}
			resp, err := c.AccessCtrl.GetCollection(ctx, &access.GetCollectionParams{
				CollectionID: comment.CollectionID,
				ActorUserID:  userID,
			})
			if err != nil {
				return stacktrace.Propagate(err, "")
			}
			if resp.Role == nil {
				return stacktrace.Propagate(ente.ErrPermissionDenied, "")
			}
			minRole := ente.ADMIN
			if !resp.Role.Satisfies(&minRole) {
				return stacktrace.Propagate(ente.ErrPermissionDenied, "")
			}
		}
	}
	return c.Repo.SoftDelete(ctx, req.CommentID)
}

func validateReplyFileContext(parent *socialentity.Comment, requestedFileID *int64) error {
	if parent == nil {
		return nil
	}
	if parent.FileID != nil {
		switch {
		case requestedFileID == nil:
			return stacktrace.Propagate(ente.ErrBadRequest, "fileID is required when replying to a file-scoped comment")
		case *requestedFileID != *parent.FileID:
			return stacktrace.Propagate(ente.ErrBadRequest, "fileID must match the parent comment's fileID")
		}
		return nil
	}
	if requestedFileID != nil {
		return stacktrace.Propagate(ente.ErrBadRequest, "fileID must be omitted when replying to a collection-level comment")
	}
	return nil
}
