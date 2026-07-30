package controller

import (
	"bytes"
	"database/sql"
	"errors"
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/ente/museum/ente"
)

type userLookupRepositoryStub struct {
	mu     sync.Mutex
	emails []string
	userID int64
	err    error
}

func (r *userLookupRepositoryStub) GetUserIDWithEmailUnrestricted(email string) (int64, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.emails = append(r.emails, email)
	return r.userID, r.err
}

func (r *userLookupRepositoryStub) callCount() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return len(r.emails)
}

func (r *userLookupRepositoryStub) setResult(userID int64, err error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.userID = userID
	r.err = err
}

type userLookupNotifierStub struct {
	messages chan string
}

func (n *userLookupNotifierStub) NotifyPotentialAbuse(message string) {
	n.messages <- message
}

func newUserLookupControllerForTest(
	repository userLookupRepository,
	notifier potentialAbuseNotifier,
	now func() time.Time,
) *UserLookupController {
	return &UserLookupController{
		userRepo:    repository,
		notifier:    notifier,
		hashingKey:  bytes.Repeat([]byte{1}, 32),
		lookupLimit: newUserLookupLimiterWithClock(defaultUserLookupLimits(), now),
	}
}

func TestUserLookupNormalizesAndAlwaysQueriesRepository(t *testing.T) {
	now := time.Unix(1000, 0)
	repository := &userLookupRepositoryStub{userID: 42}
	controller := newUserLookupControllerForTest(repository, nil, func() time.Time { return now })

	for i := 0; i < 100; i++ {
		userID, err := controller.LookupUserID(1, "  Person@Example.COM ")
		if err != nil {
			t.Fatalf("lookup %d returned error: %v", i, err)
		}
		if userID != 42 {
			t.Fatalf("lookup %d user ID = %d, want 42", i, userID)
		}
	}

	if got := repository.callCount(); got != 100 {
		t.Fatalf("repository calls = %d, want 100", got)
	}
	for _, email := range repository.emails {
		if email != "person@example.com" {
			t.Fatalf("repository email = %q, want normalized email", email)
		}
	}

	for targetHash := range controller.lookupLimit.actors[1].day.targets {
		if targetHash == "person@example.com" {
			t.Fatal("limiter stored a plaintext email")
		}
	}
}

func TestUserLookupRejectsUnauthenticatedRequesterBeforeRepository(t *testing.T) {
	now := time.Unix(1000, 0)
	repository := &userLookupRepositoryStub{}
	controller := newUserLookupControllerForTest(repository, nil, func() time.Time { return now })

	_, err := controller.LookupUserID(0, "person@example.com")
	if !errors.Is(err, ente.ErrAuthenticationRequired) {
		t.Fatalf("error = %v, want %v", err, ente.ErrAuthenticationRequired)
	}
	if got := repository.callCount(); got != 0 {
		t.Fatalf("repository calls = %d, want 0", got)
	}
}

func TestUserLookupDeniesBeforeRepositoryAndNotifiesWithoutTarget(t *testing.T) {
	now := time.Unix(1000, 0)
	repository := &userLookupRepositoryStub{userID: 42}
	notifier := &userLookupNotifierStub{messages: make(chan string, 1)}
	controller := newUserLookupControllerForTest(repository, notifier, func() time.Time { return now })

	for i := 0; i < defaultUserLookupDayLimit; i++ {
		if _, err := controller.LookupUserID(7, fmt.Sprintf("target-%d@example.com", i)); err != nil {
			t.Fatalf("seed lookup %d returned error: %v", i, err)
		}
	}
	now = now.Add(userLookupMinuteWindowDuration)
	_, err := controller.LookupUserID(7, "blocked@example.com")
	if !errors.Is(err, ente.ErrTooManyBadRequest) {
		t.Fatalf("error = %v, want %v", err, ente.ErrTooManyBadRequest)
	}
	if got := repository.callCount(); got != defaultUserLookupDayLimit {
		t.Fatalf("repository calls = %d, want %d", got, defaultUserLookupDayLimit)
	}

	select {
	case message := <-notifier.messages:
		const want = "user lookup limit exceeded (day window)"
		if message != want {
			t.Fatalf("notification = %q, want %q", message, want)
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for abuse notification")
	}

	if _, err := controller.LookupUserID(7, "another-blocked@example.com"); !errors.Is(err, ente.ErrTooManyBadRequest) {
		t.Fatalf("repeated denial error = %v, want %v", err, ente.ErrTooManyBadRequest)
	}
	select {
	case message := <-notifier.messages:
		t.Fatalf("unexpected repeated abuse notification: %q", message)
	default:
	}
}

func TestUserLookupNotFoundLimitBlocksNewExistingUserBeforeRepository(t *testing.T) {
	now := time.Unix(1000, 0)
	repository := &userLookupRepositoryStub{err: sql.ErrNoRows}
	controller := newUserLookupControllerForTest(repository, nil, func() time.Time { return now })

	for i := 0; i < defaultUserLookupNotFoundMinuteLimit; i++ {
		_, err := controller.LookupUserID(7, fmt.Sprintf("missing-%d@example.com", i))
		if !errors.Is(err, sql.ErrNoRows) {
			t.Fatalf("missing lookup %d error = %v, want %v", i, err, sql.ErrNoRows)
		}
	}

	repository.setResult(42, nil)
	_, err := controller.LookupUserID(7, "existing@example.com")
	if !errors.Is(err, ente.ErrTooManyBadRequest) {
		t.Fatalf("existing-user lookup error = %v, want %v", err, ente.ErrTooManyBadRequest)
	}
	if got := repository.callCount(); got != defaultUserLookupNotFoundMinuteLimit {
		t.Fatalf("repository calls = %d, want %d", got, defaultUserLookupNotFoundMinuteLimit)
	}
}
