package usercache

import (
	"context"
	"github.com/ente/museum/ente/cache"
	bonus "github.com/ente/museum/ente/storagebonus"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/repo/storagebonus"
	"github.com/ente/stacktrace"
)

// Controller is the controller for the data cache.
// It contains all the repositories that are used by the controller.
// Avoid adding any direct dependencies to the other controller.
type Controller struct {
	FileRepo       *repo.FileRepository
	UsageRepo      *repo.UsageRepository
	TrashRepo      *repo.TrashRepository
	StoreBonusRepo *storagebonus.Repository
	UserCache      *cache.UserCache
}

func (c *Controller) GetActiveStorageBonus(ctx context.Context, userID int64) (*bonus.ActiveStorageBonus, error) {
	// Check if the value is present in the cache
	if bonus, ok := c.UserCache.GetBonus(userID); ok {
		// Cache hit, update the cache asynchronously
		go func() {
			_, _ = c.getAndCacheActiveStorageBonus(ctx, userID)
		}()
		return bonus, nil
	}
	return c.getAndCacheActiveStorageBonus(ctx, userID)
}

func (c *Controller) getAndCacheActiveStorageBonus(ctx context.Context, userID int64) (*bonus.ActiveStorageBonus, error) {
	bonus, err := c.StoreBonusRepo.GetActiveStorageBonuses(ctx, userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	c.UserCache.SetBonus(userID, bonus)
	return bonus, nil
}
