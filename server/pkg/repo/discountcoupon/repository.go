package discountcoupon

import (
	"context"
	"database/sql"
	"fmt"
	"github.com/ente/stacktrace"
	"strings"
)

type Repository struct {
	DB *sql.DB
}

type DiscountCoupon struct {
	ProviderName    string
	Code            string
	ClaimedByUserID *int64
	ClaimedAt       *int64
	SentCount       int
	CreatedAt       int64
	UpdatedAt       int64
}

func (r *Repository) AddCoupons(ctx context.Context, providerName string, codes []string) error {
	query := `INSERT INTO discount_coupons (provider_name, code) VALUES `
	var values []interface{}
	var placeholders []string

	for i, code := range codes {
		placeholders = append(placeholders,
			fmt.Sprintf("($%d, $%d)", i*2+1, i*2+2))
		values = append(values, providerName, code)
	}

	query += strings.Join(placeholders, ", ") +
		" ON CONFLICT (provider_name, code) DO NOTHING"

	_, err := r.DB.ExecContext(ctx, query, values...)
	if err != nil {
		return stacktrace.Propagate(err,
			"failed to insert %d discount coupons for provider %s",
			len(codes), providerName)
	}

	return nil
}

func (r *Repository) GetUnclaimedCoupon(ctx context.Context, providerName string) (*DiscountCoupon, error) {
	query := `SELECT provider_name, code, claimed_by_user_id, claimed_at, sent_count, created_at, updated_at 
	          FROM discount_coupons 
	          WHERE provider_name = $1 AND claimed_by_user_id IS NULL 
	          ORDER BY created_at ASC 
	          LIMIT 1`

	var coupon DiscountCoupon
	row := r.DB.QueryRowContext(ctx, query, providerName)
	err := row.Scan(&coupon.ProviderName, &coupon.Code, &coupon.ClaimedByUserID, &coupon.ClaimedAt, &coupon.SentCount, &coupon.CreatedAt, &coupon.UpdatedAt)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, stacktrace.Propagate(err, "failed to get unclaimed coupon")
	}

	return &coupon, nil
}

func (r *Repository) ClaimCoupon(ctx context.Context, providerName, code string, userID int64) error {
	query := `UPDATE discount_coupons 
	          SET claimed_by_user_id = $1, claimed_at = now_utc_micro_seconds(), sent_count = 1
	          WHERE provider_name = $2 AND code = $3 AND claimed_by_user_id IS NULL`

	result, err := r.DB.ExecContext(ctx, query, userID, providerName, code)
	if err != nil {
		return stacktrace.Propagate(err, "failed to claim coupon")
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return stacktrace.Propagate(err, "failed to get affected rows")
	}

	if rowsAffected == 0 {
		return stacktrace.NewError("coupon not found or already claimed")
	}

	return nil
}

func (r *Repository) GetClaimedCoupon(ctx context.Context, providerName string, userID int64) (*DiscountCoupon, error) {
	query := `SELECT provider_name, code, claimed_by_user_id, claimed_at, sent_count, created_at, updated_at 
	          FROM discount_coupons 
	          WHERE provider_name = $1 AND claimed_by_user_id = $2`

	var coupon DiscountCoupon
	row := r.DB.QueryRowContext(ctx, query, providerName, userID)
	err := row.Scan(&coupon.ProviderName, &coupon.Code, &coupon.ClaimedByUserID, &coupon.ClaimedAt, &coupon.SentCount, &coupon.CreatedAt, &coupon.UpdatedAt)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, stacktrace.Propagate(err, "failed to get claimed coupon")
	}

	return &coupon, nil
}

func (r *Repository) IncrementSentCount(ctx context.Context, providerName, code string) error {
	query := `UPDATE discount_coupons 
	          SET sent_count = sent_count + 1 
	          WHERE provider_name = $1 AND code = $2`

	_, err := r.DB.ExecContext(ctx, query, providerName, code)
	if err != nil {
		return stacktrace.Propagate(err, "failed to increment sent count")
	}

	return nil
}

func (r *Repository) HasUnclaimedCoupons(ctx context.Context, providerName string) (bool, error) {
	query := `SELECT COUNT(*) FROM discount_coupons WHERE provider_name = $1 AND claimed_by_user_id IS NULL`

	var count int
	row := r.DB.QueryRowContext(ctx, query, providerName)
	err := row.Scan(&count)
	if err != nil {
		return false, stacktrace.Propagate(err, "failed to count unclaimed coupons")
	}

	return count > 0, nil
}
