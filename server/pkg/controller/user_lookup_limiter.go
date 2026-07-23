package controller

import (
	"sync"
	"time"
)

const (
	defaultUserLookupMinuteLimit         = 50
	defaultUserLookupDayLimit            = 50
	defaultUserLookupNotFoundMinuteLimit = 5
	defaultUserLookupNotFoundDayLimit    = 10

	userLookupMinuteWindowDuration = time.Minute
	userLookupDayWindowDuration    = 24 * time.Hour
	userLookupNotificationInterval = time.Minute
	userLookupPruneInterval        = time.Hour
)

type userLookupWindowLimits struct {
	total    int
	notFound int
}

type userLookupLimits struct {
	minute userLookupWindowLimits
	day    userLookupWindowLimits
}

func defaultUserLookupLimits() userLookupLimits {
	return userLookupLimits{
		minute: userLookupWindowLimits{
			total:    defaultUserLookupMinuteLimit,
			notFound: defaultUserLookupNotFoundMinuteLimit,
		},
		day: userLookupWindowLimits{
			total:    defaultUserLookupDayLimit,
			notFound: defaultUserLookupNotFoundDayLimit,
		},
	}
}

type userLookupLimitWindow string

const (
	userLookupMinuteWindow         userLookupLimitWindow = "minute"
	userLookupDayWindow            userLookupLimitWindow = "day"
	userLookupNotFoundMinuteWindow userLookupLimitWindow = "not-found minute"
	userLookupNotFoundDayWindow    userLookupLimitWindow = "not-found day"
)

type userLookupLimitDecision struct {
	allowed bool
	notify  bool
	window  userLookupLimitWindow
}

type userLookupWindow struct {
	startedAt time.Time
	targets   map[string]struct{}
	notFound  map[string]struct{}
	pending   map[string]struct{}
}

type userLookupActorState struct {
	lastSeen time.Time
	minute   userLookupWindow
	day      userLookupWindow
}

type userLookupAttempt struct {
	requesterUserID int64
	targetHash      string
	minuteStartedAt time.Time
	dayStartedAt    time.Time
}

type userLookupLimiter struct {
	mu sync.Mutex

	now        func() time.Time
	limits     userLookupLimits
	lastPruned time.Time
	actors     map[int64]*userLookupActorState
	lastNotify map[userLookupLimitWindow]time.Time
}

func newUserLookupLimiter(limits userLookupLimits) *userLookupLimiter {
	return newUserLookupLimiterWithClock(limits, time.Now)
}

func newUserLookupLimiterWithClock(limits userLookupLimits, now func() time.Time) *userLookupLimiter {
	currentTime := now()
	return &userLookupLimiter{
		now:        now,
		limits:     limits,
		lastPruned: currentTime,
		actors:     make(map[int64]*userLookupActorState),
		lastNotify: make(map[userLookupLimitWindow]time.Time),
	}
}

func (l *userLookupLimiter) Start(requesterUserID int64, targetHash string) (userLookupAttempt, userLookupLimitDecision) {
	l.mu.Lock()
	defer l.mu.Unlock()

	now := l.now()
	l.prune(now)

	state, ok := l.actors[requesterUserID]
	if !ok {
		state = &userLookupActorState{}
		l.actors[requesterUserID] = state
	}
	state.lastSeen = now
	state.minute.resetIfExpired(now, userLookupMinuteWindowDuration)
	state.day.resetIfExpired(now, userLookupDayWindowDuration)

	minuteNew := !state.minute.contains(targetHash)
	dayNew := !state.day.contains(targetHash)
	if minuteNew && len(state.minute.targets) >= l.limits.minute.total {
		return userLookupAttempt{}, l.denied(now, userLookupMinuteWindow)
	}
	if dayNew && len(state.day.targets) >= l.limits.day.total {
		return userLookupAttempt{}, l.denied(now, userLookupDayWindow)
	}
	if minuteNew && len(state.minute.notFound)+len(state.minute.pending) >= l.limits.minute.notFound {
		return userLookupAttempt{}, l.denied(now, userLookupNotFoundMinuteWindow)
	}
	if dayNew && len(state.day.notFound)+len(state.day.pending) >= l.limits.day.notFound {
		return userLookupAttempt{}, l.denied(now, userLookupNotFoundDayWindow)
	}

	state.minute.targets[targetHash] = struct{}{}
	state.day.targets[targetHash] = struct{}{}
	if minuteNew {
		state.minute.pending[targetHash] = struct{}{}
	}
	if dayNew {
		state.day.pending[targetHash] = struct{}{}
	}
	attempt := userLookupAttempt{
		requesterUserID: requesterUserID,
		targetHash:      targetHash,
		minuteStartedAt: state.minute.startedAt,
		dayStartedAt:    state.day.startedAt,
	}
	return attempt, userLookupLimitDecision{allowed: true}
}

func (l *userLookupLimiter) Finish(attempt userLookupAttempt, notFound bool) userLookupLimitDecision {
	l.mu.Lock()
	defer l.mu.Unlock()

	state, ok := l.actors[attempt.requesterUserID]
	if !ok {
		return userLookupLimitDecision{allowed: true}
	}
	minuteActive := state.minute.startedAt.Equal(attempt.minuteStartedAt)
	dayActive := state.day.startedAt.Equal(attempt.dayStartedAt)
	if minuteActive {
		delete(state.minute.pending, attempt.targetHash)
	}
	if dayActive {
		delete(state.day.pending, attempt.targetHash)
	}
	if !notFound {
		return userLookupLimitDecision{allowed: true}
	}
	if minuteActive && !state.minute.isNotFound(attempt.targetHash) && len(state.minute.notFound) >= l.limits.minute.notFound {
		return l.denied(l.now(), userLookupNotFoundMinuteWindow)
	}
	if dayActive && !state.day.isNotFound(attempt.targetHash) && len(state.day.notFound) >= l.limits.day.notFound {
		return l.denied(l.now(), userLookupNotFoundDayWindow)
	}
	if minuteActive {
		state.minute.notFound[attempt.targetHash] = struct{}{}
	}
	if dayActive {
		state.day.notFound[attempt.targetHash] = struct{}{}
	}
	return userLookupLimitDecision{allowed: true}
}

func (l *userLookupLimiter) denied(now time.Time, window userLookupLimitWindow) userLookupLimitDecision {
	decision := userLookupLimitDecision{window: window}
	lastNotify := l.lastNotify[window]
	if lastNotify.IsZero() || now.Sub(lastNotify) >= userLookupNotificationInterval {
		l.lastNotify[window] = now
		decision.notify = true
	}
	return decision
}

func (l *userLookupLimiter) prune(now time.Time) {
	if now.Sub(l.lastPruned) < userLookupPruneInterval {
		return
	}
	cutoff := now.Add(-userLookupDayWindowDuration)
	for requesterUserID, state := range l.actors {
		if !state.lastSeen.After(cutoff) {
			delete(l.actors, requesterUserID)
		}
	}
	l.lastPruned = now
}

func (w *userLookupWindow) resetIfExpired(now time.Time, duration time.Duration) {
	if w.targets != nil && now.Sub(w.startedAt) < duration {
		return
	}
	w.startedAt = now
	w.targets = make(map[string]struct{})
	w.notFound = make(map[string]struct{})
	w.pending = make(map[string]struct{})
}

func (w *userLookupWindow) contains(targetHash string) bool {
	_, ok := w.targets[targetHash]
	return ok
}

func (w *userLookupWindow) isNotFound(targetHash string) bool {
	_, ok := w.notFound[targetHash]
	return ok
}
