package usercache

import (
	"github.com/ente/museum/ente"
	"github.com/ente/museum/ente/cache"
	"github.com/ente/stacktrace"
	"github.com/sirupsen/logrus"
)

func (c *Controller) GetUserFileCountWithCache(userID int64, app ente.App) (int64, error) {
	// Check if the value is present in the cache
	if count, ok := c.UserCache.GetFileCount(userID, app); ok {
		// Cache hit, update the cache asynchronously
		go func() {
			_, _ = c.getUserCountAndUpdateCache(userID, app, count)
		}()
		return count.Count, nil
	}
	return c.getUserCountAndUpdateCache(userID, app, nil)
}

func (c *Controller) getUserCountAndUpdateCache(userID int64, app ente.App, oldCache *cache.FileCountCache) (int64, error) {
	usage, err := c.UsageRepo.GetUsage(userID)
	if err != nil {
		return 0, stacktrace.Propagate(err, "")
	}
	trashUpdatedAt, err := c.TrashRepo.GetTrashUpdatedAt(userID)
	if err != nil {
		return 0, stacktrace.Propagate(err, "")
	}
	if oldCache != nil && oldCache.Usage == usage && oldCache.TrashUpdatedAt == trashUpdatedAt && app != ente.Locker {
		logrus.Debugf("Cache hit for user %d", userID)
		return oldCache.Count, nil
	}
	count, err := c.FileRepo.GetFileCountForUser(userID, app)
	if err != nil {
		return 0, stacktrace.Propagate(err, "")
	}
	cntCache := &cache.FileCountCache{
		Count:          count,
		Usage:          usage,
		TrashUpdatedAt: trashUpdatedAt,
	}
	c.UserCache.SetFileCount(userID, cntCache, app)
	return count, nil
}
