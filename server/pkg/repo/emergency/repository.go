package emergency

import (
	"context"
	"database/sql"
	"github.com/ente/museum/ente"
	"github.com/ente/stacktrace"
	"github.com/lib/pq"
)

// Repository defines the methods for managing emergency contacts and recovery process.
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

// HasActiveLegacyContact returns true when the user has at least one accepted
// legacy contact configured on their account.
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
		userID, // $1 user_id
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

// GetActiveContactForUser returns all the contacts for a user that are in state accepted or invited
// and also returns all the contacts that have added the user as emergency contact
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
	return contacts, nil
}

// GetActiveEmergencyContact for a given userID and emergencyContactID in active state
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

// UpdateState will return true if the state was updated, false if the state was not updated
func (r *Repository) UpdateState(ctx context.Context,
	userID int64,
	emergencyContactID int64,
	newState ente.ContactState) (bool, error) {
	allowedPreviousStates := getValidPreviousState(newState)
	var res sql.Result
	var err error
	if newState == ente.ContactAccepted || newState == ente.UserInvitedContact {
		res, err = r.DB.ExecContext(ctx, `UPDATE emergency_contact SET state=$1 WHERE user_id=$2 and emergency_contact_id=$3 and state = ANY($4)`,
			newState, userID, emergencyContactID, pq.Array(allowedPreviousStates))
	} else {
		res, err = r.DB.ExecContext(ctx, `UPDATE emergency_contact SET state=$1, encrypted_key = NULL WHERE user_id=$2 and emergency_contact_id=$3 and state = ANY($4)`,
			newState, userID, emergencyContactID, pq.Array(allowedPreviousStates))
	}
	if err != nil {
		return false, stacktrace.Propagate(err, "")
	}
	count, err2 := res.RowsAffected()
	if count > 1 {
		panic("invalid state, only one row should be updated")
	}
	return count > 0, stacktrace.Propagate(err2, "")
}

// UpdateRecoveryNotice updates the notice period for an emergency contact
// Only allows update if the contact state is INVITED or ACCEPTED
func (r *Repository) UpdateRecoveryNotice(ctx context.Context,
	userID int64,
	emergencyContactID int64,
	noticePeriodInHrs int) error {
	res, err := r.DB.ExecContext(ctx, `UPDATE emergency_contact SET notice_period_in_hrs=$1 WHERE user_id=$2 and emergency_contact_id=$3 and state = ANY($4)`,
		noticePeriodInHrs, userID, emergencyContactID, pq.Array([]ente.ContactState{ente.UserInvitedContact, ente.ContactAccepted}))
	if err != nil {
		return stacktrace.Propagate(err, "failed to update notice period")
	}
	count, err := res.RowsAffected()
	if err != nil {
		return stacktrace.Propagate(err, "failed to get rows affected")
	}
	if count == 0 {
		return ente.NewBadRequestWithMessage("emergency contact not found or not in valid state")
	}
	return nil
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
