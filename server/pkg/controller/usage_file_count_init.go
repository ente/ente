package controller

import (
	"context"
	"errors"
	"time"

	"github.com/ente/museum/pkg/controller/lock"
	"github.com/ente/museum/pkg/repo"
	timeUtil "github.com/ente/museum/pkg/utils/time"
	log "github.com/sirupsen/logrus"
)

type FileCountInitializer struct {
	UsageRepo      *repo.UsageRepository
	LockController *lock.LockController
	afterUserID    int64
	resumeAt       time.Time
}

const (
	fileCountInitializationBatchSize = 10
	fileCountInitializationLock      = "file_count_initialization"
)

func (c *FileCountInitializer) ProcessBatch() {
	if !c.LockController.TryLock(fileCountInitializationLock, timeUtil.MicrosecondsAfterHours(3)) {
		return
	}
	defer c.LockController.ReleaseLock(fileCountInitializationLock)
	if time.Now().Before(c.resumeAt) {
		return
	}

	userIDs, err := c.UsageRepo.GetFileCountInitializationCandidates(context.Background(), c.afterUserID, fileCountInitializationBatchSize)
	if err != nil {
		log.WithError(err).Error("Failed to fetch file count initialization candidates")
		return
	}
	if len(userIDs) == 0 {
		c.afterUserID = 0
		c.resumeAt = time.Now().Add(24 * time.Hour)
		return
	}

	initialized, deferred, ineligible := 0, 0, 0
	for _, userID := range userIDs {
		c.afterUserID = userID
		updated, err := c.UsageRepo.InitializeFileCounts(context.Background(), userID)
		if errors.Is(err, repo.ErrFileCountIneligible) {
			ineligible++
			log.WithError(err).WithField("user_id", userID).Warn("File count initialization ineligible")
			continue
		}
		if err != nil {
			log.WithError(err).WithField("user_id", userID).Error("Failed to initialize file counts")
			return
		}
		if updated {
			initialized++
		} else {
			deferred++
		}
	}
	if len(userIDs) < fileCountInitializationBatchSize {
		c.afterUserID = 0
		c.resumeAt = time.Now().Add(24 * time.Hour)
	}
	log.WithFields(log.Fields{
		"attempted":    len(userIDs),
		"initialized":  initialized,
		"deferred":     deferred,
		"ineligible":   ineligible,
		"last_user_id": userIDs[len(userIDs)-1],
	}).Info("Processed file count initialization batch")
}
