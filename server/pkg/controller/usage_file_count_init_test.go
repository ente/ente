package controller

import (
	"testing"
	"time"
)

func TestFileCountInitializationQueueDeduplicatesAndRetries(t *testing.T) {
	initializer := &FileCountInitializer{
		queue:       make(chan int64, 1),
		attemptedAt: make(map[int64]time.Time),
	}
	initializer.Enqueue(1)
	initializer.Enqueue(1)
	initializer.Enqueue(2)
	if len(initializer.queue) != 1 || <-initializer.queue != 1 {
		t.Fatal("duplicate or full enqueue changed the queued user")
	}

	initializer.Enqueue(2)
	if len(initializer.queue) != 1 || <-initializer.queue != 2 {
		t.Fatal("a user dropped from a full queue was not retried")
	}
	initializer.attemptedAt[2] = time.Now()
	initializer.Enqueue(2)
	if len(initializer.queue) != 0 {
		t.Fatal("recently attempted user was queued again")
	}
	initializer.attemptedAt[2] = time.Now().Add(-fileCountInitializationRetry)
	initializer.Enqueue(2)
	if len(initializer.queue) != 1 || <-initializer.queue != 2 {
		t.Fatal("retry window did not expire")
	}
}
