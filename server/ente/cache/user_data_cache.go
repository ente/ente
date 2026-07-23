package cache

import (
	"fmt"
	"github.com/ente/museum/ente"
	"github.com/ente/museum/ente/storagebonus"
	"sync"
)

// UserCache struct holds can be used to fileCount various entities for user.
type UserCache struct {
	mu         sync.Mutex
	fileCache  map[string]*FileCountCache
	bonusCache map[int64]*storagebonus.ActiveStorageBonus
}

type FileCountCache struct {
	Count          int64
	TrashUpdatedAt int64
	Usage          int64
}

// NewUserCache creates a new instance of the UserCache struct.
func NewUserCache() *UserCache {
	return &UserCache{
		fileCache:  make(map[string]*FileCountCache),
		bonusCache: make(map[int64]*storagebonus.ActiveStorageBonus),
	}
}

// SetFileCount updates the fileCount with the given userID and fileCount.
func (c *UserCache) SetFileCount(userID int64, fileCount *FileCountCache, app ente.App) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.fileCache[cacheKey(userID, app)] = fileCount
}

func (c *UserCache) SetBonus(userID int64, bonus *storagebonus.ActiveStorageBonus) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.bonusCache[userID] = bonus
}

func (c *UserCache) GetBonus(userID int64) (*storagebonus.ActiveStorageBonus, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	bonus, ok := c.bonusCache[userID]
	return bonus, ok
}

// GetFileCount retrieves the file count from the fileCount for the given userID.
// It returns the file count and a boolean indicating if the value was found.
func (c *UserCache) GetFileCount(userID int64, app ente.App) (*FileCountCache, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	count, ok := c.fileCache[cacheKey(userID, app)]
	return count, ok
}

func cacheKey(userID int64, app ente.App) string {
	return fmt.Sprintf("%d-%s", userID, app)
}
