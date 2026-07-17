package controller

import (
	"database/sql"
	"errors"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/crypto"
	emailUtil "github.com/ente/museum/pkg/utils/email"
	"github.com/ente/stacktrace"
)

type userLookupRepository interface {
	GetUserIDWithEmailUnrestricted(email string) (int64, error)
}

type potentialAbuseNotifier interface {
	NotifyPotentialAbuse(message string)
}

// UserLookup applies the shared authenticated email-discovery policy.
type UserLookup interface {
	LookupUserID(requesterUserID int64, email string) (int64, error)
}

// UserLookupController limits email discovery before querying the user repository.
type UserLookupController struct {
	userRepo    userLookupRepository
	notifier    potentialAbuseNotifier
	hashingKey  []byte
	lookupLimit *userLookupLimiter
}

func NewUserLookupController(userRepo *repo.UserRepository, notifier potentialAbuseNotifier) *UserLookupController {
	return &UserLookupController{
		userRepo:    userRepo,
		notifier:    notifier,
		hashingKey:  userRepo.HashingKey,
		lookupLimit: newUserLookupLimiter(defaultUserLookupLimits()),
	}
}

func (c *UserLookupController) LookupUserID(requesterUserID int64, email string) (int64, error) {
	if requesterUserID <= 0 {
		return -1, stacktrace.Propagate(ente.ErrAuthenticationRequired, "")
	}

	normalizedEmail := emailUtil.NormalizeEmail(email)
	targetHash, err := crypto.GetHash(normalizedEmail, c.hashingKey)
	if err != nil {
		return -1, stacktrace.Propagate(err, "")
	}

	attempt, decision := c.lookupLimit.Start(requesterUserID, targetHash)
	if !decision.allowed {
		return -1, c.limitExceeded(decision)
	}

	userID, err := c.userRepo.GetUserIDWithEmailUnrestricted(normalizedEmail)
	decision = c.lookupLimit.Finish(attempt, errors.Is(err, sql.ErrNoRows))
	if !decision.allowed {
		return -1, c.limitExceeded(decision)
	}
	return userID, err
}

func (c *UserLookupController) limitExceeded(decision userLookupLimitDecision) error {
	if decision.notify && c.notifier != nil {
		go c.notifier.NotifyPotentialAbuse(
			"user lookup limit exceeded (" + string(decision.window) + " window)",
		)
	}
	return stacktrace.Propagate(ente.ErrTooManyBadRequest, "too many user lookups")
}
