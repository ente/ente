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
	"github.com/gin-gonic/gin"
)

type SpacesController struct {
	SpacesRepo *repo.SpacesRepository
	AssetsRepo *repo.AssetsRepository
	auth       authDeps
}

func (c *SpacesController) List(ctx *gin.Context) ([]models.SpaceKeyResponse, error) {
	userID, err := c.auth.requireUser(ctx)
	if err != nil {
		return nil, err
	}
	spaces, err := c.SpacesRepo.ListSpacesByOwner(ctx, userID)
	if err != nil {
		return nil, err
	}
	resp := make([]models.SpaceKeyResponse, 0, len(spaces))
	for _, space := range spaces {
		resp = append(resp, *toSpaceKeyResponse(&space))
	}
	return resp, nil
}

func (c *SpacesController) Create(ctx *gin.Context, req models.CreateSpaceRequest) (*models.SpaceKeyResponse, error) {
	userID, err := c.auth.requireUser(ctx)
	if err != nil {
		return nil, err
	}
	normalizedSlug, err := validateSpaceSlug(req.SpaceSlug)
	if err != nil {
		return nil, err
	}
	if strings.TrimSpace(req.RootWrappedSpaceKey) == "" || strings.TrimSpace(req.PublicKey) == "" || strings.TrimSpace(req.EncryptedSecretKey) == "" {
		return nil, ente.NewBadRequestWithMessage("rootWrappedSpaceKey and space identity keys are required")
	}
	rootWrappedSpaceKey, err := decodeEncodedSpaceField("rootWrappedSpaceKey", req.RootWrappedSpaceKey, maxSpaceEncryptedKeyEncodedBytes, maxSpaceEncryptedKeyDecodedBytes)
	if err != nil {
		return nil, err
	}
	publicKey, err := decodeEncodedSpaceField("publicKey", req.PublicKey, maxSpaceEncryptedKeyEncodedBytes, maxSpaceEncryptedKeyDecodedBytes)
	if err != nil {
		return nil, err
	}
	encryptedSecretKey, err := decodeEncodedSpaceField("encryptedSecretKey", req.EncryptedSecretKey, maxSpaceEncryptedKeyEncodedBytes, maxSpaceEncryptedKeyDecodedBytes)
	if err != nil {
		return nil, err
	}
	encryptedProfile, err := decodeOptionalEncodedSpaceField("encryptedProfile", req.EncryptedProfile, maxSpaceEncryptedProfileEncodedBytes, maxSpaceEncryptedProfileDecodedBytes)
	if err != nil {
		return nil, err
	}
	referredBySpaceID, err := c.referredBySpaceID(ctx, userID, req.ReferredBySpaceID)
	if err != nil {
		return nil, err
	}
	space, err := c.SpacesRepo.CreateSpace(ctx, userID, normalizedSlug, rootWrappedSpaceKey, publicKey, encryptedSecretKey, encryptedProfile, referredBySpaceID)
	if err != nil {
		if errors.Is(stacktrace.RootCause(err), repo.ErrSpaceOwnerLimitReached) {
			return nil, ente.NewConflictError("space limit reached")
		}
		return nil, err
	}
	return toSpaceKeyResponse(space), nil
}

func (c *SpacesController) referredBySpaceID(ctx context.Context, userID int64, spaceID string) (string, error) {
	spaceID = strings.TrimSpace(spaceID)
	if spaceID == "" {
		return "", nil
	}
	space, err := c.SpacesRepo.GetSpaceByID(ctx, spaceID)
	if err != nil {
		if errors.Is(stacktrace.RootCause(err), sql.ErrNoRows) {
			return "", nil
		}
		return "", err
	}
	if space.OwnerID == userID {
		return "", nil
	}
	active, err := c.SpacesRepo.IsOwnerActive(ctx, space.OwnerID)
	if err != nil {
		return "", err
	}
	if !active {
		return "", nil
	}
	return space.SpaceID, nil
}

func (c *SpacesController) GetProfile(ctx *gin.Context, req models.GetSpaceProfileRequest) (*models.SpaceProfileResponse, error) {
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
	friendsCount := int64(0)
	if c.auth.FriendsRepo != nil {
		var err error
		friendsCount, err = c.auth.FriendsRepo.CountFriendsForSpace(ctx, space.SpaceID)
		if err != nil {
			return nil, err
		}
	}
	if req.Version != nil {
		if *req.Version <= 0 {
			return nil, ente.NewBadRequestWithMessage("invalid version")
		}
		if *req.Version != space.CurrentVersion {
			version, err := c.SpacesRepo.GetVersion(ctx, space.SpaceID, *req.Version)
			if err != nil {
				return nil, err
			}
			return &models.SpaceProfileResponse{
				SpaceID:          space.SpaceID,
				SpaceSlug:        space.SpaceSlug,
				Version:          version.Version,
				EncryptedProfile: encodeSpaceField(version.EncryptedProfile),
				UpdatedAt:        formatMicros(version.CreatedAt),
				Friends:          friendsCount,
			}, nil
		}
	}
	return &models.SpaceProfileResponse{
		SpaceID:          space.SpaceID,
		SpaceSlug:        space.SpaceSlug,
		Version:          space.CurrentVersion,
		EncryptedProfile: encodeSpaceField(space.EncryptedProfile),
		UpdatedAt:        formatMicros(space.UpdatedAt),
		Avatar:           toAvatarResponse(space),
		Cover:            toCoverResponse(space),
		Friends:          friendsCount,
	}, nil
}

func (c *SpacesController) UpdateProfile(ctx context.Context, current *repo.SpaceRecord, req models.UpdateSpaceProfileRequest) (*models.UpdateSpaceProfileResponse, error) {
	if strings.TrimSpace(req.EncryptedProfile) == "" || req.KeyVersion <= 0 {
		return nil, ente.NewBadRequestWithMessage("keyVersion and encryptedProfile are required")
	}
	encryptedProfile, err := decodeEncodedSpaceField("encryptedProfile", req.EncryptedProfile, maxSpaceEncryptedProfileEncodedBytes, maxSpaceEncryptedProfileDecodedBytes)
	if err != nil {
		return nil, err
	}
	if req.RemoveAvatar && req.Avatar != nil {
		return nil, ente.NewBadRequestWithMessage("avatar and removeAvatar cannot both be set")
	}
	if req.RemoveCover && req.Cover != nil {
		return nil, ente.NewBadRequestWithMessage("cover and removeCover cannot both be set")
	}
	spaceID := current.SpaceID
	if req.KeyVersion != current.CurrentVersion {
		return nil, ente.NewBadRequestWithMessage("keyVersion does not match current space version")
	}
	avatar, err := c.profileAssetUpdate(ctx, spaceID, "avatar", repo.ProfileAssetTypeAvatar, repo.TempObjectPurposeAvatar, req.Avatar)
	if err != nil {
		return nil, err
	}
	cover, err := c.profileAssetUpdate(ctx, spaceID, "cover", repo.ProfileAssetTypeCover, repo.TempObjectPurposeCover, req.Cover)
	if err != nil {
		return nil, err
	}
	space, err := c.SpacesRepo.UpdateProfile(ctx, spaceID, req.KeyVersion, encryptedProfile, avatar, cover, req.RemoveAvatar, req.RemoveCover)
	if err != nil {
		if errors.Is(stacktrace.RootCause(err), sql.ErrNoRows) {
			return nil, ente.NewBadRequestWithMessage("keyVersion does not match current space version")
		}
		return nil, err
	}
	return &models.UpdateSpaceProfileResponse{
		Status: "updated",
		Avatar: toAvatarResponse(space),
		Cover:  toCoverResponse(space),
	}, nil
}

func (c *SpacesController) profileAssetUpdate(ctx context.Context, spaceID, assetName, assetType, purpose string, payload *models.ProfileAvatarPayload) (*repo.ProfileAssetUpdate, error) {
	if payload == nil {
		return nil, nil
	}
	objectID := strings.TrimSpace(payload.ObjectID)
	if !repo.IsProfileAssetObjectID(objectID) {
		return nil, ente.NewBadRequestWithMessage(assetName + " objectID is required")
	}
	staged, err := verifyStagedUpload(ctx, c.AssetsRepo, repo.ProfileAssetObjectKey(spaceID, assetType, objectID), purpose, &spaceID)
	if err != nil {
		return nil, err
	}
	return &repo.ProfileAssetUpdate{
		ObjectID: objectID,
		BucketID: staged.BucketID,
		Size:     staged.ExpectedSize,
	}, nil
}

func (c *SpacesController) UpdateSlug(ctx context.Context, selected *repo.SpaceRecord, req models.UpdateSpaceSlugRequest) (*models.SpaceLookupResponse, error) {
	normalizedSlug, err := validateSpaceSlug(req.SpaceSlug)
	if err != nil {
		return nil, err
	}
	space, err := c.SpacesRepo.UpdateSlug(ctx, selected.SpaceID, normalizedSlug)
	if err != nil {
		return nil, err
	}
	return &models.SpaceLookupResponse{SpaceID: space.SpaceID, SpaceSlug: space.SpaceSlug, Owner: space.SpaceSlug, PublicKey: encodeSpaceField(space.PublicKey)}, nil
}

func (c *SpacesController) LookupBySlug(ctx *gin.Context, spaceSlug string) (*models.SpaceLookupResponse, error) {
	space, err := c.SpacesRepo.GetActiveSpaceBySlug(ctx, spaceSlug)
	if err != nil {
		return nil, err
	}
	return &models.SpaceLookupResponse{
		SpaceID:   space.SpaceID,
		SpaceSlug: space.SpaceSlug,
		Owner:     space.SpaceSlug,
		PublicKey: encodeSpaceField(space.PublicKey),
	}, nil
}

func (c *SpacesController) SlugAvailability(ctx *gin.Context, spaceSlug string) (*models.SpaceSlugAvailabilityResponse, error) {
	normalizedSlug, err := validateSpaceSlug(spaceSlug)
	if err != nil {
		return &models.SpaceSlugAvailabilityResponse{Available: false}, nil
	}
	if _, err := c.SpacesRepo.GetSpaceBySlug(ctx, normalizedSlug); err != nil {
		if stacktrace.RootCause(err) == sql.ErrNoRows {
			return &models.SpaceSlugAvailabilityResponse{Available: true}, nil
		}
		return nil, err
	}
	return &models.SpaceSlugAvailabilityResponse{Available: false}, nil
}

func (c *SpacesController) RotateKey(ctx context.Context, current *repo.SpaceRecord, req models.RotateSpaceKeyRequest) (*models.SpaceKeyResponse, error) {
	if strings.TrimSpace(req.RootWrappedSpaceKey) == "" || strings.TrimSpace(req.WrappedPrevKey) == "" || strings.TrimSpace(req.EncryptedProfile) == "" || req.KeyVersion <= 0 {
		return nil, ente.NewBadRequestWithMessage("keyVersion, rootWrappedSpaceKey, wrappedPrevKey and encryptedProfile are required")
	}
	rootWrappedSpaceKey, err := decodeEncodedSpaceField("rootWrappedSpaceKey", req.RootWrappedSpaceKey, maxSpaceEncryptedKeyEncodedBytes, maxSpaceEncryptedKeyDecodedBytes)
	if err != nil {
		return nil, err
	}
	wrappedPrevKey, err := decodeEncodedSpaceField("wrappedPrevKey", req.WrappedPrevKey, maxSpaceEncryptedKeyEncodedBytes, maxSpaceEncryptedKeyDecodedBytes)
	if err != nil {
		return nil, err
	}
	encryptedProfile, err := decodeEncodedSpaceField("encryptedProfile", req.EncryptedProfile, maxSpaceEncryptedProfileEncodedBytes, maxSpaceEncryptedProfileDecodedBytes)
	if err != nil {
		return nil, err
	}
	if req.KeyVersion != current.CurrentVersion {
		return nil, ente.NewBadRequestWithMessage("keyVersion does not match current space version")
	}
	space, err := c.SpacesRepo.RotateKey(ctx, current.SpaceID, req.KeyVersion, rootWrappedSpaceKey, wrappedPrevKey, encryptedProfile)
	if err != nil {
		if errors.Is(stacktrace.RootCause(err), sql.ErrNoRows) {
			return nil, ente.NewBadRequestWithMessage("keyVersion does not match current space version")
		}
		return nil, err
	}
	return toSpaceKeyResponse(space), nil
}

func (c *SpacesController) ListVersions(ctx *gin.Context, req models.GetSpaceProfileRequest) ([]models.SpaceKeyVersionResponse, error) {
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
