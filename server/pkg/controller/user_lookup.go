package controller

import (
	"database/sql"
	"errors"
	"strconv"

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

type UserLookup interface {
	LookupUserID(requesterUserID int64, email string) (int64, error)
	VerifyUserID(requesterUserID int64, email string, expectedUserID int64) error
}

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
	return c.lookupUserID(requesterUserID, email, nil)
}

func (c *UserLookupController) VerifyUserID(
	requesterUserID int64,
	email string,
	expectedUserID int64,
) error {
	_, err := c.lookupUserID(requesterUserID, email, &expectedUserID)
	return err
}

func (c *UserLookupController) lookupUserID(
	requesterUserID int64,
	email string,
	expectedUserID *int64,
) (int64, error) {
	if requesterUserID <= 0 {
		return -1, stacktrace.Propagate(ente.ErrAuthenticationRequired, "")
	}
	if expectedUserID != nil && *expectedUserID <= 0 {
		return -1, stacktrace.Propagate(ente.ErrBadRequest, "invalid expected user ID")
	}

	normalizedEmail := emailUtil.NormalizeEmail(email)
	limitTarget := normalizedEmail
	if expectedUserID != nil {
		limitTarget = "email-user-id\x00" + normalizedEmail + "\x00" + strconv.FormatInt(*expectedUserID, 10)
	}
	targetHash, err := crypto.GetHash(limitTarget, c.hashingKey)
	if err != nil {
		return -1, stacktrace.Propagate(err, "")
	}

	attempt, decision := c.lookupLimit.Start(requesterUserID, targetHash)
	if !decision.allowed {
		return -1, c.limitExceeded(decision)
	}

	userID, err := c.userRepo.GetUserIDWithEmailUnrestricted(normalizedEmail)
	identityMismatch := errors.Is(err, sql.ErrNoRows) ||
		(err == nil && expectedUserID != nil && userID != *expectedUserID)
	decision = c.lookupLimit.Finish(attempt, identityMismatch)
	if !decision.allowed {
		return -1, c.limitExceeded(decision)
	}
	if expectedUserID != nil && identityMismatch {
		return -1, stacktrace.Propagate(ente.ErrRecipientIdentityMismatch, "")
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
