package controller

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"errors"
	"net/http"
	"strings"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/space/models"
	"github.com/ente/museum/space/repo"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
)

const (
	SpaceLinkAuthHeader   = "X-Ente-Space-Link-Auth"
	spaceLinkAuthKeyBytes = 32
	spaceLinkKDFSaltBytes = 16
	spaceLinkKDFMemLimit  = 67_108_864
	spaceLinkKDFOpsLimit  = 2
	spaceLinkPostLimit    = 60
)

type LinksController struct {
	LinksRepo   *repo.LinksRepository
	SpacesRepo  *repo.SpacesRepository
	FriendsRepo *repo.FriendsRepository
	Posts       *PostsController
	Assets      *AssetsController
}

func spaceLinkStatus(link *repo.SpaceLinkRecord) *models.SpaceLinkStatusResponse {
	return &models.SpaceLinkStatusResponse{
		LinkID:             link.LinkID,
		SpaceID:            link.SpaceID,
		SpaceSlug:          link.SpaceSlug,
		Active:             link.Active,
		KDFSalt:            encodeSpaceField(link.KDFSalt),
		KDFMemLimit:        link.KDFMemLimit,
		KDFOpsLimit:        link.KDFOpsLimit,
		KeyVersion:         link.KeyVersion,
		EncryptedAccessKey: encodeSpaceField(link.EncryptedAccessKey),
		CreatedAt:          formatMicros(link.CreatedAt),
		UpdatedAt:          formatMicros(link.UpdatedAt),
	}
}

func (c *LinksController) Get(ctx context.Context, space *repo.SpaceRecord) (*models.SpaceLinkStatusResponse, error) {
	link, err := c.LinksRepo.GetActive(ctx, space.SpaceID)
	if err != nil {
		if errors.Is(stacktrace.RootCause(err), sql.ErrNoRows) {
			return &models.SpaceLinkStatusResponse{
				SpaceID:   space.SpaceID,
				SpaceSlug: space.SpaceSlug,
				Active:    false,
			}, nil
		}
		return nil, err
	}
	return spaceLinkStatus(link), nil
}

func decodeSpaceLinkWriteRequest(req models.SpaceLinkWriteRequest) (authKey, kdfSalt, encryptedSpaceKey, encryptedAccessKey []byte, err error) {
	authKey, err = decodeEncodedSpaceField("authKey", req.AuthKey, maxSpaceEncryptedKeyEncodedBytes, maxSpaceEncryptedKeyDecodedBytes)
	if err != nil {
		return
	}
	if len(authKey) != spaceLinkAuthKeyBytes {
		err = ente.NewBadRequestWithMessage("authKey must be 32 bytes")
		return
	}
	kdfSalt, err = decodeEncodedSpaceField("kdfSalt", req.KDFSalt, maxSpaceLinkKDFSaltEncodedBytes, maxSpaceLinkKDFSaltDecodedBytes)
	if err != nil {
		return
	}
	if len(kdfSalt) != spaceLinkKDFSaltBytes {
		err = ente.NewBadRequestWithMessage("kdfSalt must be 16 bytes")
		return
	}
	if req.KDFMemLimit != spaceLinkKDFMemLimit || req.KDFOpsLimit != spaceLinkKDFOpsLimit {
		err = ente.NewBadRequestWithMessage("unsupported space link KDF parameters")
		return
	}
	encryptedSpaceKey, err = decodeEncodedSpaceField("encryptedSpaceKey", req.EncryptedSpaceKey, maxSpaceEncryptedKeyEncodedBytes, maxSpaceEncryptedKeyDecodedBytes)
	if err != nil {
		return
	}
	encryptedAccessKey, err = decodeEncodedSpaceField("encryptedAccessKey", req.EncryptedAccessKey, maxSpaceEncryptedKeyEncodedBytes, maxSpaceEncryptedKeyDecodedBytes)
	return
}

func (c *LinksController) Create(ctx context.Context, space *repo.SpaceRecord, req models.SpaceLinkWriteRequest) (*models.SpaceLinkStatusResponse, error) {
	authKey, kdfSalt, encryptedSpaceKey, encryptedAccessKey, err := decodeSpaceLinkWriteRequest(req)
	if err != nil {
		return nil, err
	}
	if req.KeyVersion != space.CurrentVersion {
		return nil, ente.NewBadRequestWithMessage("keyVersion does not match current space version")
	}
	sum := sha256.Sum256(authKey)
	link, err := c.LinksRepo.Create(
		ctx,
		space.SpaceID,
		sum[:],
		kdfSalt,
		req.KDFMemLimit,
		req.KDFOpsLimit,
		req.KeyVersion,
		encryptedSpaceKey,
		encryptedAccessKey,
	)
	if err != nil {
		if errors.Is(stacktrace.RootCause(err), sql.ErrNoRows) {
			return nil, ente.NewBadRequestWithMessage("keyVersion does not match current space version")
		}
		if errors.Is(err, repo.ErrSpaceLinkSecretReused) {
			return nil, ente.NewBadRequestWithMessage("space link secret has already been used")
		}
		return nil, err
	}
	return spaceLinkStatus(link), nil
}

func (c *LinksController) Rotate(ctx context.Context, space *repo.SpaceRecord, req models.SpaceLinkWriteRequest) (*models.SpaceLinkStatusResponse, error) {
	authKey, kdfSalt, encryptedSpaceKey, encryptedAccessKey, err := decodeSpaceLinkWriteRequest(req)
	if err != nil {
		return nil, err
	}
	if req.KeyVersion != space.CurrentVersion {
		return nil, ente.NewBadRequestWithMessage("keyVersion does not match current space version")
	}
	sum := sha256.Sum256(authKey)
	link, err := c.LinksRepo.Rotate(
		ctx,
		space.SpaceID,
		sum[:],
		kdfSalt,
		req.KDFMemLimit,
		req.KDFOpsLimit,
		req.KeyVersion,
		encryptedSpaceKey,
		encryptedAccessKey,
	)
	if err != nil {
		if errors.Is(stacktrace.RootCause(err), sql.ErrNoRows) {
			return nil, ente.NewBadRequestWithMessage("keyVersion does not match current space version")
		}
		if errors.Is(err, repo.ErrSpaceLinkSecretReused) {
			return nil, ente.NewBadRequestWithMessage("space link secret has already been used")
		}
		if errors.Is(err, repo.ErrSpaceLinkRotationLimitReached) {
			return nil, &ente.ApiError{
				Code:           ente.ErrorCode("SPACE_LINK_ROTATION_LIMIT_REACHED"),
				Message:        "space link can only be rotated five times per day",
				HttpStatusCode: http.StatusTooManyRequests,
			}
		}
		return nil, err
	}
	return spaceLinkStatus(link), nil
}

func (c *LinksController) Bootstrap(ctx context.Context, slug string) (*models.SpaceLinkBootstrapResponse, error) {
	link, err := c.LinksRepo.GetActiveBootstrap(ctx, strings.TrimSpace(slug))
	if err != nil {
		if errors.Is(stacktrace.RootCause(err), sql.ErrNoRows) {
			return nil, ente.ErrNotFound
		}
		return nil, err
	}
	return &models.SpaceLinkBootstrapResponse{
		KDFSalt:     encodeSpaceField(link.KDFSalt),
		KDFMemLimit: link.KDFMemLimit,
		KDFOpsLimit: link.KDFOpsLimit,
	}, nil
}

func (c *LinksController) authorize(ctx *gin.Context, slug string) (*repo.SpaceLinkRecord, *repo.SpaceRecord, error) {
	encodedAuth := strings.TrimSpace(ctx.GetHeader(SpaceLinkAuthHeader))
	authKey, err := decodeOptionalEncodedSpaceField("space link auth", encodedAuth, maxSpaceEncryptedKeyEncodedBytes, maxSpaceEncryptedKeyDecodedBytes)
	if err != nil || len(authKey) != spaceLinkAuthKeyBytes {
		return nil, nil, ente.ErrNotFound
	}
	sum := sha256.Sum256(authKey)
	link, space, err := c.LinksRepo.GetActiveSpaceBySlugAndAuthHash(ctx, strings.TrimSpace(slug), sum[:])
	if err != nil {
		if errors.Is(stacktrace.RootCause(err), sql.ErrNoRows) {
			return nil, nil, ente.ErrNotFound
		}
		return nil, nil, err
	}
	return link, space, nil
}

func (c *LinksController) Profile(ctx *gin.Context, slug string) (*models.SpaceLinkProfileResponse, error) {
	link, space, err := c.authorize(ctx, slug)
	if err != nil {
		return nil, err
	}
	friends, err := c.FriendsRepo.CountFriendsForSpace(ctx, space.SpaceID)
	if err != nil {
		return nil, err
	}
	posts, err := c.Posts.PostsRepo.CountPosts(ctx, space.SpaceID)
	if err != nil {
		return nil, err
	}
	return &models.SpaceLinkProfileResponse{
		EncryptedSpaceKey: encodeSpaceField(link.EncryptedSpaceKey),
		KeyVersion:        link.KeyVersion,
		Posts:             posts,
		Profile: models.SpaceProfileResponse{
			SpaceID:          space.SpaceID,
			SpaceSlug:        space.SpaceSlug,
			Version:          space.CurrentVersion,
			EncryptedProfile: encodeSpaceField(space.EncryptedProfile),
			UpdatedAt:        formatMicros(space.UpdatedAt),
			Avatar:           toAvatarResponse(space),
			Cover:            toCoverResponse(space),
			Friends:          friends,
		},
	}, nil
}

func (c *LinksController) RecentPosts(ctx *gin.Context, slug string) (*models.PostPage, error) {
	_, space, err := c.authorize(ctx, slug)
	if err != nil {
		return nil, err
	}
	posts, _, err := c.Posts.PostsRepo.ListPostsBySpace(ctx, space.SpaceID, "", "", spaceLinkPostLimit)
	if err != nil {
		return nil, err
	}
	items, err := c.Posts.postResponses(ctx, posts, true)
	if err != nil {
		return nil, err
	}
	return &models.PostPage{Items: items}, nil
}

func (c *LinksController) Versions(ctx *gin.Context, slug string) ([]models.SpaceKeyVersionResponse, error) {
	_, space, err := c.authorize(ctx, slug)
	if err != nil {
		return nil, err
	}
	versions, err := c.SpacesRepo.ListVersions(ctx, space.SpaceID)
	if err != nil {
		return nil, err
	}
	resp := make([]models.SpaceKeyVersionResponse, 0, len(versions))
	for _, version := range versions {
		item := models.SpaceKeyVersionResponse{
			Version:   version.Version,
			CreatedAt: formatMicros(version.CreatedAt),
		}
		if len(version.WrappedPrevKey) > 0 {
			item.WrappedPrevKey = encodeSpaceField(version.WrappedPrevKey)
		}
		resp = append(resp, item)
	}
	return resp, nil
}

func (c *LinksController) AssetRedirect(ctx *gin.Context, slug string, req models.AssetRedirectRequest) (*models.AssetDownloadResponse, error) {
	_, space, err := c.authorize(ctx, slug)
	if err != nil {
		return nil, err
	}
	req.SpaceID = space.SpaceID
	return c.Assets.redirectForSpace(ctx, space, req)
}
