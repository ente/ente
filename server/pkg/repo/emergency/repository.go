package emergency

import (
	"context"
	"database/sql"
	"github.com/ente/museum/ente"
	"github.com/ente/stacktrace"
	"github.com/lib/pq"
)

type Repository struct {
	DB *sql.DB
}

type ContactRow struct {
	UserID             int64
	EmergencyContactID int64
	State              ente.ContactState
	NoticePeriodInHrs  int32
	EncryptedKey       *string
}

func (r *Repository) HasActiveLegacyContact(ctx context.Context, userID int64) (bool, error) {
	var exists bool
	err := r.DB.QueryRowContext(ctx,
		`SELECT EXISTS(
			SELECT 1
			FROM emergency_contact
			WHERE user_id = $1 AND state = $2
		)`,
		userID,
		ente.ContactAccepted,
	).Scan(&exists)
	if err != nil {
		return false, stacktrace.Propagate(err, "failed to check active legacy contact")
	}
	return exists, nil
}

func (r *Repository) AddEmergencyContact(ctx context.Context, userID int64, emergencyContactID int64, encKey string, noticeInHrs int) (bool, error) {
	if userID == emergencyContactID {
		return false, ente.NewBadRequestWithMessage("user cannot add themself as emergency contact")
	}
	result, err := r.DB.ExecContext(ctx, `
INSERT INTO  emergency_contact(user_id, emergency_contact_id, state, encrypted_key, notice_period_in_hrs) VALUES ($1,$2,$3,$4,$5)
ON CONFLICT (user_id, emergency_contact_id) DO UPDATE SET state=$3, encrypted_key=$4, notice_period_in_hrs=$5 
WHERE emergency_contact.user_id=$1 AND emergency_contact.emergency_contact_id=$2 AND emergency_contact.state = ANY($6)`,
		userID,
		emergencyContactID,
		ente.UserInvitedContact,
		encKey,
		noticeInHrs,
		pq.Array([]ente.ContactState{ente.ContactDenied, ente.ContactLeft, ente.UserRevokedContact}))
	if err != nil {
		return false, stacktrace.Propagate(err, "failed to insert/update")
	}
	rowAffected, err := result.RowsAffected()
	if err != nil {
		return false, stacktrace.Propagate(err, "failed to insert/update")
	}
	return rowAffected > 0, nil
}

func (r *Repository) GetActiveContactForUser(ctx context.Context, userID int64) ([]*ContactRow, error) {
	rows, err := r.DB.QueryContext(ctx,
		`SELECT user_id, emergency_contact_id, state, notice_period_in_hrs, encrypted_key 
				FROM emergency_contact WHERE (user_id=$1 or emergency_contact_id=$1) 
				                         and state = ANY($2)`, userID, pq.Array([]ente.ContactState{ente.ContactAccepted, ente.UserInvitedContact}))
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	var contacts []*ContactRow
	for rows.Next() {
		var c ContactRow
		err := rows.Scan(&c.UserID, &c.EmergencyContactID, &c.State, &c.NoticePeriodInHrs, &c.EncryptedKey)
		if err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		contacts = append(contacts, &c)
	}
	if err := rows.Err(); err != nil {
		return nil, stacktrace.Propagate(err, "failed to read emergency contacts")
	}
	return contacts, nil
}

func (r *Repository) GetActiveEmergencyContact(ctx context.Context, userID int64, emergencyContactID int64) (*ContactRow, error) {
	row := r.DB.QueryRowContext(ctx, `SELECT user_id, emergency_contact_id, state, notice_period_in_hrs, encrypted_key
                                                                       				FROM emergency_contact WHERE user_id=$1 and emergency_contact_id=$2 and state = $3`,
		userID, emergencyContactID, ente.ContactAccepted)
	var c ContactRow
	err := row.Scan(&c.UserID, &c.EmergencyContactID, &c.State, &c.NoticePeriodInHrs, &c.EncryptedKey)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &c, nil
}

func (r *Repository) UpdateState(ctx context.Context,
	userID int64,
	emergencyContactID int64,
	newState ente.ContactState) (bool, int64, error) {
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return false, 0, stacktrace.Propagate(err, "failed to start emergency contact update")
	}
	defer tx.Rollback()
	if err = lockOwnerForUpdate(ctx, tx, userID); err != nil {
		return false, 0, err
	}
	allowedPreviousStates := getValidPreviousState(newState)
	var result sql.Result
	if newState == ente.ContactAccepted || newState == ente.UserInvitedContact {
		result, err = tx.ExecContext(ctx, `UPDATE emergency_contact SET state=$1 WHERE user_id=$2 and emergency_contact_id=$3 and state = ANY($4)`,
			newState, userID, emergencyContactID, pq.Array(allowedPreviousStates))
	} else {
		result, err = tx.ExecContext(ctx, `UPDATE emergency_contact SET state=$1, encrypted_key = NULL WHERE user_id=$2 and emergency_contact_id=$3 and state = ANY($4)`,
			newState, userID, emergencyContactID, pq.Array(allowedPreviousStates))
	}
	if err != nil {
		return false, 0, stacktrace.Propagate(err, "")
	}
	count, err := result.RowsAffected()
	if err != nil || count == 0 {
		return false, 0, stacktrace.Propagate(err, "")
	}

	var cancelled int64
	if newState == ente.ContactDenied || newState == ente.ContactLeft || newState == ente.UserRevokedContact {
		status := ente.RecoveryStatusStopped
		if newState == ente.UserRevokedContact {
			status = ente.RecoveryStatusRejected
		}
		result, err = tx.ExecContext(ctx, `UPDATE emergency_recovery SET status=$1 WHERE user_id=$2 AND emergency_contact_id=$3 AND status = ANY($4)`,
			status, userID, emergencyContactID, pq.Array([]ente.RecoveryStatus{ente.RecoveryStatusWaiting, ente.RecoveryStatusReady}))
		if err != nil {
			return false, 0, stacktrace.Propagate(err, "failed to cancel emergency recovery")
		}
		cancelled, err = result.RowsAffected()
		if err != nil {
			return false, 0, stacktrace.Propagate(err, "")
		}
	}
	if err = tx.Commit(); err != nil {
		return false, 0, stacktrace.Propagate(err, "failed to commit emergency contact update")
	}
	return true, cancelled, nil
}

func (r *Repository) UpdateRecoveryNotice(ctx context.Context,
	userID int64,
	emergencyContactID int64,
	noticePeriodInHrs int) error {
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "failed to start recovery notice update")
	}
	defer tx.Rollback()
	if err = lockOwnerForUpdate(ctx, tx, userID); err != nil {
		return err
	}
	contact, err := getContactForUpdate(ctx, tx, userID, emergencyContactID)
	if err != nil && err != sql.ErrNoRows {
		return err
	}
	hasActiveSession, err := hasActiveRecovery(ctx, tx, userID, emergencyContactID)
	if err != nil {
		return err
	}
	if hasActiveSession {
		return stacktrace.Propagate(&ente.ErrActiveRecoverySession, "")
	}
	if contact == nil || contact.State != ente.UserInvitedContact && contact.State != ente.ContactAccepted {
		return ente.NewBadRequestWithMessage("emergency contact not found or not in valid state")
	}
	_, err = tx.ExecContext(ctx, `UPDATE emergency_contact SET notice_period_in_hrs=$1 WHERE user_id=$2 and emergency_contact_id=$3`,
		noticePeriodInHrs, userID, emergencyContactID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to update notice period")
	}
	return stacktrace.Propagate(tx.Commit(), "failed to commit recovery notice update")
}

func lockOwnerForUpdate(ctx context.Context, tx *sql.Tx, userID int64) error {
	var lockedUserID int64
	err := tx.QueryRowContext(ctx, `SELECT user_id FROM users WHERE user_id=$1 FOR NO KEY UPDATE`, userID).Scan(&lockedUserID)
	return stacktrace.Propagate(err, "failed to lock recovery owner")
}

func getContactForUpdate(ctx context.Context, tx *sql.Tx, userID, emergencyContactID int64) (*ContactRow, error) {
	row := tx.QueryRowContext(ctx, `SELECT user_id, emergency_contact_id, state, notice_period_in_hrs, encrypted_key
		FROM emergency_contact WHERE user_id=$1 AND emergency_contact_id=$2 FOR UPDATE`, userID, emergencyContactID)
	var contact ContactRow
	if err := row.Scan(&contact.UserID, &contact.EmergencyContactID, &contact.State, &contact.NoticePeriodInHrs, &contact.EncryptedKey); err != nil {
		if err == sql.ErrNoRows {
			return nil, err
		}
		return nil, stacktrace.Propagate(err, "failed to lock emergency contact")
	}
	return &contact, nil
}

func getValidPreviousState(cs ente.ContactState) []ente.ContactState {
	switch cs {
	case ente.UserInvitedContact:
		return []ente.ContactState{ente.UserRevokedContact, ente.ContactLeft, ente.ContactDenied}
	case ente.ContactAccepted:
		return []ente.ContactState{ente.UserInvitedContact, ente.ContactAccepted}
	case ente.ContactLeft:
		return []ente.ContactState{ente.UserInvitedContact, ente.ContactAccepted}
	case ente.ContactDenied:
		return []ente.ContactState{ente.UserInvitedContact}
	case ente.UserRevokedContact:
		return []ente.ContactState{ente.UserInvitedContact, ente.ContactAccepted}

	}
	panic("invalid state")
}
