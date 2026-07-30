package repo

import (
	"database/sql"

	"github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
	"github.com/sirupsen/logrus"
)

// TaskLockRepository defines the methods for acquire and release locks
type TaskLockRepository struct {
	DB *sql.DB
}

func (repo *TaskLockRepository) AcquireLock(name string, lockUntil int64, lockedBy string) (bool, error) {
	result, err := repo.DB.Exec(
		`INSERT INTO task_lock(task_name, lock_until, locked_at, locked_by) VALUES($1, $2, $3, $4) 
		ON CONFLICT ON CONSTRAINT task_lock_pkey DO UPDATE SET lock_until = $2, locked_at = $3, locked_by = $4 
		where task_lock.lock_until < $3`, name, lockUntil, time.Microseconds(), lockedBy)
	if err != nil {
		return false, stacktrace.Propagate(err, "")
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return false, stacktrace.Propagate(err, "")
	}

	return rowsAffected == 1, nil
}

// ExtendLock updates the locked_at and locked_until of an existing lock (held
// by `lockedBy`).
//
// Returns false if there is no such existing lock.
func (repo *TaskLockRepository) ExtendLock(name string, lockUntil int64, lockedBy string) (bool, error) {
	result, err := repo.DB.Exec(
		`UPDATE task_lock SET locked_at = $1, lock_until = $2
		 WHERE task_name = $3 AND locked_by = $4`,
		time.Microseconds(), lockUntil, name, lockedBy)
	if err != nil {
		return false, stacktrace.Propagate(err, "")
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return false, stacktrace.Propagate(err, "")
	}

	return rowsAffected == 1, nil
}

// LastLockedAt returns the time (epoch microseconds) at which the lock with
// `name` was last acquired or refreshed.
//
// If there is no such lock, it'll return sql.ErrNoRows.
func (repo *TaskLockRepository) LastLockedAt(name string) (int64, error) {
	row := repo.DB.QueryRow(
		`SELECT locked_at FROM task_lock WHERE task_name = $1`, name)
	var lockedAt int64
	err := row.Scan(&lockedAt)
	if err != nil {
		return 0, stacktrace.Propagate(err, "")
	}
	return lockedAt, nil
}

func (repo *TaskLockRepository) ReleaseLock(name string) error {
	_, err := repo.DB.Exec(`DELETE FROM task_lock WHERE task_name = $1`, name)
	return stacktrace.Propagate(err, "")
}

func (repo *TaskLockRepository) ReleaseLocksBy(lockedBy string) (*int64, error) {
	result, err := repo.DB.Exec(`DELETE FROM task_lock WHERE locked_by = $1`, lockedBy)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &rowsAffected, nil
}

func (repo *TaskLockRepository) CleanupExpiredLocks() error {
	result, err := repo.DB.Exec(`DELETE FROM task_lock WHERE lock_until < $1`, time.Microseconds())
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if rowsAffected > 0 {
		logrus.WithField("expired_locks", rowsAffected).Error("Non zero expired locks")
	}
	return nil
}
