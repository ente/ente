package social

import (
	"context"
	"sort"

	"github.com/ente/museum/ente"
	socialentity "github.com/ente/museum/ente/social"
	"github.com/ente/museum/pkg/controller/access"
	"github.com/ente/museum/pkg/repo"
	socialrepo "github.com/ente/museum/pkg/repo/social"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
)

type Controller struct {
	CommentsRepo   *socialrepo.CommentsRepository
	ReactionsRepo  *socialrepo.ReactionsRepository
	CollectionRepo *repo.CollectionRepository
	AccessCtrl     access.Controller
	AnonUsersRepo  *socialrepo.AnonUsersRepository
}

type UnifiedDiffRequest struct {
	Actor          Actor
	CollectionID   int64
	CommentsSince  int64
	ReactionsSince int64
	Limit          int
	FileID         *int64
	RequireAccess  bool
}

type CollectionLatestUpdate struct {
	CollectionID          int64  `json:"collectionID"`
	CommentsUpdatedAt     *int64 `json:"commentsUpdatedAt,omitempty"`
	ReactionsUpdatedAt    *int64 `json:"reactionsUpdatedAt,omitempty"`
	AnonProfilesUpdatedAt *int64 `json:"anonProfilesUpdatedAt,omitempty"`
}

type AnonProfilesRequest struct {
	Actor         Actor
	CollectionID  int64
	RequireAccess bool
}

func (c *Controller) UnifiedDiff(ctx *gin.Context, req UnifiedDiffRequest) ([]socialentity.Comment, []socialentity.Reaction, bool, bool, error) {
	if req.RequireAccess {
		userID, hasUserID := req.Actor.UserIDValue()
		if !hasUserID || userID <= 0 {
			return nil, nil, false, false, ente.ErrAuthenticationRequired
		}
		if _, err := c.AccessCtrl.GetCollection(ctx, &access.GetCollectionParams{
			CollectionID: req.CollectionID,
			ActorUserID:  userID,
		}); err != nil {
			return nil, nil, false, false, stacktrace.Propagate(err, "")
		}
	}
	comments, moreComments, err := c.CommentsRepo.GetDiff(ctx, req.CollectionID, req.CommentsSince, req.Limit, req.FileID)
	if err != nil {
		return nil, nil, false, false, stacktrace.Propagate(err, "")
	}
	reactions, moreReactions, err := c.ReactionsRepo.GetDiff(ctx, req.CollectionID, req.ReactionsSince, req.Limit, req.FileID, nil)
	if err != nil {
		return nil, nil, false, false, stacktrace.Propagate(err, "")
	}
	return comments, reactions, moreComments, moreReactions, nil
}

func (c *Controller) LatestUpdates(ctx context.Context, userID int64, app ente.App) ([]CollectionLatestUpdate, error) {
	ownedMap, err := c.CollectionRepo.GetCollectionIDsOwnedByUser(userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	shared, err := c.CollectionRepo.GetCollectionIDsSharedWithUser(userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	candidateIDs := make([]int64, 0, len(ownedMap)+len(shared))
	for id := range ownedMap {
		candidateIDs = append(candidateIDs, id)
	}
	candidateIDs = append(candidateIDs, shared...)
	if len(candidateIDs) == 0 {
		return nil, nil
	}
	collectionIDs, err := c.CollectionRepo.FilterNonDeletedCollectionIDs(candidateIDs, app)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	if len(collectionIDs) == 0 {
		return nil, nil
	}

	commentUpdates, err := c.CommentsRepo.LatestUpdateByCollection(ctx, collectionIDs)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	reactionUpdates, err := c.ReactionsRepo.LatestUpdateByCollection(ctx, collectionIDs)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	anonUpdates := map[int64]int64{}
	if c.AnonUsersRepo != nil {
		anonUpdates, err = c.AnonUsersRepo.LatestUpdateByCollection(ctx, collectionIDs)
		if err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
	}

	activityMap := make(map[int64]*CollectionLatestUpdate)
	assignComment := func(collectionID int64, updatedAt int64) {
		entry, ok := activityMap[collectionID]
		if !ok {
			entry = &CollectionLatestUpdate{CollectionID: collectionID}
			activityMap[collectionID] = entry
		}
		ts := updatedAt
		entry.CommentsUpdatedAt = &ts
	}
	assignReaction := func(collectionID int64, updatedAt int64) {
		entry, ok := activityMap[collectionID]
		if !ok {
			entry = &CollectionLatestUpdate{CollectionID: collectionID}
			activityMap[collectionID] = entry
		}
		ts := updatedAt
		entry.ReactionsUpdatedAt = &ts
	}
	assignAnon := func(collectionID int64, updatedAt int64) {
		entry, ok := activityMap[collectionID]
		if !ok {
			entry = &CollectionLatestUpdate{CollectionID: collectionID}
			activityMap[collectionID] = entry
		}
		ts := updatedAt
		entry.AnonProfilesUpdatedAt = &ts
	}

	for id, ts := range commentUpdates {
		assignComment(id, ts)
	}
	for id, ts := range reactionUpdates {
		assignReaction(id, ts)
	}
	for id, ts := range anonUpdates {
		assignAnon(id, ts)
	}
	if len(activityMap) == 0 {
		return nil, nil
	}

	ids := make([]int64, 0, len(activityMap))
	for id := range activityMap {
		ids = append(ids, id)
	}
	sort.Slice(ids, func(i, j int) bool {
		return ids[i] < ids[j]
	})

	results := make([]CollectionLatestUpdate, 0, len(activityMap))
	for _, id := range ids {
		results = append(results, *activityMap[id])
	}
	return results, nil
}

func (c *Controller) ListAnonProfiles(ctx *gin.Context, req AnonProfilesRequest) ([]socialentity.AnonUser, error) {
	if req.RequireAccess {
		userID, hasUserID := req.Actor.UserIDValue()
		if !hasUserID || userID <= 0 {
			return nil, ente.ErrAuthenticationRequired
		}
		if _, err := c.AccessCtrl.GetCollection(ctx, &access.GetCollectionParams{
			CollectionID: req.CollectionID,
			ActorUserID:  userID,
		}); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
	}
	return c.AnonUsersRepo.ListByCollection(ctx, req.CollectionID)
}
