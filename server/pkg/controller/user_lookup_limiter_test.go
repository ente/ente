package controller

import (
	"fmt"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func userLookupDecision(
	limiter *userLookupLimiter,
	requesterUserID int64,
	targetHash string,
	notFound bool,
) userLookupLimitDecision {
	attempt, decision := limiter.Start(requesterUserID, targetHash)
	if decision.allowed {
		decision = limiter.Finish(attempt, notFound)
	}
	return decision
}

func newMinuteLookupLimiter(now func() time.Time) *userLookupLimiter {
	limits := defaultUserLookupLimits()
	limits.day.total = limits.minute.total + 1
	return newUserLookupLimiterWithClock(limits, now)
}

func TestUserLookupLimiterCountsUniqueTargetsPerMinute(t *testing.T) {
	now := time.Unix(1000, 0)
	limiter := newMinuteLookupLimiter(func() time.Time { return now })

	for i := 0; i < defaultUserLookupMinuteLimit; i++ {
		if decision := userLookupDecision(limiter, 1, fmt.Sprintf("target-%d", i), false); !decision.allowed {
			t.Fatalf("target %d decision = %+v, want allowed", i, decision)
		}
	}
	if decision := userLookupDecision(limiter, 1, "target-0", false); !decision.allowed {
		t.Fatalf("repeated target decision = %+v, want allowed", decision)
	}
	if decision := userLookupDecision(limiter, 1, "new-target", false); decision.allowed || decision.window != userLookupMinuteWindow {
		t.Fatalf("extra target decision = %+v, want minute-window denial", decision)
	} else if !decision.notify {
		t.Fatalf("first minute-window denial decision = %+v, want notification", decision)
	}
	if decision := userLookupDecision(limiter, 1, "another-target", false); decision.allowed || decision.notify {
		t.Fatalf("repeated minute-window denial decision = %+v, want silent denial", decision)
	}
	if decision := userLookupDecision(limiter, 2, "new-target", false); !decision.allowed {
		t.Fatalf("independent requester decision = %+v, want allowed", decision)
	}
}

func TestUserLookupLimiterCountsUniqueTargetsPerDay(t *testing.T) {
	now := time.Unix(1000, 0)
	limiter := newUserLookupLimiterWithClock(defaultUserLookupLimits(), func() time.Time { return now })

	for i := 0; i < defaultUserLookupDayLimit; i++ {
		if i > 0 && i%defaultUserLookupMinuteLimit == 0 {
			now = now.Add(userLookupMinuteWindowDuration)
		}
		if decision := userLookupDecision(limiter, 1, fmt.Sprintf("target-%d", i), false); !decision.allowed {
			t.Fatalf("target %d decision = %+v, want allowed", i, decision)
		}
	}

	now = now.Add(userLookupMinuteWindowDuration)
	if decision := userLookupDecision(limiter, 1, "target-0", false); !decision.allowed {
		t.Fatalf("existing daily target decision = %+v, want allowed", decision)
	}
	if decision := userLookupDecision(limiter, 1, "new-target", false); decision.allowed || decision.window != userLookupDayWindow {
		t.Fatalf("extra target decision = %+v, want day-window denial", decision)
	} else if !decision.notify {
		t.Fatalf("first day-window denial decision = %+v, want notification", decision)
	}
	if decision := userLookupDecision(limiter, 1, "another-target", false); decision.allowed || decision.notify {
		t.Fatalf("repeated day-window denial decision = %+v, want silent denial", decision)
	}

	now = time.Unix(1000, 0).Add(userLookupDayWindowDuration)
	if decision := userLookupDecision(limiter, 1, "new-target", false); !decision.allowed {
		t.Fatalf("target after daily reset decision = %+v, want allowed", decision)
	}
}

func TestUserLookupLimiterStopsNewTargetsAfterNotFoundLimit(t *testing.T) {
	now := time.Unix(1000, 0)
	limiter := newUserLookupLimiterWithClock(defaultUserLookupLimits(), func() time.Time { return now })

	for i := 0; i < defaultUserLookupNotFoundMinuteLimit; i++ {
		if decision := userLookupDecision(limiter, 1, fmt.Sprintf("missing-%d", i), true); !decision.allowed {
			t.Fatalf("missing target %d decision = %+v, want allowed", i, decision)
		}
	}
	if decision := userLookupDecision(limiter, 1, "missing-0", true); !decision.allowed {
		t.Fatalf("repeated missing target decision = %+v, want allowed", decision)
	}
	if decision := userLookupDecision(limiter, 1, "existing-user", false); decision.allowed || decision.window != userLookupNotFoundMinuteWindow {
		t.Fatalf("new target decision = %+v, want not-found minute-window denial", decision)
	}
}

func TestUserLookupLimiterCountsNotFoundTargetsPerDay(t *testing.T) {
	now := time.Unix(1000, 0)
	limiter := newUserLookupLimiterWithClock(defaultUserLookupLimits(), func() time.Time { return now })

	for i := 0; i < defaultUserLookupNotFoundDayLimit; i++ {
		if i > 0 && i%defaultUserLookupNotFoundMinuteLimit == 0 {
			now = now.Add(userLookupMinuteWindowDuration)
		}
		if decision := userLookupDecision(limiter, 1, fmt.Sprintf("missing-%d", i), true); !decision.allowed {
			t.Fatalf("missing target %d decision = %+v, want allowed", i, decision)
		}
	}

	now = now.Add(userLookupMinuteWindowDuration)
	if decision := userLookupDecision(limiter, 1, "new-target", false); decision.allowed || decision.window != userLookupNotFoundDayWindow {
		t.Fatalf("new target decision = %+v, want not-found day-window denial", decision)
	}
}

func TestUserLookupLimiterEnforcesConcurrentRequestsAtomically(t *testing.T) {
	now := time.Unix(1000, 0)
	limits := defaultUserLookupLimits()
	limits.minute.notFound = limits.minute.total
	limits.day.total = limits.minute.total + 1
	limits.day.notFound = limits.day.total
	limiter := newUserLookupLimiterWithClock(limits, func() time.Time { return now })

	var allowed atomic.Int64
	var notifications atomic.Int64
	var wg sync.WaitGroup
	for i := 0; i < defaultUserLookupMinuteLimit*2; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			decision := userLookupDecision(limiter, 1, fmt.Sprintf("target-%d", i), false)
			if decision.allowed {
				allowed.Add(1)
			}
			if decision.notify {
				notifications.Add(1)
			}
		}(i)
	}
	wg.Wait()

	if got := allowed.Load(); got != defaultUserLookupMinuteLimit {
		t.Fatalf("allowed concurrent requests = %d, want %d", got, defaultUserLookupMinuteLimit)
	}
	if got := notifications.Load(); got != 1 {
		t.Fatalf("concurrent notifications = %d, want 1", got)
	}
}

func TestUserLookupLimiterReservesNotFoundCapacityForConcurrentRequests(t *testing.T) {
	now := time.Unix(1000, 0)
	limiter := newMinuteLookupLimiter(func() time.Time { return now })

	var allowed atomic.Int64
	var admitted atomic.Int64
	var notifications atomic.Int64
	var started sync.WaitGroup
	var finished sync.WaitGroup
	release := make(chan struct{})
	for i := 0; i < defaultUserLookupMinuteLimit; i++ {
		started.Add(1)
		finished.Add(1)
		go func(i int) {
			defer finished.Done()
			attempt, decision := limiter.Start(1, fmt.Sprintf("target-%d", i))
			started.Done()
			if decision.notify {
				notifications.Add(1)
			}
			if !decision.allowed {
				return
			}
			admitted.Add(1)
			<-release
			decision = limiter.Finish(attempt, true)
			if decision.allowed {
				allowed.Add(1)
			}
		}(i)
	}
	started.Wait()
	if got := admitted.Load(); got != defaultUserLookupNotFoundMinuteLimit {
		t.Fatalf("admitted concurrent lookups = %d, want %d", got, defaultUserLookupNotFoundMinuteLimit)
	}
	close(release)
	finished.Wait()

	if got := allowed.Load(); got != defaultUserLookupNotFoundMinuteLimit {
		t.Fatalf("allowed concurrent requests = %d, want %d", got, defaultUserLookupNotFoundMinuteLimit)
	}
	if got := notifications.Load(); got != 1 {
		t.Fatalf("concurrent notifications = %d, want 1", got)
	}
}

func TestUserLookupLimiterCoalescesNotificationsAcrossRequesters(t *testing.T) {
	now := time.Unix(1000, 0)
	limiter := newMinuteLookupLimiter(func() time.Time { return now })

	for requesterUserID := int64(1); requesterUserID <= 2; requesterUserID++ {
		for i := 0; i < defaultUserLookupMinuteLimit; i++ {
			userLookupDecision(limiter, requesterUserID, fmt.Sprintf("target-%d", i), false)
		}
		decision := userLookupDecision(limiter, requesterUserID, "blocked-target", false)
		if requesterUserID == 1 && !decision.notify {
			t.Fatalf("first requester decision = %+v, want notification", decision)
		}
		if requesterUserID == 2 && decision.notify {
			t.Fatalf("second requester decision = %+v, want coalesced notification", decision)
		}
	}
}

func TestUserLookupLimiterRenotifiesDayDenialsAfterNotificationInterval(t *testing.T) {
	now := time.Unix(1000, 0)
	limiter := newUserLookupLimiterWithClock(defaultUserLookupLimits(), func() time.Time { return now })

	for i := 0; i < defaultUserLookupDayLimit; i++ {
		if i > 0 && i%defaultUserLookupMinuteLimit == 0 {
			now = now.Add(userLookupMinuteWindowDuration)
		}
		for requesterUserID := int64(1); requesterUserID <= 2; requesterUserID++ {
			if decision := userLookupDecision(limiter, requesterUserID, fmt.Sprintf("target-%d", i), false); !decision.allowed {
				t.Fatalf("requester %d target %d decision = %+v, want allowed", requesterUserID, i, decision)
			}
		}
	}

	now = now.Add(userLookupMinuteWindowDuration)
	first := userLookupDecision(limiter, 1, "blocked-target", false)
	if first.allowed || first.window != userLookupDayWindow || !first.notify {
		t.Fatalf("first day-window denial = %+v, want notifying denial", first)
	}
	second := userLookupDecision(limiter, 2, "blocked-target", false)
	if second.allowed || second.window != userLookupDayWindow || second.notify {
		t.Fatalf("coalesced day-window denial = %+v, want silent denial", second)
	}

	now = now.Add(userLookupNotificationInterval)
	third := userLookupDecision(limiter, 2, "another-blocked-target", false)
	if third.allowed || third.window != userLookupDayWindow || !third.notify {
		t.Fatalf("later day-window denial = %+v, want notifying denial", third)
	}
}

func TestUserLookupLimiterPrunesInactiveRequesters(t *testing.T) {
	now := time.Unix(1000, 0)
	limiter := newUserLookupLimiterWithClock(defaultUserLookupLimits(), func() time.Time { return now })
	userLookupDecision(limiter, 1, "target", false)

	now = now.Add(userLookupDayWindowDuration)
	userLookupDecision(limiter, 2, "target", false)

	if _, ok := limiter.actors[1]; ok {
		t.Fatal("inactive requester was not pruned")
	}
	if _, ok := limiter.actors[2]; !ok {
		t.Fatal("active requester was pruned")
	}
}
