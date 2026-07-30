package repo

import (
	"context"
	"database/sql"
	"errors"

	"github.com/ente/stacktrace"
	"github.com/lib/pq"
)

// UsageRepository defines the methods tracking and fetching usage related date
type UsageRepository struct {
	DB       *sql.DB
	UserRepo *UserRepository
}

type LockerUsage struct {
	TotalFileCount int64
	TotalUsage     int64
	Users          []UserLockerUsage
}

type UserLockerUsage struct {
	UserID    int64
	FileCount int64
	Usage     int64
}

type StorageWarningCandidate struct {
	RecipientID  int64
	IsFamilyPlan bool
}

// GetUsage  gets the Storage usage of a user
func (repo *UsageRepository) GetUsage(userID int64) (int64, error) {
	row := repo.DB.QueryRow(`SELECT storage_consumed FROM usage WHERE user_id = $1`,
		userID)
	var usage int64
	err := row.Scan(&usage)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, nil
	}
	return usage, stacktrace.Propagate(err, "")
}

// Create inserts a new entry for the given user. If entry already exists, it doesn't nothing
func (repo *UsageRepository) Create(userID int64) error {
	_, err := repo.DB.Exec(`INSERT INTO usage(user_id, storage_consumed) VALUES ($1,$2) ON CONFLICT DO NOTHING;`,
		userID, //$1 user_id
		0,      // $2 initial value for storage consumed
	)
	return stacktrace.Propagate(err, "failed to insert/update")
}

// GetCombinedUsage  gets the sum of Storage usage of the list of userIDS
func (repo *UsageRepository) GetCombinedUsage(ctx context.Context, userIDs []int64) (int64, error) {
	row := repo.DB.QueryRowContext(ctx, `SELECT coalesce(sum(storage_consumed),0) FROM usage WHERE user_id = ANY($1)`,
		pq.Array(userIDs))
	var totalUsage int64
	err := row.Scan(&totalUsage)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, nil
	}
	return totalUsage, stacktrace.Propagate(err, "")
}

func (repo *UsageRepository) GetStorageWarningCandidates(ctx context.Context, usageThreshold int64) ([]StorageWarningCandidate, error) {
	// Intentionally use per-member usage when selecting family candidates. The
	// mailer evaluates aggregate family usage later, but candidate selection is
	// deliberately narrower so families are only pulled into the workflow when a
	// specific member crosses the threshold.
	rows, err := repo.DB.QueryContext(ctx, `
		SELECT
			COALESCE(u.family_admin_id, u.user_id) AS recipient_id,
			u.family_admin_id IS NOT NULL AS is_family_plan
		FROM users u
		INNER JOIN usage us
			ON us.user_id = u.user_id
		WHERE
			us.storage_consumed > $1
			AND u.encrypted_email IS NOT NULL
		ORDER BY recipient_id
	`, usageThreshold)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to fetch storage warning candidates")
	}
	defer rows.Close()

	candidates := make([]StorageWarningCandidate, 0)
	seenRecipients := make(map[int64]struct{})
	for rows.Next() {
		var candidate StorageWarningCandidate
		if err := rows.Scan(&candidate.RecipientID, &candidate.IsFamilyPlan); err != nil {
			return nil, stacktrace.Propagate(err, "failed to scan storage warning candidate")
		}
		if _, ok := seenRecipients[candidate.RecipientID]; ok {
			continue
		}
		seenRecipients[candidate.RecipientID] = struct{}{}
		candidates = append(candidates, candidate)
	}
	if err := rows.Err(); err != nil {
		return nil, stacktrace.Propagate(err, "failed to iterate storage warning candidates")
	}
	return candidates, nil
}

func (repo *UsageRepository) GetLockerUsage(ctx context.Context, userIDs []int64) (*LockerUsage, error) {
	usage := &LockerUsage{}
	if len(userIDs) == 0 {
		return usage, nil
	}

	// Initialize map with all requested users
	userMap := make(map[int64]*UserLockerUsage)
	for _, userID := range userIDs {
		userMap[userID] = &UserLockerUsage{
			UserID:    userID,
			FileCount: 0,
			Usage:     0,
		}
	}

	// Query 1: Get file counts (non-deleted only)
	countQuery := `
      SELECT 
         c.owner_id,
         COUNT(DISTINCT cf.file_id) AS file_count
      FROM collections c
      JOIN collection_files cf ON c.collection_id = cf.collection_id
      WHERE c.app = 'locker'
         AND c.owner_id = ANY($1)
         AND cf.f_owner_id = c.owner_id
         AND cf.is_deleted = false
      GROUP BY c.owner_id;
   `

	// Query 2: Get total sizes (all files)
	sizeQuery := `
      SELECT 
         unique_files.owner_id,
         COALESCE(SUM(ok.size), 0) AS total_size
      FROM (
         SELECT DISTINCT c.owner_id, cf.file_id
         FROM collections c
         JOIN collection_files cf ON c.collection_id = cf.collection_id
         WHERE c.app = 'locker'
            AND c.owner_id = ANY($1)
            AND cf.f_owner_id = c.owner_id
      ) AS unique_files
      LEFT JOIN object_keys ok ON ok.file_id = unique_files.file_id AND ok.is_deleted = false
      GROUP BY unique_files.owner_id;
   `

	// Get counts
	rows, err := repo.DB.QueryContext(ctx, countQuery, pq.Array(userIDs))
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()

	for rows.Next() {
		var ownerID, fileCount int64
		if scanErr := rows.Scan(&ownerID, &fileCount); scanErr != nil {
			return nil, stacktrace.Propagate(scanErr, "")
		}
		if user, exists := userMap[ownerID]; exists {
			user.FileCount = fileCount
		}
	}
	rows.Close()

	// Get sizes
	rows, err = repo.DB.QueryContext(ctx, sizeQuery, pq.Array(userIDs))
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()

	for rows.Next() {
		var ownerID, totalSize int64
		if scanErr := rows.Scan(&ownerID, &totalSize); scanErr != nil {
			return nil, stacktrace.Propagate(scanErr, "")
		}
		if user, exists := userMap[ownerID]; exists {
			user.Usage = totalSize
		}
	}

	// Build result - now includes ALL requested users
	for _, userID := range userIDs {
		user := userMap[userID]
		usage.Users = append(usage.Users, *user)
		usage.TotalFileCount += user.FileCount
		usage.TotalUsage += user.Usage
	}

	if err := rows.Err(); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}

	return usage, nil
}

// StorageForFamilyAdmin calculates the total storage consumed by the family for a given adminID
func (repo *UsageRepository) StorageForFamilyAdmin(adminID int64) (int64, error) {
	query := `
		SELECT COALESCE(SUM(storage_consumed), 0)
		FROM users
		LEFT JOIN families ON users.family_admin_id = families.admin_id AND families.status IN ('SELF', 'ACCEPTED')
		LEFT JOIN usage ON families.member_id = usage.user_id
		WHERE users.user_id = $1
	`
	var totalStorage int64
	err := repo.DB.QueryRow(query, adminID).Scan(&totalStorage)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, nil
	}
	return totalStorage, stacktrace.Propagate(err, "")
}
