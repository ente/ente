package lock

import (
	"fmt"

	"github.com/ente/museum/pkg/repo"
	"github.com/ente/stacktrace"
	log "github.com/sirupsen/logrus"
)

type LockController struct {
	TaskLockingRepo *repo.TaskLockRepository
	HostName        string
}

// Leaving a lock unreleased prevents another run until it expires.
func (c *LockController) TryLock(lockID string, lockUntil int64) bool {
	lockStatus, err := c.TaskLockingRepo.AcquireLock(lockID, lockUntil, c.HostName)
	if err != nil || !lockStatus {
		return false
	}
	return true
}

// Only the host holding a lock can extend it.
func (c *LockController) ExtendLock(lockID string, lockUntil int64) error {
	foundLock, err := c.TaskLockingRepo.ExtendLock(lockID, lockUntil, c.HostName)
	if err != nil {
		return stacktrace.Propagate(err, "Unable to extend lock %v", lockID)
	}
	if !foundLock {
		return fmt.Errorf("no existing lock for %v", lockID)
	}
	return nil
}

func (c *LockController) ReleaseLock(lockID string) {
	err := c.TaskLockingRepo.ReleaseLock(lockID)
	if err != nil {
		log.Errorf("Error while releasing lock %v: %s", lockID, err)
	}
}

func (c *LockController) ReleaseHostLock() {
	count, err := c.TaskLockingRepo.ReleaseLocksBy(c.HostName)
	if err != nil {
		log.Errorf("Error while releasing host lock: %s", err)
	}
	log.Infof("Released %d locks held by %s", *count, c.HostName)
}
