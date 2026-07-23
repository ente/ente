package user

import (
	"fmt"
	"testing"
	"time"
)

func TestOTTSendLimiterAllowsRepeatedIPBelowElevatedThreshold(t *testing.T) {
	now := time.Unix(1000, 0)
	limiter := newOTTSendLimiter(func() time.Time { return now })

	decision := limiter.Allow("203.0.113.1")
	if !decision.allowed || decision.alert != "" {
		t.Fatalf("first request decision=%+v, want allowed only", decision)
	}

	decision = limiter.Allow("203.0.113.1")
	if !decision.allowed || decision.alert != "" {
		t.Fatalf("second request below threshold decision=%+v, want allowed only", decision)
	}
}

func TestOTTSendLimiterBlocksRepeatedIPInElevatedMode(t *testing.T) {
	now := time.Unix(1000, 0)
	limiter := newOTTSendLimiter(func() time.Time { return now })

	for i := 0; i < ottSendElevatedThreshold-1; i++ {
		decision := limiter.Allow(fmt.Sprintf("203.0.113.%d", i+1))
		if !decision.allowed || decision.alert != "" {
			t.Fatalf("seed request %d decision=%+v, want allowed only", i, decision)
		}
	}

	decision := limiter.Allow("198.51.100.10")
	if !decision.allowed || decision.alert != ottSendElevatedAlert {
		t.Fatalf("first elevated request decision=%+v, want allowed with elevated activation", decision)
	}

	decision = limiter.Allow("198.51.100.10")
	if decision.allowed || decision.alert != "" {
		t.Fatalf("repeated elevated request decision=%+v, want blocked without activation", decision)
	}

	decision = limiter.Allow("198.51.100.51")
	if !decision.allowed || decision.alert != "" {
		t.Fatalf("request %d decision=%+v, want allowed without repeated alert", ottSendElevatedThreshold+1, decision)
	}
}

func TestOTTSendLimiterActivatesGlobalBlock(t *testing.T) {
	now := time.Unix(1000, 0)
	limiter := newOTTSendLimiter(func() time.Time { return now })

	for i := 0; i < ottSendSevereThreshold-1; i++ {
		decision := limiter.Allow(fmt.Sprintf("203.0.113.%d", i))
		if !decision.allowed || decision.alert == ottSendSevereAlert {
			t.Fatalf("seed request %d decision=%+v, want allowed without severe activation", i, decision)
		}
	}

	decision := limiter.Allow("198.51.100.10")
	if decision.allowed || decision.alert != ottSendSevereAlert {
		t.Fatalf("severe request decision=%+v, want blocked with severe activation", decision)
	}
	if !limiter.IsGloballyBlocked() {
		t.Fatal("limiter should be globally blocked after severe threshold")
	}
}

func TestOTTSendLimiterGlobalBlockExpires(t *testing.T) {
	now := time.Unix(1000, 0)
	limiter := newOTTSendLimiter(func() time.Time { return now })

	for i := 0; i < ottSendSevereThreshold; i++ {
		limiter.Allow(fmt.Sprintf("203.0.113.%d", i))
	}
	if !limiter.IsGloballyBlocked() {
		t.Fatal("limiter should be globally blocked")
	}

	now = now.Add(ottSendSevereBlockDuration - time.Nanosecond)
	if !limiter.IsGloballyBlocked() {
		t.Fatal("limiter should remain globally blocked before expiry")
	}

	now = now.Add(2 * time.Nanosecond)
	if limiter.IsGloballyBlocked() {
		t.Fatal("limiter should allow requests after global block expiry")
	}
}

func TestOTTSendLimiterPrunesExpiredAttemptsAndIPCooldowns(t *testing.T) {
	now := time.Unix(1000, 0)
	limiter := newOTTSendLimiter(func() time.Time { return now })

	decision := limiter.Allow("203.0.113.1")
	if !decision.allowed || decision.alert != "" {
		t.Fatalf("initial request decision=%+v, want allowed only", decision)
	}

	now = now.Add(ottSendAttackWindow + time.Nanosecond)
	decision = limiter.Allow("198.51.100.10")
	if !decision.allowed || decision.alert != "" {
		t.Fatalf("fresh request decision=%+v, want allowed only", decision)
	}

	if got := len(limiter.attempts); got != 1 {
		t.Fatalf("attempt count after prune = %d, want 1", got)
	}
	if _, ok := limiter.ipNextAllowed["203.0.113.1"]; ok {
		t.Fatal("expired IP cooldown should be pruned")
	}
	if _, ok := limiter.ipNextAllowed["198.51.100.10"]; !ok {
		t.Fatal("fresh IP cooldown should remain")
	}
}
