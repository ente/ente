package repo

import "time"

func (repo *ObjectCopiesRepository) PruneCompletedReplicationBatch(batchSize int, interval time.Duration) (CleanupBatch, error) {
	cleanupRepo := &CleanupRepository{DB: repo.DB}
	return cleanupRepo.PruneBatch(CleanupSpec{
		Name:      "object_copies_completed_v1",
		Table:     "object_copies",
		KeyColumn: "object_key",
		DeleteCondition: `(want_b2 = false OR b2 IS NOT NULL)
			AND (want_wasabi = false OR wasabi IS NOT NULL)
			AND (want_scw = false OR scw IS NOT NULL)`,
	}, batchSize, interval)
}
