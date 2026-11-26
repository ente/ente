package controller

import (
	"time"

	"github.com/ente/museum/pkg/repo"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/viper"
)

type objectCopiesCleanupRepository interface {
	PruneCompletedReplicationBatch(int, time.Duration) (repo.CleanupBatch, error)
}

type ObjectCopiesCleanupController struct {
	Repo objectCopiesCleanupRepository
}

func NewObjectCopiesCleanupController(repository *repo.ObjectCopiesRepository) *ObjectCopiesCleanupController {
	return &ObjectCopiesCleanupController{Repo: repository}
}

func (c *ObjectCopiesCleanupController) StartCleanup() {
	batchSize := viper.GetInt("jobs.prune-object-copies.batch-size")
	if batchSize <= 0 {
		batchSize = 1000
	}
	interval := viper.GetDuration("jobs.prune-object-copies.batch-interval")
	if interval <= 0 {
		interval = time.Second
	}
	go c.runCleanup(batchSize, interval)
}

func (c *ObjectCopiesCleanupController) runCleanup(batchSize int, interval time.Duration) {
	logger := log.WithField("task", "prune-object-copies")
	delay := 10 * time.Minute
	for {
		time.Sleep(delay)
		start := time.Now()
		batch, err := c.Repo.PruneCompletedReplicationBatch(batchSize, interval)
		if err != nil {
			logger.WithError(err).Warn("Failed to prune completed replication; will retry")
			delay = time.Minute
			continue
		}
		if batch.Scanned > 0 {
			logger.WithFields(log.Fields{
				"scanned":  batch.Scanned,
				"deleted":  batch.Deleted,
				"duration": time.Since(start),
			}).Info("Pruned completed replication batch")
		}
		if batch.Completed {
			logger.Info("Historical object copies cleanup is complete")
			return
		}
		delay = batch.RetryAfter
	}
}
