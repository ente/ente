package repo

import (
	"context"
	"database/sql"
	"errors"
	"fmt"

	"github.com/ente/museum/ente"
	"github.com/ente/stacktrace"
	log "github.com/sirupsen/logrus"
)

// ObjectCopiesRepository wraps over our interaction with the database related
// to the object_copies table.
type ObjectCopiesRepository struct {
	DB *sql.DB
}

// GetAndLockUnreplicatedObject gets an object which is not yet replicated to
// all the replicas. It also registers a replication to keep the row corresponding
// to that object to be blocked for 24h before next replication attemp.
//
// ObjectCopies is guaranteed to be nil if error is not nil.
func (repo *ObjectCopiesRepository) GetAndLockUnreplicatedObject(ctx context.Context) (*ente.ObjectCopies, error) {
	tx, err := repo.DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}

	rollback := func() {
		rerr := tx.Rollback()
		if rerr != nil {
			log.Errorf("Ignoring error when rolling back transaction: %s", rerr)
		}
	}

	row := tx.QueryRowContext(ctx, `
	SELECT object_key, want_b2, b2, want_wasabi, wasabi, want_scw, scw
	FROM object_copies
	WHERE (
		(
			(wasabi IS NULL AND want_wasabi = true) OR
			(scw IS NULL AND want_scw = true)
		) AND last_attempt < (now_utc_micro_seconds() - (24::BIGINT * 60 * 60 * 1000 * 1000))
	)
	LIMIT 1
	FOR UPDATE SKIP LOCKED
	`)

	var r ente.ObjectCopies
	err = row.Scan(&r.ObjectKey, &r.WantB2, &r.B2, &r.WantWasabi, &r.Wasabi,
		&r.WantSCW, &r.SCW)

	if err != nil {
		rollback() // Rollback transaction on any error
		if errors.Is(err, sql.ErrNoRows) {
			return nil, err // Return sql.ErrNoRows without committing the transaction
		}
		return nil, stacktrace.Propagate(err, "")
	}

	err = repo.RegisterReplicationAttempt(tx, ctx, r.ObjectKey)
	if err != nil {
		rollback()
		return nil, stacktrace.Propagate(err, "failed to register replication attempt")
	}

	err = tx.Commit()
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &r, nil
}

// CreateNewB2Object creates a new entry for objectKey and marks it as having
// being replicated to B2. It then sets provided flags to mark this object as
// requiring replication where needed.
//
// This operation runs within the context of a transaction that creates the
// initial entry for the file in the database; thus, it gets passed ctx and tx
// which it uses to scope its own DB changes.
func (repo *ObjectCopiesRepository) CreateNewB2Object(ctx context.Context, tx *sql.Tx, objectKey string, wantWasabi bool, wantScaleway bool) error {
	_, err := tx.ExecContext(ctx, `
	INSERT INTO object_copies (object_key, want_b2, b2, want_wasabi, want_scw)
	VALUES ($1, true, now_utc_micro_seconds(), $2, $3)
	`, objectKey, wantWasabi, wantScaleway)
	return stacktrace.Propagate(err, "")
}

// CreateNewWasabiObject creates a new entry for objectKey and marks it as having
// being replicated to Wasabi.
//
// See CreateNewB2Object for details.
func (repo *ObjectCopiesRepository) CreateNewWasabiObject(ctx context.Context, tx *sql.Tx, objectKey string, wantB2 bool, wantScaleway bool) error {
	_, err := tx.ExecContext(ctx, `
	INSERT INTO object_copies (object_key, want_wasabi, wasabi, want_b2, want_scw)
	VALUES ($1, true, now_utc_micro_seconds(), $2, $3)
	`, objectKey, wantB2, wantScaleway)
	return stacktrace.Propagate(err, "")
}

// RegisterReplicationAttempt sets the last_attempt timestamp so that this row can
// be skipped over for the next day in case the replication was not succesful.
func (repo *ObjectCopiesRepository) RegisterReplicationAttempt(tx *sql.Tx, ctx context.Context, objectKey string) error {
	_, err := tx.ExecContext(ctx, `
	UPDATE object_copies
	SET last_attempt = now_utc_micro_seconds()
	WHERE object_key = $1
	`, objectKey)
	return stacktrace.Propagate(err, "")
}

func (repo *ObjectCopiesRepository) DelayNextAttemptByDays(ctx context.Context, objectKey string, days int) error {
	_, err := repo.DB.ExecContext(ctx, `
	UPDATE object_copies
	SET last_attempt = last_attempt + ($2 * 24::BIGINT * 60 * 60 * 1000 * 1000)
	WHERE object_key = $1
	`, objectKey, days)
	return stacktrace.Propagate(err, "")
}

// ResetNeedsB2Replication modifies the db to indicate that objectKey should be
// re-replicated to Backblaze even if it has already been replicated there.
func (repo *ObjectCopiesRepository) ResetNeedsB2Replication(objectKey string) error {
	_, err := repo.DB.Exec(`UPDATE object_copies SET b2 = null WHERE object_key = $1`,
		objectKey)
	return stacktrace.Propagate(err, "")
}

// ResetNeedsWasabiReplication modifies the db to indicate that objectKey should
// be re-replicated to Wasabi even if it has already been replicated there.
func (repo *ObjectCopiesRepository) ResetNeedsWasabiReplication(objectKey string) error {
	_, err := repo.DB.Exec(`UPDATE object_copies SET wasabi = null WHERE object_key = $1`,
		objectKey)
	return stacktrace.Propagate(err, "")
}

// ResetNeedsScalewayReplication modifies the db to indicate that objectKey
// should be re-replicated to Scaleway even if it has already been replicated there.
func (repo *ObjectCopiesRepository) ResetNeedsScalewayReplication(objectKey string) error {
	_, err := repo.DB.Exec(`UPDATE object_copies SET scw = null WHERE object_key = $1`,
		objectKey)
	return stacktrace.Propagate(err, "")
}

// UnmarkFromReplication clears the want_* flags so that this objectKey is
// marked as not requiring further replication.
func (repo *ObjectCopiesRepository) UnmarkFromReplication(objectKey string) error {
	_, err := repo.DB.Exec(`
	UPDATE object_copies
	SET want_b2 = false, want_wasabi = false, want_scw = false
	WHERE object_key = $1
	`, objectKey)
	return stacktrace.Propagate(err, "")
}

// MarkObjectReplicatedB2 sets the time when `objectKey` was replicated to
// Wasabi to the current timestamp.
func (repo *ObjectCopiesRepository) MarkObjectReplicatedWasabi(objectKey string) error {
	return repo.markObjectReplicated(`
	UPDATE object_copies SET wasabi = now_utc_micro_seconds()
	WHERE object_key = $1
	`, objectKey)
}

// MarkObjectReplicatedScaleway sets the time when `objectKey` was replicated to
// Wasabi to the current timestamp.
func (repo *ObjectCopiesRepository) MarkObjectReplicatedScaleway(objectKey string) error {
	return repo.markObjectReplicated(`
	UPDATE object_copies SET scw = now_utc_micro_seconds()
	WHERE object_key = $1
	`, objectKey)
}

func (repo *ObjectCopiesRepository) markObjectReplicated(query string, objectKey string) error {
	result, err := repo.DB.Exec(query, objectKey)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	c, err := result.RowsAffected()
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if c != 1 {
		return stacktrace.Propagate(fmt.Errorf("expected 1 row to be updated, but got %d", c), "")
	}
	return nil
}
