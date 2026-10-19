package controller

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/space/models"
	"github.com/ente/museum/space/repo"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
)

const spacePostLimitWarningThreshold = 200

type SpaceAbuseNotifier interface {
	NotifyPotentialAbuse(message string)
}

type PostsController struct {
	PostsRepo        *repo.PostsRepository
	SpacesRepo       *repo.SpacesRepository
	AssetsRepo       *repo.AssetsRepository
	ActivityNotifier SpaceActivityNotifier
	AbuseNotifier    SpaceAbuseNotifier
	auth             authDeps
}

func (c *PostsController) Create(ctx context.Context, space *repo.SpaceRecord, req models.CreatePostRequest) (*models.CreatePostResponse, error) {
	if strings.TrimSpace(req.EncryptedPostKey) == "" || len(req.Objects) == 0 {
		return nil, ente.NewBadRequestWithMessage("encryptedPostKey and objects are required")
	}
	if len(req.Objects) > maxSpacePostObjects {
		return nil, ente.NewBadRequestWithMessage("too many post objects")
	}
	if req.KeyVersion <= 0 {
		return nil, ente.NewBadRequestWithMessage("keyVersion is required")
	}
	encryptedPostKey, err := decodeEncodedSpaceField("encryptedPostKey", req.EncryptedPostKey, maxSpaceEncryptedKeyEncodedBytes, maxSpaceEncryptedKeyDecodedBytes)
	if err != nil {
		return nil, err
	}
	captionCipher, err := decodeOptionalEncodedSpacePointerField("captionCipher", req.CaptionCipher, maxSpaceCaptionCipherEncodedBytes, maxSpaceCaptionCipherDecodedBytes)
	if err != nil {
		return nil, err
	}
	if len(req.ClientRequestID) > 64 {
		return nil, ente.NewBadRequestWithMessage("invalid client request id")
	}
	if req.ClientRequestID != "" {
		postID, err := c.PostsRepo.PostIDForRequest(ctx, space.SpaceID, req.ClientRequestID)
		if err == nil {
			return &models.CreatePostResponse{PostID: postID}, nil
		}
		if !errors.Is(err, sql.ErrNoRows) {
			return nil, err
		}
	}
	assets := make([]repo.SpacePostAssetRecord, 0, len(req.Objects)*2)
	positions := make(map[int]bool)
	keys := make(map[string]bool)
	for _, object := range req.Objects {
		if object.Position < 0 || object.Position >= maxSpacePostObjects || positions[object.Position] {
			return nil, ente.NewBadRequestWithMessage("invalid object position")
		}
		positions[object.Position] = true
		parts := []models.PostObjectPayload{object}
		if object.Video != nil {
			if object.Video.Video != nil {
				return nil, ente.NewBadRequestWithMessage("invalid nested video")
			}
			parts = append(parts, *object.Video)
		}
		for index, part := range parts {
			if strings.TrimSpace(part.ObjectKey) == "" || keys[part.ObjectKey] {
				return nil, ente.NewBadRequestWithMessage("a unique objectKey is required for each asset")
			}
			keys[part.ObjectKey] = true
			if err := validateSpaceTextFieldBytes("objectKey", part.ObjectKey, maxSpaceObjectKeyBytes); err != nil {
				return nil, err
			}
			metadataCipher, err := decodeEncodedSpaceField("metadataCipher", part.MetadataCipher, maxSpaceAssetMetadataEncodedBytes, maxSpaceAssetMetadataDecodedBytes)
			if err != nil {
				return nil, err
			}
			staged, err := verifyStagedUpload(ctx, c.AssetsRepo, part.ObjectKey, repo.TempObjectPurposePost, &space.SpaceID)
			if err != nil {
				if req.ClientRequestID != "" {
					postID, lookupErr := c.PostsRepo.PostIDForRequest(ctx, space.SpaceID, req.ClientRequestID)
					if lookupErr == nil {
						return &models.CreatePostResponse{PostID: postID}, nil
					}
					if !errors.Is(lookupErr, sql.ErrNoRows) {
						return nil, lookupErr
					}
				}
				return nil, err
			}
			role := "preview"
			if index == 1 {
				role = "video"
			}
			assets = append(assets, repo.SpacePostAssetRecord{
				ObjectKey:      staged.ObjectKey,
				BucketID:       staged.BucketID,
				Size:           sql.NullInt64{Int64: staged.ExpectedSize, Valid: staged.ExpectedSize > 0},
				Position:       object.Position,
				MetadataCipher: metadataCipher,
				Role:           role,
			})
		}
	}
	postID, postCount, err := c.PostsRepo.CreatePost(ctx, space.SpaceID, encryptedPostKey, captionCipher, req.KeyVersion, assets, req.ClientRequestID)
	if err != nil {
		if errors.Is(stacktrace.RootCause(err), sql.ErrNoRows) {
			return nil, ente.NewBadRequestWithMessage("keyVersion does not match current space version")
		}
		if errors.Is(stacktrace.RootCause(err), repo.ErrSpacePostLimitReached) {
			return nil, ente.NewConflictError("space post limit reached")
		}
		return nil, err
	}
	if postCount == spacePostLimitWarningThreshold && c.AbuseNotifier != nil {
		go c.AbuseNotifier.NotifyPotentialAbuse(fmt.Sprintf(
			"Space %s owned by user %d has reached %d of %d posts",
			space.SpaceID, space.OwnerID, postCount, repo.MaxPostsPerSpace,
		))
	}
	if postCount > 0 {
		c.notifyFriendsOfNewPost(spaceActivityActor(space), postID)
	}
	return &models.CreatePostResponse{PostID: postID}, nil
}

func (c *PostsController) notifyFriendsOfNewPost(actor SpaceActivityActor, postID int64) {
	go c.ActivityNotifier.OnSpacePostCreated(actor, postID)
}

func (c *PostsController) postResponses(ctx context.Context, posts []repo.SpacePostRecord, includeAuthor bool) ([]models.PostResponse, error) {
	postIDs := make([]int64, 0, len(posts))
	for _, post := range posts {
		postIDs = append(postIDs, post.PostID)
	}
	assetsByPost, err := c.PostsRepo.ListAssetsByPostIDs(ctx, postIDs)
	if err != nil {
		return nil, err
	}
	resp := make([]models.PostResponse, 0, len(posts))
	for _, post := range posts {
		resp = append(resp, *toPostResponse(&post, assetsByPost[post.PostID], includeAuthor))
	}
	return resp, nil
}

func (c *PostsController) postResponse(ctx context.Context, post *repo.SpacePostRecord, includeAuthor bool) (*models.PostResponse, error) {
	assetsByPost, err := c.PostsRepo.ListAssetsByPostIDs(ctx, []int64{post.PostID})
	if err != nil {
		return nil, err
	}
	return toPostResponse(post, assetsByPost[post.PostID], includeAuthor), nil
}

func (c *PostsController) List(ctx *gin.Context, req models.ListPostsRequest) (*models.PostPage, error) {
	viewer, err := c.auth.resolveViewer(ctx, req.ViewerSpaceID)
	if err != nil {
		return nil, err
	}
	space, err := c.SpacesRepo.GetSpaceByID(ctx, strings.TrimSpace(req.SpaceID))
	if err != nil {
		return nil, err
	}
	if err := c.auth.canViewSpace(ctx, viewer, space); err != nil {
		return nil, err
	}
	viewerSpaceID := ""
	if viewer != nil {
		viewerSpaceID = viewer.SpaceID
	}
	posts, nextCursor, err := c.PostsRepo.ListPostsBySpace(ctx, space.SpaceID, viewerSpaceID, req.Cursor, req.Limit)
	if err != nil {
		return nil, err
	}
	resp, err := c.postResponses(ctx, posts, true)
	if err != nil {
		return nil, err
	}
	return &models.PostPage{
		Items:      resp,
		NextCursor: nextCursor,
	}, nil
}

func (c *PostsController) ListFeed(ctx context.Context, viewerSpace *repo.SpaceRecord, req models.ListFeedRequest) (*models.PostPage, error) {
	posts, nextCursor, err := c.PostsRepo.ListFeed(ctx, viewerSpace.SpaceID, req.Cursor, req.Limit)
	if err != nil {
		return nil, err
	}
	items, err := c.postResponses(ctx, posts, true)
	if err != nil {
		return nil, err
	}
	return &models.PostPage{
		Items:      items,
		NextCursor: nextCursor,
	}, nil
}

func (c *PostsController) Get(ctx *gin.Context, postID int64, req models.GetPostRequest) (*models.PostResponse, error) {
	viewer, err := c.auth.resolveViewer(ctx, req.ViewerSpaceID)
	if err != nil {
		return nil, err
	}
	viewerSpaceID := ""
	if viewer != nil {
		viewerSpaceID = viewer.SpaceID
	}
	post, err := c.PostsRepo.GetPost(ctx, postID, viewerSpaceID)
	if err != nil {
		return nil, err
	}
	if strings.TrimSpace(req.SpaceID) != "" && post.SpaceID != strings.TrimSpace(req.SpaceID) {
		return nil, ente.ErrNotFound
	}
	space, err := c.SpacesRepo.GetSpaceByID(ctx, post.SpaceID)
	if err != nil {
		return nil, err
	}
	if err := c.auth.canViewSpace(ctx, viewer, space); err != nil {
		return nil, err
	}
	return c.postResponse(ctx, post, true)
}

func (c *PostsController) UpdateCaption(ctx context.Context, viewerSpace *repo.SpaceRecord, postID int64, req models.UpdatePostCaptionRequest) (*models.PostResponse, error) {
	captionCipher, err := decodeOptionalEncodedSpacePointerField("captionCipher", req.CaptionCipher, maxSpaceCaptionCipherEncodedBytes, maxSpaceCaptionCipherDecodedBytes)
	if err != nil {
		return nil, err
	}
	if err := c.PostsRepo.UpdateCaption(ctx, postID, viewerSpace.SpaceID, captionCipher); err != nil {
		return nil, err
	}
	post, err := c.PostsRepo.GetPost(ctx, postID, viewerSpace.SpaceID)
	if err != nil {
		return nil, err
	}
	return c.postResponse(ctx, post, true)
}

func (c *PostsController) SetLike(ctx context.Context, actorSpace *repo.SpaceRecord, postID int64, like bool) (*models.LikePostResponse, error) {
	post, err := c.PostsRepo.GetPost(ctx, postID, actorSpace.SpaceID)
	if err != nil {
		return nil, err
	}
	space, err := c.SpacesRepo.GetSpaceByID(ctx, post.SpaceID)
	if err != nil {
		return nil, err
	}
	if space.OwnerID == actorSpace.OwnerID {
		return nil, ente.NewBadRequestWithMessage("cannot like your own post")
	}
	if err := c.auth.canViewSpace(ctx, &viewerAuth{UserID: actorSpace.OwnerID, SpaceID: actorSpace.SpaceID}, space); err != nil {
		return nil, err
	}
	created, err := c.PostsRepo.SetLikeWithCreated(ctx, postID, actorSpace.SpaceID, like)
	if err != nil {
		return nil, err
	}
	if like && created {
		go c.ActivityNotifier.OnSpacePostLiked(spaceActivityActor(actorSpace), post.OwnerID)
	}
	return &models.LikePostResponse{Liked: like}, nil
}

func (c *PostsController) Delete(ctx context.Context, space *repo.SpaceRecord, postID int64) error {
	return c.PostsRepo.DeletePost(ctx, postID, space.SpaceID)
}
