package storagebonus

import (
	"context"
	"database/sql"
	"fmt"
	"github.com/ente/museum/ente"
	"net/http"

	entity "github.com/ente/museum/ente/storagebonus"
	"github.com/ente/stacktrace"
)

const (
	MaxReferralCodeChangeAllowed = 3
)

// Add context as first parameter in all methods in this file

// GetCode returns the storagebonus code for the given userID
func (r *Repository) GetCode(ctx context.Context, userID int64) (*string, error) {
	var code *string
	err := r.DB.QueryRowContext(ctx, "SELECT code FROM referral_codes WHERE user_id = $1 and is_active = TRUE", userID).Scan(&code)
	return code, stacktrace.Propagate(err, "failed to get storagebonus code for user %d", userID)
}

// InsertCode for the given userID
func (r *Repository) InsertCode(ctx context.Context, userID int64, code string) error {
	_, err := r.DB.ExecContext(ctx, "INSERT INTO referral_codes (user_id, code) VALUES ($1, $2)", userID, code)
	if err != nil {
		if err.Error() == "pq: duplicate key value violates unique constraint \"referral_codes_pkey\"" {
			return stacktrace.Propagate(entity.CodeAlreadyExistsErr, "duplicate storagebonus code for user %d", userID)
		}
		return stacktrace.Propagate(err, "failed to insert storagebonus code for user %d", userID)
	}
	return nil
}

// AddNewCode and mark the old one as inactive for a given userID.
// Note: This method is not being used in the initial MVP as we don't allow user to change the storagebonus
// code
func (r *Repository) AddNewCode(ctx context.Context, userID int64, code string, isAdminEdit bool) error {
	// check current referral code count
	var count int
	err := r.DB.QueryRowContext(ctx, "SELECT COALESCE(COUNT(*),0) FROM referral_codes WHERE user_id = $1", userID).Scan(&count)
	if err != nil {
		return stacktrace.Propagate(err, "failed to get storagebonus code count for user %d", userID)
	}
	if !isAdminEdit && count > MaxReferralCodeChangeAllowed {
		return stacktrace.Propagate(&ente.ApiError{
			Code:           "REFERRAL_CHANGE_LIMIT_REACHED",
			Message:        fmt.Sprintf("max referral code change limit %d reached", MaxReferralCodeChangeAllowed),
			HttpStatusCode: http.StatusTooManyRequests,
		}, "max referral code change limit reached for user %d", userID)
	}
	// check if code already exists
	var existCount int
	err = r.DB.QueryRowContext(ctx, "SELECT COALESCE(COUNT(*),0) FROM referral_codes WHERE code = $1", code).Scan(&existCount)
	if err != nil {
		return stacktrace.Propagate(err, "failed to check if code already exists for user %d", userID)
	}
	if existCount > 0 {
		return stacktrace.Propagate(entity.CodeAlreadyExistsErr, "storagebonus code %s already exists", code)
	}
	_, err = r.DB.ExecContext(ctx, "UPDATE referral_codes SET is_active = FALSE WHERE user_id = $1", userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to update remove existing code code for user %d", userID)
	}
	return r.InsertCode(ctx, userID, code)
}

// GetCodeChangeCount returns the number of times the user has changed their referral code.
// A count of 1 means no changes (only the initial code exists).
func (r *Repository) GetCodeChangeCount(ctx context.Context, userID int64) (int, error) {
	var count int
	err := r.DB.QueryRowContext(ctx, "SELECT COALESCE(COUNT(*),0) FROM referral_codes WHERE user_id = $1", userID).Scan(&count)
	if err != nil {
		return 0, stacktrace.Propagate(err, "failed to get referral code count for user %d", userID)
	}
	return count, nil
}

// GetUserIDByCode returns the userID for the given storagebonus code. The method will also return the userID
// if the code is inactive.
func (r *Repository) GetUserIDByCode(ctx context.Context, code string) (*int64, error) {
	var userID int64
	err := r.DB.QueryRowContext(ctx, "SELECT user_id FROM referral_codes WHERE code = $1", code).Scan(&userID)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, stacktrace.Propagate(entity.InvalidCodeErr, "code %s not found", code)
		}
		return nil, err
	}
	return &userID, nil
}
