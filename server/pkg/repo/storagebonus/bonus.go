package storagebonus

import (
	"context"
	"github.com/lib/pq"

	"github.com/ente/museum/ente/storagebonus"
	"github.com/ente/stacktrace"
)

// GetStorageBonuses returns the storage surplus for the given userID
func (r *Repository) GetStorageBonuses(ctx context.Context, userID int64) ([]storagebonus.StorageBonus, error) {
	var storageSurplus = make([]storagebonus.StorageBonus, 0)
	rows, err := r.DB.QueryContext(ctx, "SELECT user_id,storage,type, created_at, updated_at, valid_till, is_revoked, revoke_reason FROM storage_bonus WHERE user_id = $1", userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to get storage surplus for user %d", userID)
	}
	defer rows.Close()
	for rows.Next() {
		var ss storagebonus.StorageBonus
		err := rows.Scan(&ss.UserID, &ss.Storage, &ss.Type, &ss.CreatedAt, &ss.UpdatedAt, &ss.ValidTill, &ss.IsRevoked, &ss.RevokeReason)
		if err != nil {
			return nil, stacktrace.Propagate(err, "failed to scan storage surplus for user %d", userID)
		}
		storageSurplus = append(storageSurplus, ss)
	}
	return storageSurplus, nil
}

func (r *Repository) GetActiveStorageBonuses(ctx context.Context, userID int64) (*storagebonus.ActiveStorageBonus, error) {
	var bonuses = make([]storagebonus.StorageBonus, 0)
	rows, err := r.DB.QueryContext(ctx, "SELECT user_id,storage,type, created_at, updated_at, valid_till, is_revoked, revoke_reason FROM storage_bonus WHERE user_id = $1 AND is_revoked = false AND (valid_till = 0 OR valid_till > now_utc_micro_seconds())", userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to get active storage surplus for user %d", userID)
	}
	defer rows.Close()
	for rows.Next() {
		var ss storagebonus.StorageBonus
		err := rows.Scan(&ss.UserID, &ss.Storage, &ss.Type, &ss.CreatedAt, &ss.UpdatedAt, &ss.ValidTill, &ss.IsRevoked, &ss.RevokeReason)
		if err != nil {
			return nil, stacktrace.Propagate(err, "failed to scan active storage surplus for user %d", userID)
		}
		bonuses = append(bonuses, ss)
	}
	return &storagebonus.ActiveStorageBonus{StorageBonuses: bonuses}, nil
}

// ActiveStorageSurplusOfType returns the total storage surplus for a given userID. Surplus is considered as active when
// it is not revoked and not expired aka validTill is 0 or greater than now_utc_micro_seconds()
func (r *Repository) ActiveStorageSurplusOfType(ctx context.Context, userID int64, bonusTypes []storagebonus.BonusType) (*int64, error) {
	var total *int64
	rows, err := r.DB.QueryContext(ctx, "SELECT coalesce(sum(storage),0) FROM storage_bonus "+
		"WHERE user_id = $1 AND type = ANY($2) AND is_revoked = false AND (valid_till = 0 OR valid_till > now_utc_micro_seconds())", userID, pq.Array(bonusTypes))
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to get active storage surplus for users %d", userID)
	}
	defer rows.Close()
	for rows.Next() {
		err := rows.Scan(&total)
		if err != nil {
			return nil, stacktrace.Propagate(err, "failed to scan active storage surplus for users %d", userID)
		}
	}
	return total, nil
}

// GetPaidAddonSurplusStorage returns the total storage surplus for a given userID. Surplus is considered as active when
// it is not revoked and not expired aka validTill is 0 or greater than now_utc_micro_seconds()
func (r *Repository) GetPaidAddonSurplusStorage(ctx context.Context, userID int64) (*int64, error) {
	return r.ActiveStorageSurplusOfType(ctx, userID, storagebonus.PaidAddOnTypes)
}

// GetAllUsersSurplusBonus returns two maps userID to referralBonus & addonBonus
func (r *Repository) GetAllUsersSurplusBonus(ctx context.Context) (refBonus map[int64]int64, addonBonus map[int64]int64, err error) {
	var userID, bonus int64
	var bonusType storagebonus.BonusType
	refBonus = make(map[int64]int64)
	addonBonus = make(map[int64]int64)
	rows, err := r.DB.QueryContext(ctx, "SELECT user_id, type, coalesce(sum(storage),0) FROM storage_bonus WHERE is_revoked = false AND (valid_till = 0 OR valid_till > now_utc_micro_seconds()) GROUP BY user_id, type")
	if err != nil {
		return nil, nil, stacktrace.Propagate(err, "failed to get active storage surplus for users")
	}
	defer rows.Close()
	for rows.Next() {
		err := rows.Scan(&userID, &bonusType, &bonus)
		if err != nil {
			return nil, nil, stacktrace.Propagate(err, "failed to scan active storage surplus for users")
		}
		if _, ok := refBonus[userID]; !ok {
			refBonus[userID] = 0
		}
		if _, ok := addonBonus[userID]; !ok {
			addonBonus[userID] = 0
		}
		if bonusType.RestrictToDoublingStorage() {
			refBonus[userID] += bonus
		} else {
			addonBonus[userID] += bonus
		}
	}
	return refBonus, addonBonus, nil
}
