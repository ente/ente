package controller

import (
	"errors"
	"testing"
	"testing/synctest"
	"time"

	"github.com/ente/museum/pkg/repo"
	"github.com/spf13/viper"
	"github.com/stretchr/testify/require"
)

func TestObjectCopiesCleanupWorkerRetriesAndFinishes(t *testing.T) {
	viper.Reset()
	t.Cleanup(viper.Reset)
	synctest.Test(t, func(t *testing.T) {
		start := time.Now()
		attempts := make(chan time.Duration, 3)
		attemptCount := 0
		cleanupController := &ObjectCopiesCleanupController{
			Repo: objectCopiesCleanupRepoFunc(func(batchSize int, interval time.Duration) (repo.CleanupBatch, error) {
				attempts <- time.Since(start)
				attemptCount++
				switch attemptCount {
				case 1:
					return repo.CleanupBatch{}, errors.New("temporary database failure")
				case 2:
					return repo.CleanupBatch{Scanned: batchSize, RetryAfter: interval}, nil
				default:
					return repo.CleanupBatch{Completed: true}, nil
				}
			}),
		}
		cleanupController.StartCleanup()
		require.Zero(t, time.Since(start), "starting cleanup must not block startup")
		synctest.Wait()
		require.Empty(t, attempts)
		time.Sleep(11*time.Minute + time.Second)
		synctest.Wait()
		require.Equal(t, []time.Duration{10 * time.Minute, 11 * time.Minute, 11*time.Minute + time.Second},
			[]time.Duration{<-attempts, <-attempts, <-attempts})
	})
}

type objectCopiesCleanupRepoFunc func(int, time.Duration) (repo.CleanupBatch, error)

func (f objectCopiesCleanupRepoFunc) PruneCompletedReplicationBatch(batchSize int, interval time.Duration) (repo.CleanupBatch, error) {
	return f(batchSize, interval)
}
