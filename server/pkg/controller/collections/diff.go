package collections

import (
	"github.com/ente/museum/ente"
	"github.com/ente/stacktrace"
)

// GetOwnedV2 returns the list of collections owned by a user using optimized query
func (c *CollectionController) GetOwnedV2(userID int64, sinceTime int64, app ente.App, limit *int64) ([]ente.Collection, error) {
	collections, err := c.CollectionRepo.GetCollectionsOwnedByUserV2(userID, sinceTime, app, limit)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return collections, nil
}

// GetSharedWith returns the list of collections that are shared with a user
func (c *CollectionController) GetSharedWith(userID int64, sinceTime int64, app ente.App, limit *int64) ([]ente.Collection, error) {
	collections, err := c.CollectionRepo.GetCollectionsSharedWithUser(userID, sinceTime, app, limit)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return collections, nil
}
