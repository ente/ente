package lock

import (
	"fmt"

	"github.com/ente/museum/pkg/repo"
	"github.com/ente/stacktrace"
	log "github.com/sirupsen/logrus"
)

// LockController exposes functions to obtain locks before entering critical sections
type LockController struct {
	TaskLockingRepo *repo.TaskLockRepository
	HostName        string
}

// Try to obtain a lock with the given lockID.
//
// Return false if the lock is already taken.
//
// A call to this function should be matched by a call to ReleaseLock. A common
// pattern is to put the ReleaseLock into a defer statement immediately
// following the lock acquisition.
//
// However, it is also fine to omit the release. Such would be useful for cases
// where we want to ensure the same job cannot run again until the expiry time
// is past.
func (c *LockController) TryLock(lockID string, lockUntil int64) bool {
	lockStatus, err := c.TaskLockingRepo.AcquireLock(lockID, lockUntil, c.HostName)
	if err != nil || !lockStatus {
		return false
	}
	return true
}

// ExtendLock refreshes an existing lock by updating its locked_at to now and
// extending its lockUntil.
//
// It is only valid to call this method when holding an existing lock previously
// obtained using TryLock.
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

// Release a lock that was obtained earlier using TryLock.
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
