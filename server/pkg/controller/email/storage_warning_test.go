package email

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/ente/museum/ente"
	bonus "github.com/ente/museum/ente/storagebonus"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/billing"
	"github.com/ente/museum/pkg/utils/rollout"
	"github.com/ente/museum/pkg/utils/time"
	log "github.com/sirupsen/logrus"
)

type recordingUserAccessResetter struct {
	callCount int
	callOrder *[]string
	err       error
}

func (r *recordingUserAccessResetter) ResetUserAccess(_ context.Context, _ int64, _ *log.Entry) error {
	r.callCount++
	if r.callOrder != nil {
		*r.callOrder = append(*r.callOrder, "reset")
	}
	return r.err
}

func TestBucketStorageWarningActiveOverage(t *testing.T) {
	now := int64(100)
	effectiveExpiry := now + 10
	expiredWarningAnchor := now + 20
	allottedStorage := int64(50)
	totalUsage := allottedStorage + storageWarningOverageThreshold + 1

	got := bucketStorageWarning(totalUsage, allottedStorage, effectiveExpiry, expiredWarningAnchor, now)
	if got != storageWarningBucketActiveOverage {
		t.Fatalf("unexpected bucket: got %q want %q", got, storageWarningBucketActiveOverage)
	}
}

func TestBucketStorageWarningExpired(t *testing.T) {
	effectiveExpiry := int64(90)
	expiredWarningAnchor := int64(100)
	now := expiredWarningAnchor
	allottedStorage := int64(0)
	totalUsage := allottedStorage + storageWarningOverageThreshold + 1

	got := bucketStorageWarning(totalUsage, allottedStorage, effectiveExpiry, expiredWarningAnchor, now)
	if got != storageWarningBucketExpired {
		t.Fatalf("unexpected bucket: got %q want %q", got, storageWarningBucketExpired)
	}
}

func TestBucketStorageWarningWaitsForExpiredWarningAnchor(t *testing.T) {
	effectiveExpiry := int64(100)
	expiredWarningAnchor := effectiveExpiry + storageWarningExpiredAnchorDelay
	now := effectiveExpiry

	got := bucketStorageWarning(storageWarningOverageThreshold+1, 0, effectiveExpiry, expiredWarningAnchor, now)
	if got != storageWarningBucketNone {
		t.Fatalf("unexpected bucket: got %q want %q", got, storageWarningBucketNone)
	}
}

func TestBucketStorageWarningExpiredRequiresUsageAboveThreshold(t *testing.T) {
	effectiveExpiry := int64(100)
	expiredWarningAnchor := int64(100)
	now := effectiveExpiry

	got := bucketStorageWarning(storageWarningOverageThreshold, 0, effectiveExpiry, expiredWarningAnchor, now)
	if got != storageWarningBucketNone {
		t.Fatalf("unexpected bucket: got %q want %q", got, storageWarningBucketNone)
	}
}

func TestComputeStorageWarningMetricsActiveSubscription(t *testing.T) {
	now := int64(100)
	subscription := &ente.Subscription{
		Storage:         100,
		ExpiryTime:      now + 1,
		PaymentProvider: ente.Stripe,
	}
	totalUsage := subscription.Storage + storageWarningOverageThreshold + 1

	got := computeStorageWarningMetrics(subscription, nil, totalUsage, now)

	if got.BaseStorage != subscription.Storage {
		t.Fatalf("unexpected base storage: got %d want %d", got.BaseStorage, subscription.Storage)
	}
	if got.SubscriptionExpiry != subscription.ExpiryTime {
		t.Fatalf("unexpected subscription expiry: got %d want %d", got.SubscriptionExpiry, subscription.ExpiryTime)
	}
	wantEffectiveExpiry := subscription.ExpiryTime + billing.ProviderToExpiryGracePeriodMap[ente.Stripe]
	if got.EffectiveExpiry != wantEffectiveExpiry {
		t.Fatalf("unexpected effective expiry: got %d want %d", got.EffectiveExpiry, wantEffectiveExpiry)
	}
	wantExpiredWarningAnchor := subscription.ExpiryTime + storageWarningExpiredAnchorDelay
	if got.ExpiredWarningAnchor != wantExpiredWarningAnchor {
		t.Fatalf("unexpected expired warning anchor: got %d want %d", got.ExpiredWarningAnchor, wantExpiredWarningAnchor)
	}
	if got.Bucket != storageWarningBucketActiveOverage {
		t.Fatalf("unexpected bucket: got %q want %q", got.Bucket, storageWarningBucketActiveOverage)
	}
}

func TestComputeStorageWarningMetricsAddonKeepsAccountActive(t *testing.T) {
	now := billing.ProviderToExpiryGracePeriodMap[ente.Stripe] + 1000
	subscription := &ente.Subscription{
		Storage:         100,
		ExpiryTime:      now - billing.ProviderToExpiryGracePeriodMap[ente.Stripe] - 1,
		PaymentProvider: ente.Stripe,
	}
	activeBonuses := &bonus.ActiveStorageBonus{
		StorageBonuses: []bonus.StorageBonus{
			{
				Storage:   10,
				Type:      bonus.AddOnSupport,
				ValidTill: now + time.MicroSecondsInOneHour,
			},
		},
	}
	totalUsage := int64(10) + storageWarningOverageThreshold + 1

	got := computeStorageWarningMetrics(subscription, activeBonuses, totalUsage, now)

	if got.BaseStorage != 0 {
		t.Fatalf("unexpected base storage for expired subscription: got %d want 0", got.BaseStorage)
	}
	if got.SubscriptionExpiry != subscription.ExpiryTime {
		t.Fatalf("unexpected subscription expiry: got %d want %d", got.SubscriptionExpiry, subscription.ExpiryTime)
	}
	if got.EffectiveExpiry != now+time.MicroSecondsInOneHour {
		t.Fatalf("unexpected effective expiry: got %d want %d", got.EffectiveExpiry, now+time.MicroSecondsInOneHour)
	}
	wantExpiredWarningAnchor := subscription.ExpiryTime + storageWarningExpiredAnchorDelay
	if got.ExpiredWarningAnchor != wantExpiredWarningAnchor {
		t.Fatalf("unexpected expired warning anchor: got %d want %d", got.ExpiredWarningAnchor, wantExpiredWarningAnchor)
	}
	if got.Bucket != storageWarningBucketActiveOverage {
		t.Fatalf("unexpected bucket: got %q want %q", got.Bucket, storageWarningBucketActiveOverage)
	}
}

func TestComputeStorageWarningMetricsNilSubscriptionDoesNotCrash(t *testing.T) {
	now := int64(1000)
	activeBonuses := &bonus.ActiveStorageBonus{
		StorageBonuses: []bonus.StorageBonus{
			{
				Storage:   10,
				Type:      bonus.AddOnSupport,
				ValidTill: now + time.MicroSecondsInOneHour,
			},
		},
	}

	got := computeStorageWarningMetrics(nil, activeBonuses, int64(10)+storageWarningOverageThreshold+1, now)

	if got.BaseStorage != 0 {
		t.Fatalf("unexpected base storage without subscription: got %d want 0", got.BaseStorage)
	}
	if got.SubscriptionExpiry != 0 {
		t.Fatalf("unexpected subscription expiry without subscription: got %d want 0", got.SubscriptionExpiry)
	}
	if got.ExpiredWarningAnchor != 0 {
		t.Fatalf("unexpected expired warning anchor without subscription: got %d want 0", got.ExpiredWarningAnchor)
	}
	if got.Bucket != storageWarningBucketActiveOverage {
		t.Fatalf("unexpected bucket: got %q want %q", got.Bucket, storageWarningBucketActiveOverage)
	}
}

func TestComputeStorageWarningMetricsFreeSubscriptionCanBeActiveOverage(t *testing.T) {
	now := int64(100)
	subscription := &ente.Subscription{
		Storage:         10 * (1 << 30),
		ExpiryTime:      now + time.MicroSecondsInOneHour,
		PaymentProvider: ente.Stripe,
		ProductID:       ente.FreePlanProductID,
	}
	totalUsage := subscription.Storage + storageWarningOverageThreshold + 1

	got := computeStorageWarningMetrics(subscription, nil, totalUsage, now)

	if got.BaseStorage != subscription.Storage {
		t.Fatalf("unexpected base storage: got %d want %d", got.BaseStorage, subscription.Storage)
	}
	if got.SubscriptionExpiry != subscription.ExpiryTime {
		t.Fatalf("unexpected subscription expiry: got %d want %d", got.SubscriptionExpiry, subscription.ExpiryTime)
	}
	if got.Bucket != storageWarningBucketActiveOverage {
		t.Fatalf("unexpected bucket: got %q want %q", got.Bucket, storageWarningBucketActiveOverage)
	}
}

func TestResolveExpiredWarningStage(t *testing.T) {
	expiredWarningAnchor := int64(100)

	tests := []struct {
		name    string
		now     int64
		history map[string]int64
		want    expiredWarningStage
	}{
		{
			name:    "before first reminder",
			now:     expiredWarningAnchor - 1,
			history: map[string]int64{},
			want:    expiredWarningStageNone,
		},
		{
			name:    "first reminder at anchor day",
			now:     expiredWarningAnchor,
			history: map[string]int64{},
			want:    expiredWarningStage0,
		},
		{
			name: "second reminder after first sent",
			now:  expiredWarningAnchor + storageWarningExpiredWarning30Delay,
			history: map[string]int64{
				storageWarningExpired0TemplateID: expiredWarningAnchor,
			},
			want: expiredWarningStage30,
		},
		{
			name: "third reminder after earlier stages sent",
			now:  expiredWarningAnchor + storageWarningExpiredWarning60Delay,
			history: map[string]int64{
				storageWarningExpired0TemplateID:  expiredWarningAnchor,
				storageWarningExpired30TemplateID: expiredWarningAnchor + storageWarningExpiredWarning30Delay,
			},
			want: expiredWarningStage60,
		},
		{
			name: "fourth reminder after earlier stages sent",
			now:  expiredWarningAnchor + storageWarningExpiredWarning90Delay,
			history: map[string]int64{
				storageWarningExpired0TemplateID:  expiredWarningAnchor,
				storageWarningExpired30TemplateID: expiredWarningAnchor + storageWarningExpiredWarning30Delay,
				storageWarningExpired60TemplateID: expiredWarningAnchor + storageWarningExpiredWarning60Delay,
			},
			want: expiredWarningStage90,
		},
		{
			name: "final reminder for long expired user",
			now:  expiredWarningAnchor + storageWarningExpiredWarning119Delay + 10,
			history: map[string]int64{
				storageWarningExpired0TemplateID:  expiredWarningAnchor,
				storageWarningExpired30TemplateID: expiredWarningAnchor + storageWarningExpiredWarning30Delay,
				storageWarningExpired60TemplateID: expiredWarningAnchor + storageWarningExpiredWarning60Delay,
				storageWarningExpired90TemplateID: expiredWarningAnchor + storageWarningExpiredWarning90Delay,
			},
			want: expiredWarningStage119,
		},
		{
			name: "scheduled deletion after final reminder sent",
			now:  expiredWarningAnchor + storageWarningExpiredDeletionDelay,
			history: map[string]int64{
				storageWarningExpired0TemplateID:   expiredWarningAnchor,
				storageWarningExpired30TemplateID:  expiredWarningAnchor + storageWarningExpiredWarning30Delay,
				storageWarningExpired60TemplateID:  expiredWarningAnchor + storageWarningExpiredWarning60Delay,
				storageWarningExpired90TemplateID:  expiredWarningAnchor + storageWarningExpiredWarning90Delay,
				storageWarningExpired119TemplateID: expiredWarningAnchor + storageWarningExpiredWarning119Delay,
			},
			want: expiredWarningStageScheduledDeletion,
		},
		{
			name: "scheduled deletion is sent only once",
			now:  expiredWarningAnchor + storageWarningExpiredDeletionDelay + 10,
			history: map[string]int64{
				storageWarningExpired0TemplateID:                      expiredWarningAnchor,
				storageWarningExpired30TemplateID:                     expiredWarningAnchor + storageWarningExpiredWarning30Delay,
				storageWarningExpired60TemplateID:                     expiredWarningAnchor + storageWarningExpiredWarning60Delay,
				storageWarningExpired90TemplateID:                     expiredWarningAnchor + storageWarningExpiredWarning90Delay,
				storageWarningExpired119TemplateID:                    expiredWarningAnchor + storageWarningExpiredWarning119Delay,
				repo.StorageWarningExpiredScheduledDeletionTemplateID: expiredWarningAnchor + storageWarningExpiredDeletionDelay,
			},
			want: expiredWarningStageNone,
		},
		{
			name: "old cycle reminder ignored after renewal",
			now:  expiredWarningAnchor,
			history: map[string]int64{
				storageWarningExpired0TemplateID: expiredWarningAnchor - 1,
			},
			want: expiredWarningStage0,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := resolveExpiredWarningStage(expiredWarningAnchor, tc.now, tc.history)
			if got != tc.want {
				t.Fatalf("unexpected stage: got %q want %q", got, tc.want)
			}
		})
	}
}

func TestResolveExpiredWarningUsesBufferedCycleForLateBackfill(t *testing.T) {
	expiredWarningAnchor := int64(100)
	now := expiredWarningAnchor + storageWarningExpiredWarning119Delay + 10
	got := resolveExpiredWarning(expiredWarningAnchor, now, map[string]int64{})

	if got.Stage != expiredWarningStage0 {
		t.Fatalf("unexpected stage: got %q want %q", got.Stage, expiredWarningStage0)
	}
	if !got.BufferedCycle {
		t.Fatal("expected late backfill to use a buffered cycle")
	}
	if got.CycleStart != now {
		t.Fatalf("unexpected cycle start: got %d want %d", got.CycleStart, now)
	}
	wantAutoDeleteDate := now + storageWarningExpiredBackfillMinRecoveryDelay
	if got.AutoDeleteDate != wantAutoDeleteDate {
		t.Fatalf("unexpected auto delete date: got %d want %d", got.AutoDeleteDate, wantAutoDeleteDate)
	}
}

func TestResolveExpiredWarningBufferedCycleKeepsLaterHistoricalDeleteDate(t *testing.T) {
	expiredWarningAnchor := int64(100)
	now := expiredWarningAnchor + storageWarningExpiredBackfillThreshold + 10

	got := resolveExpiredWarning(expiredWarningAnchor, now, map[string]int64{})

	if got.Stage != expiredWarningStage0 {
		t.Fatalf("unexpected stage: got %q want %q", got.Stage, expiredWarningStage0)
	}
	if !got.BufferedCycle {
		t.Fatal("expected late first contact to use buffered cycle")
	}
	wantAutoDeleteDate := expiredWarningAnchor + storageWarningExpiredDeletionDelay
	if got.AutoDeleteDate != wantAutoDeleteDate {
		t.Fatalf("unexpected auto delete date: got %d want %d", got.AutoDeleteDate, wantAutoDeleteDate)
	}
}

func TestResolveExpiredWarningBufferedCycleProgressesFromPersistedHistory(t *testing.T) {
	cycleStart := int64(100)
	autoDeleteDate := cycleStart + storageWarningExpiredBackfillMinRecoveryDelay
	now := expiredBufferedWarning119At(autoDeleteDate) + 10
	history := map[string]int64{
		storageWarningExpired0TemplateID:  cycleStart,
		storageWarningExpired60TemplateID: expiredBufferedWarning60At(cycleStart, autoDeleteDate),
	}

	got := resolveExpiredBufferedWarningStage(cycleStart, autoDeleteDate, now, history)
	if got != expiredWarningStage119 {
		t.Fatalf("unexpected buffered stage: got %q want %q", got, expiredWarningStage119)
	}
}

func TestExpiredWarningAutoDeleteDateClampsOverdueFinalStage(t *testing.T) {
	now := int64(1000)
	autoDeleteDate := now - 10

	got := expiredWarningAutoDeleteDate(autoDeleteDate, expiredWarningStage119, now)
	want := now + storageWarningOneDayInMicroseconds
	if got != want {
		t.Fatalf("unexpected auto delete date: got %d want %d", got, want)
	}
}

func TestResolveActiveOverageWarningStage(t *testing.T) {
	now := storageWarningActiveOverageDeletionDelay + (10 * storageWarningOneDayInMicroseconds)
	firstWarningTime := now - storageWarningActiveOverageWarning89Delay - 10

	tests := []struct {
		name    string
		now     int64
		history map[string]int64
		want    activeOverageWarningStage
	}{
		{
			name:    "first reminder is immediate when no history exists",
			now:     now,
			history: map[string]int64{},
			want:    activeOverageWarningStage0,
		},
		{
			name: "30 day reminder after first send",
			now:  now,
			history: map[string]int64{
				StorageWarningActiveOverageAnchorTemplateID: now - storageWarningActiveOverageWarning30Delay,
			},
			want: activeOverageWarningStage30,
		},
		{
			name: "60 day reminder after earlier stage sent",
			now:  now,
			history: map[string]int64{
				StorageWarningActiveOverageAnchorTemplateID: now - storageWarningActiveOverageWarning60Delay,
				storageWarningActiveOverage30TemplateID:     now - storageWarningActiveOverageWarning30Delay,
			},
			want: activeOverageWarningStage60,
		},
		{
			name: "89 day reminder for long running overusage",
			now:  now,
			history: map[string]int64{
				StorageWarningActiveOverageAnchorTemplateID: firstWarningTime,
				storageWarningActiveOverage30TemplateID:     firstWarningTime + storageWarningActiveOverageWarning30Delay,
				storageWarningActiveOverage60TemplateID:     firstWarningTime + storageWarningActiveOverageWarning60Delay,
			},
			want: activeOverageWarningStage89,
		},
		{
			name: "scheduled deletion after final reminder sent",
			now:  now,
			history: map[string]int64{
				StorageWarningActiveOverageAnchorTemplateID: now - storageWarningActiveOverageDeletionDelay,
				storageWarningActiveOverage30TemplateID:     now - storageWarningActiveOverageDeletionDelay + storageWarningActiveOverageWarning30Delay,
				storageWarningActiveOverage60TemplateID:     now - storageWarningActiveOverageDeletionDelay + storageWarningActiveOverageWarning60Delay,
				storageWarningActiveOverage89TemplateID:     now - storageWarningActiveOverageDeletionDelay + storageWarningActiveOverageWarning89Delay,
			},
			want: activeOverageWarningStageScheduledDeletion,
		},
		{
			name: "no reminder when all due stages already sent",
			now:  now,
			history: map[string]int64{
				StorageWarningActiveOverageAnchorTemplateID: now - storageWarningActiveOverageWarning30Delay,
				storageWarningActiveOverage30TemplateID:     now - 1,
			},
			want: activeOverageWarningStageNone,
		},
		{
			name: "stale anchor restarts at day zero",
			now:  now,
			history: map[string]int64{
				StorageWarningActiveOverageAnchorTemplateID: now - storageWarningActiveOverageDeletionDelay,
				storageWarningActiveOverage30TemplateID:     now - storageWarningActiveOverageDeletionDelay + storageWarningActiveOverageWarning30Delay,
			},
			want: activeOverageWarningStage0,
		},
		{
			name: "stale final reminder restarts at day zero",
			now:  now + storageWarningPreviousStageFreshnessWindow + storageWarningOneDayInMicroseconds,
			history: map[string]int64{
				StorageWarningActiveOverageAnchorTemplateID: now - storageWarningActiveOverageDeletionDelay,
				storageWarningActiveOverage30TemplateID:     now - storageWarningActiveOverageDeletionDelay + storageWarningActiveOverageWarning30Delay,
				storageWarningActiveOverage60TemplateID:     now - storageWarningActiveOverageDeletionDelay + storageWarningActiveOverageWarning60Delay,
				storageWarningActiveOverage89TemplateID:     now - storageWarningActiveOverageDeletionDelay + storageWarningActiveOverageWarning89Delay,
			},
			want: activeOverageWarningStage0,
		},
		{
			name: "scheduled deletion is sent only once",
			now:  now,
			history: map[string]int64{
				StorageWarningActiveOverageAnchorTemplateID:                 now - storageWarningActiveOverageDeletionDelay,
				storageWarningActiveOverage30TemplateID:                     now - storageWarningActiveOverageDeletionDelay + storageWarningActiveOverageWarning30Delay,
				storageWarningActiveOverage60TemplateID:                     now - storageWarningActiveOverageDeletionDelay + storageWarningActiveOverageWarning60Delay,
				storageWarningActiveOverage89TemplateID:                     now - storageWarningActiveOverageDeletionDelay + storageWarningActiveOverageWarning89Delay,
				repo.StorageWarningActiveOverageScheduledDeletionTemplateID: now - 1,
			},
			want: activeOverageWarningStageNone,
		},
		{
			name: "terminal marker suppresses restart even without anchor history",
			now:  now,
			history: map[string]int64{
				repo.StorageWarningActiveOverageScheduledDeletionTemplateID: now - 1,
			},
			want: activeOverageWarningStageNone,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := resolveActiveOverageWarningStage(tc.now, tc.history)
			if got != tc.want {
				t.Fatalf("unexpected stage: got %q want %q", got, tc.want)
			}
		})
	}
}

func TestActiveOverageWarningAutoDeleteDateClampsOverdueFinalStage(t *testing.T) {
	now := storageWarningActiveOverageDeletionDelay + 1000
	cycleStart := now - storageWarningActiveOverageDeletionDelay - 10

	got := activeOverageWarningAutoDeleteDate(cycleStart, activeOverageWarningStage89, now)
	want := now + storageWarningOneDayInMicroseconds
	if got != want {
		t.Fatalf("unexpected auto delete date: got %d want %d", got, want)
	}
}

func TestResolveActiveOverageWarningReturnsCycleStart(t *testing.T) {
	now := storageWarningActiveOverageDeletionDelay + storageWarningOneDayInMicroseconds
	history := map[string]int64{
		StorageWarningActiveOverageAnchorTemplateID: now - storageWarningActiveOverageWarning30Delay,
	}

	got := resolveActiveOverageWarning(now, history)
	if got.Stage != activeOverageWarningStage30 {
		t.Fatalf("unexpected stage: got %q want %q", got.Stage, activeOverageWarningStage30)
	}
	if got.CycleStart != history[StorageWarningActiveOverageAnchorTemplateID] {
		t.Fatalf("unexpected cycle start: got %d want %d", got.CycleStart, history[StorageWarningActiveOverageAnchorTemplateID])
	}
}

func TestStorageWarningTemplateSentInCycle(t *testing.T) {
	history := map[string]int64{
		storageWarningExpired30TemplateID: 50,
	}

	if storageWarningTemplateSentInCycle(history, storageWarningExpired30TemplateID, 100) {
		t.Fatal("expected prior-cycle send to be ignored")
	}
	if !storageWarningTemplateSentInCycle(history, storageWarningExpired30TemplateID, 50) {
		t.Fatal("expected same-cycle send to be considered")
	}
}

func TestStorageWarningCadenceBroken(t *testing.T) {
	now := storageWarningActiveOverageDeletionDelay + (10 * storageWarningOneDayInMicroseconds)

	tests := []struct {
		name       string
		snapshot   storageWarningSnapshot
		wantBroken bool
		wantStage  string
	}{
		{
			name: "initial stages are exempt",
			snapshot: storageWarningSnapshot{
				Bucket:             storageWarningBucketActiveOverage,
				ActiveOverageStage: activeOverageWarningStage0,
				EvaluatedAt:        now,
			},
			wantBroken: false,
		},
		{
			name: "active overage stage 30 requires anchor send",
			snapshot: storageWarningSnapshot{
				Bucket:              storageWarningBucketActiveOverage,
				ActiveOverageStage:  activeOverageWarningStage30,
				EvaluatedAt:         now,
				WarningCycleStart:   now - storageWarningActiveOverageWarning30Delay,
				NotificationHistory: map[string]int64{},
			},
			wantBroken: true,
			wantStage:  string(activeOverageWarningStage0),
		},
		{
			name: "active overage previous stage must be recent",
			snapshot: storageWarningSnapshot{
				Bucket:             storageWarningBucketActiveOverage,
				ActiveOverageStage: activeOverageWarningStage60,
				EvaluatedAt:        now,
				WarningCycleStart:  now - storageWarningActiveOverageWarning60Delay,
				NotificationHistory: map[string]int64{
					StorageWarningActiveOverageAnchorTemplateID: now - storageWarningActiveOverageWarning60Delay,
					storageWarningActiveOverage30TemplateID:     now - storageWarningPreviousStageFreshnessWindow - 1,
				},
			},
			wantBroken: true,
			wantStage:  string(activeOverageWarningStage30),
		},
		{
			name: "expired previous stage from prior cycle is ignored",
			snapshot: storageWarningSnapshot{
				Bucket:            storageWarningBucketExpired,
				ExpiredStage:      expiredWarningStage30,
				EvaluatedAt:       now,
				EffectiveExpiry:   now - storageWarningExpiredWarning30Delay,
				WarningCycleStart: now - storageWarningExpiredWarning30Delay,
				NotificationHistory: map[string]int64{
					storageWarningExpired0TemplateID: now - storageWarningExpiredWarning30Delay - 1,
				},
			},
			wantBroken: true,
			wantStage:  string(expiredWarningStage0),
		},
		{
			name: "same cycle recent previous stage passes",
			snapshot: storageWarningSnapshot{
				Bucket:            storageWarningBucketExpired,
				ExpiredStage:      expiredWarningStage60,
				EvaluatedAt:       now,
				EffectiveExpiry:   now - storageWarningExpiredWarning60Delay,
				WarningCycleStart: now - storageWarningExpiredWarning60Delay,
				NotificationHistory: map[string]int64{
					storageWarningExpired30TemplateID: now - storageWarningOneDayInMicroseconds,
				},
			},
			wantBroken: false,
		},
		{
			name: "terminal expired stage requires final reminder",
			snapshot: storageWarningSnapshot{
				Bucket:            storageWarningBucketExpired,
				ExpiredStage:      expiredWarningStageScheduledDeletion,
				EvaluatedAt:       now,
				WarningCycleStart: now - storageWarningExpiredDeletionDelay,
				NotificationHistory: map[string]int64{
					storageWarningExpired90TemplateID: now - storageWarningOneDayInMicroseconds,
				},
			},
			wantBroken: true,
			wantStage:  string(expiredWarningStage119),
		},
		{
			name: "expired final reminder requires prior 90-day stage",
			snapshot: storageWarningSnapshot{
				Bucket:              storageWarningBucketExpired,
				ExpiredStage:        expiredWarningStage119,
				EvaluatedAt:         now,
				WarningCycleStart:   now - storageWarningExpiredWarning119Delay,
				NotificationHistory: map[string]int64{},
			},
			wantBroken: true,
			wantStage:  string(expiredWarningStage90),
		},
		{
			name: "expired final reminder passes when prior 90-day stage exists in overdue cycle",
			snapshot: storageWarningSnapshot{
				Bucket:            storageWarningBucketExpired,
				ExpiredStage:      expiredWarningStage119,
				EvaluatedAt:       now,
				WarningCycleStart: now - storageWarningExpiredWarning119Delay,
				NotificationHistory: map[string]int64{
					storageWarningExpired90TemplateID: now - storageWarningOneDayInMicroseconds,
				},
			},
			wantBroken: false,
		},
		{
			name: "buffered expired stage 60 requires initial expired notice",
			snapshot: storageWarningSnapshot{
				Bucket:               storageWarningBucketExpired,
				ExpiredStage:         expiredWarningStage60,
				ExpiredBufferedCycle: true,
				EvaluatedAt:          now,
				WarningCycleStart:    now - (storageWarningExpiredBackfillMinRecoveryDelay / 2),
				NotificationHistory:  map[string]int64{},
			},
			wantBroken: true,
			wantStage:  string(expiredWarningStage0),
		},
		{
			name: "buffered expired final reminder uses the buffered midpoint stage",
			snapshot: storageWarningSnapshot{
				Bucket:               storageWarningBucketExpired,
				ExpiredStage:         expiredWarningStage119,
				ExpiredBufferedCycle: true,
				EvaluatedAt:          now,
				WarningCycleStart:    now - storageWarningExpiredBackfillMinRecoveryDelay + storageWarningOneDayInMicroseconds,
				NotificationHistory: map[string]int64{
					storageWarningExpired60TemplateID: now - storageWarningOneDayInMicroseconds,
				},
			},
			wantBroken: false,
		},
		{
			name: "buffered expired stage 60 allows predecessor older than default window",
			snapshot: storageWarningSnapshot{
				Bucket:               storageWarningBucketExpired,
				ExpiredStage:         expiredWarningStage60,
				ExpiredBufferedCycle: true,
				EvaluatedAt:          148 * storageWarningOneDayInMicroseconds,
				WarningCycleStart:    65 * storageWarningOneDayInMicroseconds,
				AutoDeleteDate:       150 * storageWarningOneDayInMicroseconds,
				NotificationHistory: map[string]int64{
					storageWarningExpired0TemplateID: 107 * storageWarningOneDayInMicroseconds,
				},
			},
			wantBroken: false,
		},
		{
			name: "buffered expired stage 60 tolerates a two-day outage beyond midpoint",
			snapshot: storageWarningSnapshot{
				Bucket:               storageWarningBucketExpired,
				ExpiredStage:         expiredWarningStage60,
				ExpiredBufferedCycle: true,
				EvaluatedAt:          150 * storageWarningOneDayInMicroseconds,
				WarningCycleStart:    65 * storageWarningOneDayInMicroseconds,
				AutoDeleteDate:       150 * storageWarningOneDayInMicroseconds,
				NotificationHistory: map[string]int64{
					storageWarningExpired0TemplateID: 105 * storageWarningOneDayInMicroseconds,
				},
			},
			wantBroken: false,
		},
		{
			name: "buffered expired final reminder allows predecessor older than default window",
			snapshot: storageWarningSnapshot{
				Bucket:               storageWarningBucketExpired,
				ExpiredStage:         expiredWarningStage119,
				ExpiredBufferedCycle: true,
				EvaluatedAt:          150 * storageWarningOneDayInMicroseconds,
				WarningCycleStart:    65 * storageWarningOneDayInMicroseconds,
				AutoDeleteDate:       150 * storageWarningOneDayInMicroseconds,
				NotificationHistory: map[string]int64{
					storageWarningExpired60TemplateID: 108 * storageWarningOneDayInMicroseconds,
				},
			},
			wantBroken: false,
		},
		{
			name: "buffered expired final reminder tolerates a two-day outage beyond final reminder threshold",
			snapshot: storageWarningSnapshot{
				Bucket:               storageWarningBucketExpired,
				ExpiredStage:         expiredWarningStage119,
				ExpiredBufferedCycle: true,
				EvaluatedAt:          152 * storageWarningOneDayInMicroseconds,
				WarningCycleStart:    65 * storageWarningOneDayInMicroseconds,
				AutoDeleteDate:       150 * storageWarningOneDayInMicroseconds,
				NotificationHistory: map[string]int64{
					storageWarningExpired60TemplateID: 108 * storageWarningOneDayInMicroseconds,
				},
			},
			wantBroken: false,
		},
		{
			name: "buffered expired stage 60 still breaks once predecessor is too stale after extra grace",
			snapshot: storageWarningSnapshot{
				Bucket:               storageWarningBucketExpired,
				ExpiredStage:         expiredWarningStage60,
				ExpiredBufferedCycle: true,
				EvaluatedAt:          151 * storageWarningOneDayInMicroseconds,
				WarningCycleStart:    65 * storageWarningOneDayInMicroseconds,
				AutoDeleteDate:       150 * storageWarningOneDayInMicroseconds,
				NotificationHistory: map[string]int64{
					storageWarningExpired0TemplateID: 105 * storageWarningOneDayInMicroseconds,
				},
			},
			wantBroken: true,
			wantStage:  string(expiredWarningStage0),
		},
		{
			name: "buffered expired final reminder still breaks once predecessor is too stale after extra grace",
			snapshot: storageWarningSnapshot{
				Bucket:               storageWarningBucketExpired,
				ExpiredStage:         expiredWarningStage119,
				ExpiredBufferedCycle: true,
				EvaluatedAt:          153 * storageWarningOneDayInMicroseconds,
				WarningCycleStart:    65 * storageWarningOneDayInMicroseconds,
				AutoDeleteDate:       150 * storageWarningOneDayInMicroseconds,
				NotificationHistory: map[string]int64{
					storageWarningExpired60TemplateID: 108 * storageWarningOneDayInMicroseconds,
				},
			},
			wantBroken: true,
			wantStage:  string(expiredWarningStage60),
		},
		{
			name: "terminal active overage stage requires final reminder",
			snapshot: storageWarningSnapshot{
				Bucket:             storageWarningBucketActiveOverage,
				ActiveOverageStage: activeOverageWarningStageScheduledDeletion,
				EvaluatedAt:        now,
				WarningCycleStart:  now - storageWarningActiveOverageDeletionDelay,
				NotificationHistory: map[string]int64{
					storageWarningActiveOverage60TemplateID: now - storageWarningOneDayInMicroseconds,
				},
			},
			wantBroken: true,
			wantStage:  string(activeOverageWarningStage89),
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			broken, alert := storageWarningCadenceBroken(tc.snapshot)
			if broken != tc.wantBroken {
				t.Fatalf("unexpected cadence result: got %v want %v", broken, tc.wantBroken)
			}
			if tc.wantBroken && !strings.Contains(alert, "previous_required_stage="+tc.wantStage) {
				t.Fatalf("expected alert to include previous stage %q, got %q", tc.wantStage, alert)
			}
		})
	}
}

func TestStorageWarningPreviousStageFreshnessWindowForSnapshot(t *testing.T) {
	buffered60Snapshot := storageWarningSnapshot{
		Bucket:               storageWarningBucketExpired,
		ExpiredStage:         expiredWarningStage60,
		ExpiredBufferedCycle: true,
		WarningCycleStart:    65 * storageWarningOneDayInMicroseconds,
		AutoDeleteDate:       150 * storageWarningOneDayInMicroseconds,
	}
	got := storageWarningPreviousStageFreshnessWindowForSnapshot(buffered60Snapshot)
	want := expiredBufferedWarning60At(buffered60Snapshot.WarningCycleStart, buffered60Snapshot.AutoDeleteDate) -
		buffered60Snapshot.WarningCycleStart + storageWarningOneDayInMicroseconds + storageWarningBufferedCadenceExtraGrace
	if got != want {
		t.Fatalf("unexpected buffered stage 60 freshness window: got %d want %d", got, want)
	}

	buffered119Snapshot := storageWarningSnapshot{
		Bucket:               storageWarningBucketExpired,
		ExpiredStage:         expiredWarningStage119,
		ExpiredBufferedCycle: true,
		WarningCycleStart:    65 * storageWarningOneDayInMicroseconds,
		AutoDeleteDate:       150 * storageWarningOneDayInMicroseconds,
	}
	got = storageWarningPreviousStageFreshnessWindowForSnapshot(buffered119Snapshot)
	want = expiredBufferedWarning119At(buffered119Snapshot.AutoDeleteDate) -
		expiredBufferedWarning60At(buffered119Snapshot.WarningCycleStart, buffered119Snapshot.AutoDeleteDate) +
		storageWarningOneDayInMicroseconds + storageWarningBufferedCadenceExtraGrace
	if got != want {
		t.Fatalf("unexpected buffered stage 119 freshness window: got %d want %d", got, want)
	}

	standardSnapshot := storageWarningSnapshot{
		Bucket:       storageWarningBucketExpired,
		ExpiredStage: expiredWarningStage60,
	}
	got = storageWarningPreviousStageFreshnessWindowForSnapshot(standardSnapshot)
	if got != storageWarningPreviousStageFreshnessWindow {
		t.Fatalf("unexpected standard freshness window: got %d want %d", got, storageWarningPreviousStageFreshnessWindow)
	}
}

func TestBuildStorageWarningCadenceAlert(t *testing.T) {
	snapshot := storageWarningSnapshot{
		RecipientID:     123,
		Bucket:          storageWarningBucketExpired,
		ExpiredStage:    expiredWarningStage90,
		TotalUsage:      75,
		AllottedStorage: 10,
		EffectiveExpiry: 1,
	}

	got := buildStorageWarningCadenceAlert(snapshot, string(expiredWarningStage60), 0)
	for _, want := range []string{
		"recipient_id=123",
		"bucket=expired",
		"intended_stage=expired_90d",
		"previous_required_stage=expired_60d",
		"previous_sent_time=missing",
		"total_usage=75",
		"allotted_storage=10",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("expected alert to contain %q, got %q", want, got)
		}
	}
}

func TestStorageWarningNotificationGroup(t *testing.T) {
	if got := storageWarningNotificationGroup(storageWarningBucketActiveOverage); got != storageWarningActiveOverageNotificationGroup {
		t.Fatalf("unexpected active overage notification group: got %q want %q", got, storageWarningActiveOverageNotificationGroup)
	}
	if got := storageWarningNotificationGroup(storageWarningBucketExpired); got != storageWarningExpiredNotificationGroup {
		t.Fatalf("unexpected expired notification group: got %q want %q", got, storageWarningExpiredNotificationGroup)
	}
	if got := storageWarningNotificationGroup(storageWarningBucketNone); got != "" {
		t.Fatalf("unexpected notification group for none bucket: got %q want empty", got)
	}
}

func TestMergeStorageWarningCandidatesDeduplicatesAndKeepsFamilyPlan(t *testing.T) {
	candidates := mergeStorageWarningCandidates(
		[]repo.StorageWarningCandidate{
			{RecipientID: 1, IsFamilyPlan: false},
			{RecipientID: 2, IsFamilyPlan: true},
		},
		[]repo.StorageWarningCandidate{
			{RecipientID: 1, IsFamilyPlan: true},
			{RecipientID: 3, IsFamilyPlan: false},
		},
	)

	if len(candidates) != 3 {
		t.Fatalf("expected 3 merged candidates, got %d", len(candidates))
	}
	if candidates[0].RecipientID != 1 || !candidates[0].IsFamilyPlan {
		t.Fatalf("unexpected first candidate: %+v", candidates[0])
	}
	if candidates[1].RecipientID != 2 || !candidates[1].IsFamilyPlan {
		t.Fatalf("unexpected second candidate: %+v", candidates[1])
	}
	if candidates[2].RecipientID != 3 || candidates[2].IsFamilyPlan {
		t.Fatalf("unexpected third candidate: %+v", candidates[2])
	}
}

func TestStorageWarningShouldPreserveActiveOverageHistory(t *testing.T) {
	if !storageWarningShouldPreserveActiveOverageHistory(storageWarningSnapshot{CurrentBucket: storageWarningBucketActiveOverage, Bucket: storageWarningBucketNone}) {
		t.Fatal("expected active overage history to be preserved even when no stage is due")
	}
	if storageWarningShouldPreserveActiveOverageHistory(storageWarningSnapshot{
		CurrentBucket:       storageWarningBucketActiveOverage,
		WarningCycleStart:   100,
		NotificationHistory: map[string]int64{repo.StorageWarningActiveOverageScheduledDeletionTemplateID: 100},
	}) {
		t.Fatal("expected active overage history to be dropped after scheduled deletion")
	}
	if storageWarningShouldPreserveActiveOverageHistory(storageWarningSnapshot{CurrentBucket: storageWarningBucketExpired}) {
		t.Fatal("expected expired snapshot to not preserve active overage history")
	}
}

func TestStorageWarningTemplateDetailsExpired(t *testing.T) {
	snapshot := storageWarningSnapshot{
		Bucket:       storageWarningBucketExpired,
		ExpiredStage: expiredWarningStage90,
	}
	templateID, templateName, subject, ok := storageWarningTemplateDetails(snapshot)
	if !ok {
		t.Fatal("expected expired bucket template details")
	}
	if templateID != storageWarningExpired90TemplateID || templateName != storageWarningExpiredTemplate || subject != storageWarningExpired90Subject {
		t.Fatalf("unexpected expired template details: %q %q %q", templateID, templateName, subject)
	}
}

func TestStorageWarningTemplateDetailsScheduledDeletion(t *testing.T) {
	expiredSnapshot := storageWarningSnapshot{
		Bucket:       storageWarningBucketExpired,
		ExpiredStage: expiredWarningStageScheduledDeletion,
	}
	templateID, templateName, subject, ok := storageWarningTemplateDetails(expiredSnapshot)
	if !ok {
		t.Fatal("expected expired scheduled deletion template details")
	}
	if templateID != repo.StorageWarningExpiredScheduledDeletionTemplateID || templateName != storageWarningExpiredScheduledDeletionTemplate || subject != storageWarningExpiredScheduledDeletionSubject {
		t.Fatalf("unexpected expired scheduled deletion template details: %q %q %q", templateID, templateName, subject)
	}

	activeSnapshot := storageWarningSnapshot{
		Bucket:             storageWarningBucketActiveOverage,
		ActiveOverageStage: activeOverageWarningStageScheduledDeletion,
	}
	templateID, templateName, subject, ok = storageWarningTemplateDetails(activeSnapshot)
	if !ok {
		t.Fatal("expected active overage scheduled deletion template details")
	}
	if templateID != repo.StorageWarningActiveOverageScheduledDeletionTemplateID || templateName != storageWarningActiveOverageScheduledDeletionTemplate || subject != storageWarningActiveOverageScheduledDeletionSubject {
		t.Fatalf("unexpected active overage scheduled deletion template details: %q %q %q", templateID, templateName, subject)
	}
}

func TestStorageWarningTemplateDetailsActiveOverage(t *testing.T) {
	snapshot := storageWarningSnapshot{
		Bucket:             storageWarningBucketActiveOverage,
		ActiveOverageStage: activeOverageWarningStage60,
	}
	templateID, templateName, subject, ok := storageWarningTemplateDetails(snapshot)
	if !ok {
		t.Fatal("expected active overage template details")
	}
	if templateID != storageWarningActiveOverage60TemplateID || templateName != storageWarningActiveOverageTemplate || subject != storageWarningActiveOverage60Subject {
		t.Fatalf("unexpected active overage template details: %q %q %q", templateID, templateName, subject)
	}
}

func TestProcessStorageWarningSnapshotScheduledDeletionSkipsResetWhenEmailFails(t *testing.T) {
	originalSendStorageWarningTemplatedEmail := sendStorageWarningTemplatedEmail
	originalPersistStorageWarningHistory := persistStorageWarningHistory
	defer func() {
		sendStorageWarningTemplatedEmail = originalSendStorageWarningTemplatedEmail
		persistStorageWarningHistory = originalPersistStorageWarningHistory
	}()

	sendStorageWarningTemplatedEmail = func(_ []string, _ string, _ string, _ string, _ string, _ string, _ map[string]interface{}, _ []map[string]interface{}) error {
		return errors.New("boom")
	}
	persistStorageWarningHistory = func(_ *repo.NotificationHistoryRepository, _ storageWarningSnapshot, _ string) error {
		t.Fatal("did not expect history persistence when email send fails")
		return nil
	}

	resetter := &recordingUserAccessResetter{}
	snapshot := storageWarningSnapshot{
		RecipientID:      12345,
		AccountEmail:     "user@ente.com",
		TotalUsage:       storageWarningOverageThreshold + 10,
		AllottedStorage:  0,
		AvailableStorage: -10,
		Bucket:           storageWarningBucketExpired,
		ExpiredStage:     expiredWarningStageScheduledDeletion,
		EffectiveExpiry:  1,
		NotificationHistory: map[string]int64{
			storageWarningExpired119TemplateID: 1,
		},
	}

	result, err := (&EmailNotificationController{UserAccessResetter: resetter}).processStorageWarningSnapshot(t.Context(), snapshot)
	if err == nil {
		t.Fatal("expected email failure to be returned")
	}
	if result != storageWarningProcessResultSkipped {
		t.Fatalf("unexpected result: got %q want %q", result, storageWarningProcessResultSkipped)
	}
	if resetter.callCount != 0 {
		t.Fatalf("expected no access reset when email send fails, got %d resets", resetter.callCount)
	}
}

func TestProcessStorageWarningSnapshotScheduledDeletionResetsAccessAfterEmail(t *testing.T) {
	originalSendStorageWarningTemplatedEmail := sendStorageWarningTemplatedEmail
	originalPersistStorageWarningHistory := persistStorageWarningHistory
	defer func() {
		sendStorageWarningTemplatedEmail = originalSendStorageWarningTemplatedEmail
		persistStorageWarningHistory = originalPersistStorageWarningHistory
	}()

	callOrder := []string{}
	sendStorageWarningTemplatedEmail = func(_ []string, _ string, _ string, _ string, _ string, _ string, _ map[string]interface{}, _ []map[string]interface{}) error {
		callOrder = append(callOrder, "send")
		return nil
	}
	persistStorageWarningHistory = func(_ *repo.NotificationHistoryRepository, _ storageWarningSnapshot, _ string) error {
		callOrder = append(callOrder, "persist")
		return nil
	}

	resetter := &recordingUserAccessResetter{callOrder: &callOrder}
	snapshot := storageWarningSnapshot{
		RecipientID:      12345,
		AccountEmail:     "user@ente.com",
		TotalUsage:       storageWarningOverageThreshold + 10,
		AllottedStorage:  0,
		AvailableStorage: -10,
		Bucket:           storageWarningBucketExpired,
		ExpiredStage:     expiredWarningStageScheduledDeletion,
		EffectiveExpiry:  1,
		NotificationHistory: map[string]int64{
			storageWarningExpired119TemplateID: 1,
		},
	}

	result, err := (&EmailNotificationController{UserAccessResetter: resetter}).processStorageWarningSnapshot(t.Context(), snapshot)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result != storageWarningProcessResultSent {
		t.Fatalf("unexpected result: got %q want %q", result, storageWarningProcessResultSent)
	}
	if resetter.callCount != 1 {
		t.Fatalf("expected one access reset after successful email, got %d", resetter.callCount)
	}
	if got, want := strings.Join(callOrder, ","), "send,reset,persist"; got != want {
		t.Fatalf("unexpected call order: got %q want %q", got, want)
	}
}

func TestProcessStorageWarningSnapshotScheduledDeletionSkipsDuringActiveLoginGrace(t *testing.T) {
	originalSendStorageWarningTemplatedEmail := sendStorageWarningTemplatedEmail
	originalPersistStorageWarningHistory := persistStorageWarningHistory
	defer func() {
		sendStorageWarningTemplatedEmail = originalSendStorageWarningTemplatedEmail
		persistStorageWarningHistory = originalPersistStorageWarningHistory
	}()

	sendStorageWarningTemplatedEmail = func(_ []string, _ string, _ string, _ string, _ string, _ string, _ map[string]interface{}, _ []map[string]interface{}) error {
		t.Fatal("did not expect email send during active login grace")
		return nil
	}
	persistStorageWarningHistory = func(_ *repo.NotificationHistoryRepository, _ storageWarningSnapshot, _ string) error {
		t.Fatal("did not expect history persistence during active login grace")
		return nil
	}

	now := int64(10) * storageWarningOneDayInMicroseconds
	graceSentAt := now - storageWarningOneDayInMicroseconds
	resetter := &recordingUserAccessResetter{}
	snapshot := storageWarningSnapshot{
		RecipientID:       12345,
		AccountEmail:      "user@example.com",
		TotalUsage:        storageWarningOverageThreshold + 10,
		AllottedStorage:   0,
		AvailableStorage:  -10,
		Bucket:            storageWarningBucketExpired,
		ExpiredStage:      expiredWarningStageScheduledDeletion,
		EffectiveExpiry:   1,
		EvaluatedAt:       now,
		WarningCycleStart: graceSentAt - storageWarningOneDayInMicroseconds,
		NotificationHistory: map[string]int64{
			storageWarningExpired119TemplateID:      graceSentAt - storageWarningOneDayInMicroseconds,
			repo.StorageWarningLoginGraceTemplateID: graceSentAt,
		},
	}

	result, err := (&EmailNotificationController{UserAccessResetter: resetter}).processStorageWarningSnapshot(t.Context(), snapshot)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result != storageWarningProcessResultSkipped {
		t.Fatalf("unexpected result: got %q want %q", result, storageWarningProcessResultSkipped)
	}
	if resetter.callCount != 0 {
		t.Fatalf("expected no access reset during active login grace, got %d resets", resetter.callCount)
	}
}

func TestProcessStorageWarningSnapshotSkipsActiveOverageRestartDuringActiveLoginGrace(t *testing.T) {
	originalSendStorageWarningTemplatedEmail := sendStorageWarningTemplatedEmail
	originalPersistStorageWarningHistory := persistStorageWarningHistory
	defer func() {
		sendStorageWarningTemplatedEmail = originalSendStorageWarningTemplatedEmail
		persistStorageWarningHistory = originalPersistStorageWarningHistory
	}()

	sendStorageWarningTemplatedEmail = func(_ []string, _ string, _ string, _ string, _ string, _ string, _ map[string]interface{}, _ []map[string]interface{}) error {
		t.Fatal("did not expect warning email during active login grace")
		return nil
	}
	persistStorageWarningHistory = func(_ *repo.NotificationHistoryRepository, _ storageWarningSnapshot, _ string) error {
		t.Fatal("did not expect history persistence during active login grace")
		return nil
	}

	now := int64(10) * storageWarningOneDayInMicroseconds
	graceSentAt := now - storageWarningOneDayInMicroseconds
	resetter := &recordingUserAccessResetter{}
	snapshot := storageWarningSnapshot{
		RecipientID:         12345,
		AccountEmail:        "user@ente.com",
		TotalUsage:          storageWarningOverageThreshold + 10,
		AllottedStorage:     0,
		AvailableStorage:    -10,
		Bucket:              storageWarningBucketActiveOverage,
		ActiveOverageStage:  activeOverageWarningStage0,
		EvaluatedAt:         now,
		WarningCycleStart:   now,
		NotificationHistory: map[string]int64{repo.StorageWarningLoginGraceTemplateID: graceSentAt},
	}

	result, err := (&EmailNotificationController{UserAccessResetter: resetter}).processStorageWarningSnapshot(t.Context(), snapshot)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result != storageWarningProcessResultSkipped {
		t.Fatalf("unexpected result: got %q want %q", result, storageWarningProcessResultSkipped)
	}
	if resetter.callCount != 0 {
		t.Fatalf("expected no access reset during active login grace, got %d resets", resetter.callCount)
	}
}

func TestProcessStorageWarningSnapshotScheduledDeletionAllowsExpiredLoginGraceDespiteStaleCadence(t *testing.T) {
	originalSendStorageWarningTemplatedEmail := sendStorageWarningTemplatedEmail
	originalPersistStorageWarningHistory := persistStorageWarningHistory
	defer func() {
		sendStorageWarningTemplatedEmail = originalSendStorageWarningTemplatedEmail
		persistStorageWarningHistory = originalPersistStorageWarningHistory
	}()

	callOrder := []string{}
	sendStorageWarningTemplatedEmail = func(_ []string, _ string, _ string, _ string, _ string, _ string, _ map[string]interface{}, _ []map[string]interface{}) error {
		callOrder = append(callOrder, "send")
		return nil
	}
	persistStorageWarningHistory = func(_ *repo.NotificationHistoryRepository, _ storageWarningSnapshot, _ string) error {
		callOrder = append(callOrder, "persist")
		return nil
	}

	graceSentAt := int64(40) * storageWarningOneDayInMicroseconds
	now := graceSentAt + repo.StorageWarningLoginGraceDurationMicroseconds + 1
	resetter := &recordingUserAccessResetter{callOrder: &callOrder}
	snapshot := storageWarningSnapshot{
		RecipientID:       12345,
		AccountEmail:      "user@ente.com",
		TotalUsage:        storageWarningOverageThreshold + 10,
		AllottedStorage:   0,
		AvailableStorage:  -10,
		Bucket:            storageWarningBucketExpired,
		ExpiredStage:      expiredWarningStageScheduledDeletion,
		EffectiveExpiry:   1,
		EvaluatedAt:       now,
		WarningCycleStart: 1,
		NotificationHistory: map[string]int64{
			storageWarningExpired119TemplateID:      1,
			repo.StorageWarningLoginGraceTemplateID: graceSentAt,
		},
	}

	result, err := (&EmailNotificationController{UserAccessResetter: resetter}).processStorageWarningSnapshot(t.Context(), snapshot)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result != storageWarningProcessResultSent {
		t.Fatalf("unexpected result: got %q want %q", result, storageWarningProcessResultSent)
	}
	if resetter.callCount != 1 {
		t.Fatalf("expected one access reset after login grace expiry, got %d", resetter.callCount)
	}
	if got, want := strings.Join(callOrder, ","), "send,reset,persist"; got != want {
		t.Fatalf("unexpected call order: got %q want %q", got, want)
	}
}

func TestProcessStorageWarningSnapshotExpiredLoginGraceReblocksActiveOverageRestart(t *testing.T) {
	originalSendStorageWarningTemplatedEmail := sendStorageWarningTemplatedEmail
	originalPersistStorageWarningHistory := persistStorageWarningHistory
	defer func() {
		sendStorageWarningTemplatedEmail = originalSendStorageWarningTemplatedEmail
		persistStorageWarningHistory = originalPersistStorageWarningHistory
	}()

	callOrder := []string{}
	sendStorageWarningTemplatedEmail = func(_ []string, _ string, _ string, _ string, _ string, templateName string, _ map[string]interface{}, _ []map[string]interface{}) error {
		callOrder = append(callOrder, "send")
		if templateName != storageWarningActiveOverageScheduledDeletionTemplate {
			t.Fatalf("unexpected template: got %q want %q", templateName, storageWarningActiveOverageScheduledDeletionTemplate)
		}
		return nil
	}
	var persistedTemplateID string
	persistStorageWarningHistory = func(_ *repo.NotificationHistoryRepository, _ storageWarningSnapshot, templateID string) error {
		callOrder = append(callOrder, "persist")
		persistedTemplateID = templateID
		return nil
	}

	graceSentAt := int64(40) * storageWarningOneDayInMicroseconds
	now := graceSentAt + repo.StorageWarningLoginGraceDurationMicroseconds + 1
	resetter := &recordingUserAccessResetter{callOrder: &callOrder}
	snapshot := storageWarningSnapshot{
		RecipientID:         12345,
		AccountEmail:        "user@ente.com",
		TotalUsage:          storageWarningOverageThreshold + 10,
		AllottedStorage:     0,
		AvailableStorage:    -10,
		Bucket:              storageWarningBucketActiveOverage,
		ActiveOverageStage:  activeOverageWarningStage0,
		EvaluatedAt:         now,
		WarningCycleStart:   now,
		NotificationHistory: map[string]int64{repo.StorageWarningLoginGraceTemplateID: graceSentAt},
	}

	result, err := (&EmailNotificationController{UserAccessResetter: resetter}).processStorageWarningSnapshot(t.Context(), snapshot)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result != storageWarningProcessResultSent {
		t.Fatalf("unexpected result: got %q want %q", result, storageWarningProcessResultSent)
	}
	if resetter.callCount != 1 {
		t.Fatalf("expected one access reset after login grace expiry, got %d", resetter.callCount)
	}
	if persistedTemplateID != repo.StorageWarningActiveOverageScheduledDeletionTemplateID {
		t.Fatalf("unexpected persisted template: got %q want %q", persistedTemplateID, repo.StorageWarningActiveOverageScheduledDeletionTemplateID)
	}
	if got, want := strings.Join(callOrder, ","), "send,reset,persist"; got != want {
		t.Fatalf("unexpected call order: got %q want %q", got, want)
	}
}

func TestProcessStorageWarningSnapshotClearsLoginGraceAfterRecovery(t *testing.T) {
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	const userID int64 = 12348
	testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       userID,
		Email:        "user@example.com",
		CreationTime: 1,
	})
	graceSentAt := int64(40) * storageWarningOneDayInMicroseconds
	testutil.InsertNotificationHistory(t, db, testutil.NotificationHistoryFixture{
		UserID:     userID,
		TemplateID: repo.StorageWarningLoginGraceTemplateID,
		SentTime:   graceSentAt,
	})
	testutil.InsertNotificationHistory(t, db, testutil.NotificationHistoryFixture{
		UserID:     userID,
		TemplateID: repo.StorageWarningExpiredScheduledDeletionTemplateID,
		SentTime:   graceSentAt + 1,
	})

	notificationHistoryRepo := &repo.NotificationHistoryRepository{DB: db}
	result, err := (&EmailNotificationController{
		NotificationHistoryRepo: notificationHistoryRepo,
	}).processStorageWarningSnapshot(t.Context(), storageWarningSnapshot{
		RecipientID: userID,
		Bucket:      storageWarningBucketNone,
		EvaluatedAt: graceSentAt + storageWarningOneDayInMicroseconds,
		NotificationHistory: map[string]int64{
			repo.StorageWarningLoginGraceTemplateID: graceSentAt,
		},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result != storageWarningProcessResultSkipped {
		t.Fatalf("unexpected result: got %q want %q", result, storageWarningProcessResultSkipped)
	}
	graceSentAfterClear, err := notificationHistoryRepo.GetLastNotificationTime(userID, repo.StorageWarningLoginGraceTemplateID)
	if err != nil {
		t.Fatalf("failed to fetch login grace after recovery: %v", err)
	}
	if graceSentAfterClear != 0 {
		t.Fatalf("expected login grace to be cleared after recovery, got sent_time %d", graceSentAfterClear)
	}
	terminalRowExists, err := notificationHistoryRepo.IsStorageWarningDeletionScheduled(userID)
	if err != nil {
		t.Fatalf("failed to fetch terminal row after recovery: %v", err)
	}
	if terminalRowExists {
		t.Fatal("expected stale terminal row to be cleared after recovery")
	}
}

func TestBuildStorageWarningRunSummary(t *testing.T) {
	stats := newStorageWarningRunStats()
	stats.ProcessedUsers = 42
	stats.SentEmails = 3
	stats.SuccessByStage[string(expiredWarningStage0)] = 1
	stats.SuccessByStage[string(activeOverageWarningStage0)] = 2
	stats.FailureByStage[string(activeOverageWarningStage60)] = 1
	stats.SkippedRolloutByStage[string(expiredWarningStage30)] = 39
	stats.PreStageFailures = 4
	stats.SkippedRolloutPct = 39

	got := buildStorageWarningRunSummary(stats, 0)
	want := "Storage warning run summary (1970-01-01T00:00:00Z): processed=42 | sent=3 | success={expired_0d=1, active_overage_0d=2} | failures={active_overage_60d=1} | skipped_rollout={expired_30d=39} | pre_stage_failures=4 | skipped_rollout_percentage=39 | rollout_percentage=100"
	if got != want {
		t.Fatalf("unexpected summary:\n got: %s\nwant: %s", got, want)
	}
}

func TestStorageWarningHistoryGroup(t *testing.T) {
	if got := storageWarningHistoryGroup(storageWarningSnapshot{
		Bucket:             storageWarningBucketActiveOverage,
		ActiveOverageStage: activeOverageWarningStage60,
	}); got != storageWarningActiveOverageNotificationGroup {
		t.Fatalf("unexpected active overage history group: got %q want %q", got, storageWarningActiveOverageNotificationGroup)
	}
	if got := storageWarningHistoryGroup(storageWarningSnapshot{
		Bucket:       storageWarningBucketExpired,
		ExpiredStage: expiredWarningStageScheduledDeletion,
	}); got != "" {
		t.Fatalf("unexpected terminal history group: got %q want empty", got)
	}
}

func TestStorageWarningShouldResetUserAccess(t *testing.T) {
	if !storageWarningShouldResetUserAccess(storageWarningSnapshot{
		Bucket:       storageWarningBucketExpired,
		ExpiredStage: expiredWarningStageScheduledDeletion,
	}) {
		t.Fatal("expected expired scheduled deletion stage to reset access")
	}
	if !storageWarningShouldResetUserAccess(storageWarningSnapshot{
		Bucket:             storageWarningBucketActiveOverage,
		ActiveOverageStage: activeOverageWarningStageScheduledDeletion,
	}) {
		t.Fatal("expected active overage scheduled deletion stage to reset access")
	}
	if storageWarningShouldResetUserAccess(storageWarningSnapshot{
		Bucket:             storageWarningBucketActiveOverage,
		ActiveOverageStage: activeOverageWarningStage89,
	}) {
		t.Fatal("expected non-terminal stage to not reset access")
	}
}

func TestIsInStorageWarningRollout(t *testing.T) {
	const userID int64 = 12345

	if !isInStorageWarningRollout(userID, "alerts@ente.io") {
		t.Fatal("expected @ente.io account to always be in rollout")
	}
	if !isInStorageWarningRollout(userID, " ALERTS@ENTE.COM ") {
		t.Fatal("expected normalized @ente.com account to always be in rollout")
	}

	want := rollout.IsInPercentageRollout(userID, storageWarningRolloutNonce, storageWarningRolloutPercentage)
	got := isInStorageWarningRollout(userID, "user@example.com")
	if got != want {
		t.Fatalf("unexpected percentage rollout decision: got %v want %v", got, want)
	}
}
