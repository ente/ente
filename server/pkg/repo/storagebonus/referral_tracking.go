package storagebonus

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/ente/storagebonus"
	"github.com/ente/stacktrace"
	"github.com/sirupsen/logrus"
)

func (r *Repository) TrackReferralAndInviteeBonus(ctx context.Context, invitee, codeOwnerId int64, planType storagebonus.PlanType) error {
	if invitee == codeOwnerId {
		return stacktrace.Propagate(ente.ErrBadRequest, "invitee %d and invitor %d are same", invitee, codeOwnerId)
	}
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "failed to begin txn for invitee bonus tracking")
	}
	defer func(tx *sql.Tx) {
		err := tx.Rollback()
		if err != nil && err.Error() != "sql: transaction has already been committed or rolled back" {
			logrus.WithError(err).Error("failed to rollback txn for invitee bonus tracking")
		}
	}(tx)
	_, err = tx.ExecContext(ctx, "INSERT INTO referral_tracking (invitee_id, invitor_id, plan_type) VALUES ($1, $2, $3)", invitee, codeOwnerId, planType)
	if err != nil {
		return stacktrace.Propagate(err, "failed to insert storagebonus tracking entry for invitee %d, invitor %d and planType %s", invitee, codeOwnerId, planType)
	}
	bonusType := storagebonus.SignUp
	bonusID := fmt.Sprintf("%s-%d", bonusType, invitee)
	bonusValue := planType.SignUpInviteeBonus()
	_, err = tx.ExecContext(ctx, "INSERT INTO storage_bonus (bonus_id,type, user_id, storage) VALUES ($1, $2, $3, $4)", bonusID, bonusType, invitee, bonusValue)
	if err != nil {
		return stacktrace.Propagate(err, "failed to add storage surplus for user %d", invitee)
	}

	err = tx.Commit()
	if err != nil {
		return stacktrace.Propagate(err, "failed to commit txn for invitee bonus tracking")
	}
	return nil
}

func (r *Repository) TrackUpgradeAndInvitorBonus(ctx context.Context, invitee, invitor int64, planType storagebonus.PlanType) error {
	if invitee == invitor {
		return stacktrace.Propagate(ente.ErrBadRequest, "invitee %d and invitor %d are same", invitee, invitor)
	}
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "failed to begin txn for storagebonus tracking")
	}
	defer func(tx *sql.Tx) {
		err := tx.Rollback()
		if err != nil {
			logrus.WithError(err).Error("failed to rollback txn for storagebonus tracking")
		}
	}(tx)
	result, err := tx.ExecContext(ctx, "UPDATE referral_tracking SET invitee_on_paid_plan = true WHERE invitee_id = $1 AND invitor_id = $2 and invitee_on_paid_plan = FALSE", invitee, invitor)
	if err != nil {
		return stacktrace.Propagate(err, "failed to update tracking entry for invitee %d, invitor %d", invitee, invitor)
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if affected == 0 {
		return stacktrace.Propagate(err, "failed to update tracking entry for invitee %d, invitor %d", invitee, invitor)
	}
	bonusType := storagebonus.Referral
	bonusID := fmt.Sprintf("%s-upgrade-%d", bonusType, invitee)
	bonusValue := planType.InvitorBonusOnInviteeUpgrade()

	_, err = tx.ExecContext(ctx, "INSERT INTO storage_bonus (bonus_id, type, user_id, storage) VALUES ($1, $2, $3, $4)", bonusID, bonusType, invitor, bonusValue)
	if err != nil {
		return stacktrace.Propagate(err, "failed to add storage surplus for user %d", invitor)
	}

	err = tx.Commit()
	if err != nil {
		return stacktrace.Propagate(err, "failed to commit txn for storagebonus tracking")
	}
	return nil
}

func (r *Repository) GetUserReferralStats(ctx context.Context, userID int64) ([]storagebonus.UserReferralPlanStat, error) {
	rows, err := r.DB.QueryContext(ctx, "SELECT plan_type, COUNT(*), SUM(CASE WHEN invitee_on_paid_plan THEN 1 ELSE 0 END) FROM referral_tracking WHERE invitor_id = $1 GROUP BY plan_type", userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to get referral counts for user %d", userID)
	}
	defer rows.Close()
	var counts = make([]storagebonus.UserReferralPlanStat, 0)
	for rows.Next() {
		var count storagebonus.UserReferralPlanStat
		err := rows.Scan(&count.PlanType, &count.TotalCount, &count.UpgradedCount)
		if err != nil {
			return nil, stacktrace.Propagate(err, "failed to scan referral count for user %d", userID)
		}
		counts = append(counts, count)
	}
	return counts, nil
}

func (r *Repository) HasAppliedReferral(ctx context.Context, invitee int64) (bool, error) {
	var count int
	err := r.DB.QueryRowContext(ctx, "SELECT COUNT(*) FROM referral_tracking WHERE invitee_id = $1", invitee).Scan(&count)
	if err != nil {
		return false, stacktrace.Propagate(err, "failed to check if invitee %d has joined", invitee)
	}
	return count > 0, nil
}

func (r *Repository) GetReferredForUpgradeBonus(ctx context.Context) ([]storagebonus.Tracking, error) {
	rows, err := r.DB.QueryContext(ctx, "SELECT invitee_id, invitor_id, plan_type FROM referral_tracking WHERE invitee_on_paid_plan = FALSE AND invitee_id IN (SELECT user_id FROM subscriptions WHERE product_id != $1 and expiry_time > now_utc_micro_seconds())", ente.FreePlanProductID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to get list of result")
	}
	defer func(rows *sql.Rows) {
		err := rows.Close()
		if err != nil {
			logrus.WithError(err).Error("failed to close rows")
		}
	}(rows)
	var result = make([]storagebonus.Tracking, 0)
	for rows.Next() {
		var tracking storagebonus.Tracking
		err := rows.Scan(&tracking.Invitee, &tracking.Invitor, &tracking.PlanType)
		if err != nil {
			return nil, stacktrace.Propagate(err, "failed to scan tracking")
		}
		result = append(result, tracking)
	}
	return result, nil
}

func (r *Repository) GetReferredForDowngradePenalty(ctx context.Context) ([]storagebonus.Tracking, error) {
	rows, err := r.DB.QueryContext(ctx, "SELECT invitee_id, invitor_id, plan_type FROM referral_tracking WHERE invitee_on_paid_plan = TRUE AND invitee_id IN (SELECT user_id FROM subscriptions WHERE expiry_time < now_utc_micro_seconds())")
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to get list of result")
	}
	defer func(rows *sql.Rows) {
		err := rows.Close()
		if err != nil {
			logrus.WithError(err).Error("failed to close rows")
		}
	}(rows)
	var result = make([]storagebonus.Tracking, 0)
	for rows.Next() {
		var tracking storagebonus.Tracking
		err := rows.Scan(&tracking.Invitee, &tracking.Invitor, &tracking.PlanType)
		if err != nil {
			return nil, stacktrace.Propagate(err, "failed to scan tracking")
		}
		result = append(result, tracking)
	}
	return result, nil
}
