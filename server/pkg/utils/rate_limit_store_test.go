package utils

import (
	"context"
	"testing"
	"unsafe"

	"github.com/ulule/limiter/v3"
)

func TestMemoryLimiterStoreCopiesKeys(t *testing.T) {
	store := newMemoryLimiterStore()
	rate := limiter.Rate{Period: limiter.DefaultCleanUpInterval, Limit: 2}

	keyBytes := []byte("1580559962874575")
	key := unsafe.String(unsafe.SliceData(keyBytes), len(keyBytes))
	if _, err := store.Get(context.Background(), key, rate); err != nil {
		t.Fatal(err)
	}

	copy(keyBytes, "9999999999999999")

	original, err := store.Peek(context.Background(), "1580559962874575", rate)
	if err != nil {
		t.Fatal(err)
	}
	if original.Remaining != 1 {
		t.Fatalf("stored key was not retained: remaining = %d", original.Remaining)
	}

	mutated, err := store.Peek(context.Background(), "9999999999999999", rate)
	if err != nil {
		t.Fatal(err)
	}
	if mutated.Remaining != 2 {
		t.Fatalf("mutated key unexpectedly hit existing counter: remaining = %d", mutated.Remaining)
	}
}

func TestNewRateLimiterUsesSafeStore(t *testing.T) {
	rateLimiter := NewRateLimiter("2-S")
	if _, ok := rateLimiter.Store.(*memoryLimiterStore); !ok {
		t.Fatalf("unexpected store type %T", rateLimiter.Store)
	}

	first, err := rateLimiter.Get(context.Background(), "user")
	if err != nil {
		t.Fatal(err)
	}
	if first.Reached || first.Remaining != 1 {
		t.Fatalf("unexpected first limit context: %+v", first)
	}

	second, err := rateLimiter.Get(context.Background(), "user")
	if err != nil {
		t.Fatal(err)
	}
	if second.Reached || second.Remaining != 0 {
		t.Fatalf("unexpected second limit context: %+v", second)
	}

	third, err := rateLimiter.Get(context.Background(), "user")
	if err != nil {
		t.Fatal(err)
	}
	if !third.Reached {
		t.Fatalf("third request should be rate limited: %+v", third)
	}
}
