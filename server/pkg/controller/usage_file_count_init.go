package controller

import (
	"context"
	"errors"
	"strconv"
	"sync"
	"time"

	"github.com/ente/museum/pkg/controller/lock"
	"github.com/ente/museum/pkg/repo"
	timeUtil "github.com/ente/museum/pkg/utils/time"
	log "github.com/sirupsen/logrus"
)

type FileCountInitializer struct {
	UsageRepo      *repo.UsageRepository
	TrashRepo      *repo.TrashRepository
	LockController *lock.LockController
	queue          chan int64
	mu             sync.Mutex
	attemptedAt    map[int64]time.Time
	lastPrunedAt   time.Time
}

const (
	fileCountInitializationQueueSize = 100
	fileCountInitializationRetry     = time.Hour
	fileCountInitializationLock      = "file_count_initialization"
)

func NewFileCountInitializer(usageRepo *repo.UsageRepository, trashRepo *repo.TrashRepository, lockController *lock.LockController) *FileCountInitializer {
	return &FileCountInitializer{
		UsageRepo:      usageRepo,
		TrashRepo:      trashRepo,
		LockController: lockController,
		queue:          make(chan int64, fileCountInitializationQueueSize),
		attemptedAt:    make(map[int64]time.Time),
		lastPrunedAt:   time.Now(),
	}
}

func (c *FileCountInitializer) Enqueue(userID int64) {
	now := time.Now()
	c.mu.Lock()
	defer c.mu.Unlock()
	if attemptedAt, ok := c.attemptedAt[userID]; ok && (attemptedAt.IsZero() || now.Sub(attemptedAt) < fileCountInitializationRetry) {
		return
	}
	select {
	case c.queue <- userID:
		c.attemptedAt[userID] = time.Time{}
	default:
	}
}

func (c *FileCountInitializer) Run() {
	for userID := range c.queue {
		retry := c.initializeUser(userID)
		now := time.Now()
		c.mu.Lock()
		if retry {
			delete(c.attemptedAt, userID)
		} else {
			c.attemptedAt[userID] = now
		}
		if now.Sub(c.lastPrunedAt) >= fileCountInitializationRetry {
			for id, attemptedAt := range c.attemptedAt {
				if !attemptedAt.IsZero() && now.Sub(attemptedAt) >= fileCountInitializationRetry {
					delete(c.attemptedAt, id)
				}
			}
			c.lastPrunedAt = now
		}
		c.mu.Unlock()
	}
}

func (c *FileCountInitializer) initializeUser(userID int64) bool {
	lockID := fileCountInitializationLock + ":" + strconv.FormatInt(userID, 10)
	if !c.LockController.TryLock(lockID, timeUtil.MicrosecondsAfterHours(3)) {
		return false
	}
	defer c.LockController.ReleaseLock(lockID)

	ctx := context.Background()
	initialized, err := c.UsageRepo.InitializeFileCounts(ctx, userID)
	if errors.Is(err, repo.ErrFileCountIneligible) {
		fileIDs, cleanupErr := c.TrashRepo.GetStaleDeletedFileIDs(ctx, userID)
		if cleanupErr != nil {
			log.WithError(cleanupErr).WithField("user_id", userID).Error("Failed to find stale deleted file memberships")
		}
		cleaned := false
		for _, fileID := range fileIDs {
			if cleanupErr := c.TrashRepo.CleanUpDeletedFilesFromCollection(ctx, []int64{fileID}, userID); cleanupErr != nil {
				log.WithError(cleanupErr).WithFields(log.Fields{
					"user_id": userID,
					"file_id": fileID,
				}).Error("Failed to clean stale deleted file membership")
			} else {
				cleaned = true
			}
		}
		log.WithError(err).WithField("user_id", userID).Warn("File count initialization ineligible")
		return cleaned
	}
	if err != nil {
		log.WithError(err).WithField("user_id", userID).Error("Failed to initialize file counts")
	} else if initialized {
		log.WithField("user_id", userID).Info("Initialized file counts")
	}
	return false
}
