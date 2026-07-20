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

type FriendsController struct {
	FriendsRepo   *repo.FriendsRepository
	SpacesRepo    *repo.SpacesRepository
	EmailNotifier SpaceEmailNotifier
}

func (c *FriendsController) Add(ctx context.Context, requesterSpace *repo.SpaceRecord, req models.AddFriendPayload) (*models.FriendStatusResponse, error) {
	if (strings.TrimSpace(req.TargetSpaceID) == "" && strings.TrimSpace(req.TargetUsername) == "") ||
		strings.TrimSpace(req.RequesterFriendSealedSpaceKey) == "" ||
		req.RequesterKeyVersion <= 0 {
		return nil, ente.NewBadRequestWithMessage("targetSpaceId or targetUsername, requesterFriendSealedSpaceKey and requesterKeyVersion are required")
	}
	requesterFriendSealedSpaceKey, err := decodeEncodedSpaceField("requesterFriendSealedSpaceKey", req.RequesterFriendSealedSpaceKey, maxSpaceEncryptedKeyEncodedBytes, maxSpaceEncryptedKeyDecodedBytes)
	if err != nil {
		return nil, err
	}
	var targetSpace *repo.SpaceRecord
	switch {
	case strings.TrimSpace(req.TargetSpaceID) != "":
		targetSpace, err = c.SpacesRepo.GetSpaceByID(ctx, strings.TrimSpace(req.TargetSpaceID))
	case strings.TrimSpace(req.TargetUsername) != "":
		targetSpace, err = c.SpacesRepo.GetSpaceBySlug(ctx, strings.TrimSpace(req.TargetUsername))
	}
	if err != nil {
		return nil, err
	}
	request, created, becameFriends, err := c.FriendsRepo.CreateFriendRequest(
		ctx,
		requesterSpace.OwnerID,
		requesterSpace.SpaceID,
		targetSpace.SpaceID,
		requesterFriendSealedSpaceKey,
		req.RequesterKeyVersion,
	)
	if err != nil {
		if errors.Is(stacktrace.RootCause(err), repo.ErrSelfFriendship) {
			return nil, ente.NewBadRequestWithMessage("cannot add yourself as a friend")
		}
		if errors.Is(stacktrace.RootCause(err), repo.ErrAlreadyFriends) {
			return &models.FriendStatusResponse{Status: "friend"}, nil
		}
		if errors.Is(stacktrace.RootCause(err), sql.ErrNoRows) {
			return nil, ente.NewBadRequestWithMessage("space key version is stale")
		}
		if errors.Is(stacktrace.RootCause(err), repo.ErrSpaceFriendRequestLimitReached) {
			return nil, ente.NewConflictError("space friend request limit reached")
		}
		return nil, err
	}
	if becameFriends {
		if c.EmailNotifier != nil {
			go c.EmailNotifier.OnSpaceFriendAdded(requesterSpace.OwnerID, requesterSpace.SpaceSlug, request.RequesterID)
		}
		return &models.FriendStatusResponse{Status: "friend"}, nil
	}
	if created && c.EmailNotifier != nil {
		go c.EmailNotifier.OnSpaceFriendRequested(requesterSpace.OwnerID, requesterSpace.SpaceSlug, request.TargetID)
	}
	return &models.FriendStatusResponse{Status: "requested"}, nil
}

func (c *FriendsController) ListRequests(ctx context.Context, space *repo.SpaceRecord) ([]models.SpaceFriendRequestResponse, error) {
	requests, err := c.FriendsRepo.ListFriendRequestsForSpace(ctx, space.SpaceID)
	if err != nil {
		return nil, err
	}
	resp := make([]models.SpaceFriendRequestResponse, 0, len(requests))
	for _, request := range requests {
		resp = append(resp, models.SpaceFriendRequestResponse{
			RequestID: request.RequestID,
			Requester: toActorResponse(request.Requester, true),
			CreatedAt: formatMicros(request.CreatedAt),
		})
	}
	return resp, nil
}

func (c *FriendsController) ConfirmRequest(ctx context.Context, targetSpace *repo.SpaceRecord, requestID int64, req models.ConfirmFriendRequestPayload) (*models.FriendStatusResponse, error) {
	if strings.TrimSpace(req.TargetFriendSealedSpaceKey) == "" || req.TargetKeyVersion <= 0 {
		return nil, ente.NewBadRequestWithMessage("targetFriendSealedSpaceKey and targetKeyVersion are required")
	}
	targetFriendSealedSpaceKey, err := decodeEncodedSpaceField("targetFriendSealedSpaceKey", req.TargetFriendSealedSpaceKey, maxSpaceEncryptedKeyEncodedBytes, maxSpaceEncryptedKeyDecodedBytes)
	if err != nil {
		return nil, err
	}
	requesterID, created, err := c.FriendsRepo.ConfirmFriendRequest(
		ctx,
		targetSpace.SpaceID,
		requestID,
		targetFriendSealedSpaceKey,
		req.TargetKeyVersion,
	)
	if err != nil {
		if errors.Is(stacktrace.RootCause(err), sql.ErrNoRows) {
			return nil, ente.NewBadRequestWithMessage("friend request is stale or no longer available")
		}
		return nil, err
	}
	if created && c.EmailNotifier != nil {
		go c.EmailNotifier.OnSpaceFriendAdded(targetSpace.OwnerID, targetSpace.SpaceSlug, requesterID)
	}
	return &models.FriendStatusResponse{Status: "friend"}, nil
}

func (c *FriendsController) DeleteRequest(ctx context.Context, targetSpace *repo.SpaceRecord, requestID int64) error {
	if err := c.FriendsRepo.DeleteFriendRequest(ctx, targetSpace.SpaceID, requestID); err != nil {
		if errors.Is(stacktrace.RootCause(err), sql.ErrNoRows) {
			return ente.ErrNotFound
		}
		return err
	}
	return nil
}

func (c *FriendsController) Unfriend(ctx context.Context, actorSpace *repo.SpaceRecord, req models.FriendTargetPayload) error {
	var space *repo.SpaceRecord
	var err error
	switch {
	case req.TargetSpaceID != nil && strings.TrimSpace(*req.TargetSpaceID) != "":
		space, err = c.SpacesRepo.GetSpaceByID(ctx, strings.TrimSpace(*req.TargetSpaceID))
	case req.TargetUsername != nil && strings.TrimSpace(*req.TargetUsername) != "":
		space, err = c.SpacesRepo.GetSpaceBySlug(ctx, strings.TrimSpace(*req.TargetUsername))
	default:
		return ente.NewBadRequestWithMessage("targetUsername or targetSpaceId is required")
	}
	if err != nil {
		return err
	}
	return c.FriendsRepo.DeleteFriendship(ctx, actorSpace.SpaceID, space.SpaceID)
}

func (c *FriendsController) ListFriends(ctx context.Context, space *repo.SpaceRecord) ([]models.SpaceFriendResponse, error) {
	friends, err := c.FriendsRepo.ListFriendsForSpace(ctx, space.SpaceID)
	if err != nil {
		return nil, err
	}
	resp := make([]models.SpaceFriendResponse, 0, len(friends))
	for _, friend := range friends {
		resp = append(resp, models.SpaceFriendResponse{
			Friend:          toActorResponse(friend.Friend, true),
			ShareKeyVersion: friend.ShareKeyVersion,
			CreatedAt:       formatMicros(friend.CreatedAt),
		})
	}
	return resp, nil
}

func (c *FriendsController) Relationship(ctx context.Context, viewerSpace *repo.SpaceRecord, req models.FriendRelationshipRequest) (*models.FriendRelationshipResponse, error) {
	targetSpaceID := strings.TrimSpace(req.TargetSpaceID)
	if targetSpaceID == "" {
		return nil, ente.NewBadRequestWithMessage("targetSpaceId is required")
	}
	targetSpace, err := c.SpacesRepo.GetSpaceByID(ctx, targetSpaceID)
	if err != nil {
		return nil, err
	}
	if viewerSpace.OwnerID == targetSpace.OwnerID {
		return &models.FriendRelationshipResponse{Relationship: "self"}, nil
	}
	relationship, err := c.FriendsRepo.GetRelationship(ctx, viewerSpace.SpaceID, targetSpace.SpaceID)
	if err != nil {
		return nil, err
	}
	return &models.FriendRelationshipResponse{Relationship: relationship}, nil
}

func (c *FriendsController) RefreshShares(ctx context.Context, space *repo.SpaceRecord, req models.RefreshFriendSharesRequest) error {
	if req.KeyVersion <= 0 {
		return ente.NewBadRequestWithMessage("keyVersion is required")
	}
	if len(req.Shares) > maxSpaceFriendSharesPerRefresh {
		return ente.NewBadRequestWithMessage("too many friend shares")
	}
	updates := make([]repo.SpaceShareUpdateRecord, 0, len(req.Shares))
	for _, share := range req.Shares {
		if strings.TrimSpace(share.FriendSpaceID) == "" || strings.TrimSpace(share.FriendSealedSpaceKey) == "" {
			return ente.NewBadRequestWithMessage("friendSpaceId and friendSealedSpaceKey are required for each share")
		}
		friendSealedSpaceKey, err := decodeEncodedSpaceField("friendSealedSpaceKey", share.FriendSealedSpaceKey, maxSpaceEncryptedKeyEncodedBytes, maxSpaceEncryptedKeyDecodedBytes)
		if err != nil {
			return err
		}
		updates = append(updates, repo.SpaceShareUpdateRecord{
			FriendSpaceID:        strings.TrimSpace(share.FriendSpaceID),
			FriendSealedSpaceKey: friendSealedSpaceKey,
		})
	}
	if err := c.FriendsRepo.UpdateShares(ctx, space.SpaceID, updates, req.KeyVersion); err != nil {
		if errors.Is(stacktrace.RootCause(err), sql.ErrNoRows) {
			return ente.NewBadRequestWithMessage("keyVersion does not match current space version or friend share does not exist")
		}
		return err
	}
	return nil
}

func (c *FriendsController) ListShares(ctx context.Context, space *repo.SpaceRecord) ([]models.FriendShareResponse, error) {
	shares, err := c.FriendsRepo.ListSharesForFriendAndSpace(ctx, space.SpaceID)
	if err != nil {
		return nil, err
	}
	resp := make([]models.FriendShareResponse, 0, len(shares))
	for _, share := range shares {
		resp = append(resp, models.FriendShareResponse{
			Friend:               share.SpaceSlug,
			SpaceID:              share.SpaceID,
			SpaceSlug:            share.SpaceSlug,
			FriendSealedSpaceKey: encodeSpaceField(share.FriendSealedSpaceKey),
			KeyVersion:           share.KeyVersion,
		})
	}
	return resp, nil
}
