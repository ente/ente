package user

import (
	"testing"

	"github.com/ente/museum/pkg/repo"
)

func TestNextInactivityEmailStage(t *testing.T) {
	day := int64(24 * 60 * 60 * 1000 * 1000)
	now := int64(500 * day)
	lastActivity := now - inactiveUserWarn2MonthsInMicroSeconds

	tests := []struct {
		name         string
		lastActivity int64
		now          int64
		history      map[string]int64
		want         inactivityEmailStage
	}{
		{
			name:         "no stage before 2 month threshold",
			lastActivity: now - inactiveUserWarn2MonthsInMicroSeconds + day,
			now:          now,
			history:      map[string]int64{},
			want:         inactivityEmailStageNone,
		},
		{
			name:         "first stage at 2 months before deletion",
			lastActivity: lastActivity,
			now:          now,
			history:      map[string]int64{},
			want:         inactivityEmailStageWarn2m,
		},
		{
			name:         "second stage waits for replay gap",
			lastActivity: lastActivity,
			now:          now + inactiveUserGap2mTo1m - day,
			history: map[string]int64{
				InactiveUserDeletionWarn2mTemplateID: now,
			},
			want: inactivityEmailStageNone,
		},
		{
			name:         "second stage after replay gap",
			lastActivity: lastActivity,
			now:          now + inactiveUserGap2mTo1m,
			history: map[string]int64{
				InactiveUserDeletionWarn2mTemplateID: now,
			},
			want: inactivityEmailStageWarn1m,
		},
		{
			name:         "third stage after second stage gap",
			lastActivity: lastActivity,
			now:          now + inactiveUserGap1mTo7d,
			history: map[string]int64{
				InactiveUserDeletionWarn2mTemplateID: now - 100,
				InactiveUserDeletionWarn1mTemplateID: now,
			},
			want: inactivityEmailStageWarn7d,
		},
		{
			name:         "fourth stage after third stage gap",
			lastActivity: lastActivity,
			now:          now + inactiveUserGap7dTo1d,
			history: map[string]int64{
				InactiveUserDeletionWarn2mTemplateID: now - 100,
				InactiveUserDeletionWarn1mTemplateID: now - 50,
				InactiveUserDeletionWarn7dTemplateID: now,
			},
			want: inactivityEmailStageWarn1d,
		},
		{
			name:         "final stage after fourth stage gap",
			lastActivity: lastActivity,
			now:          now + inactiveUserGap1dToFinal,
			history: map[string]int64{
				InactiveUserDeletionWarn2mTemplateID: now - 100,
				InactiveUserDeletionWarn1mTemplateID: now - 50,
				InactiveUserDeletionWarn7dTemplateID: now - 10,
				InactiveUserDeletionWarn1dTemplateID: now,
			},
			want: inactivityEmailStageFinal,
		},
		{
			name:         "stop after final stage in same activity cycle",
			lastActivity: lastActivity,
			now:          now + (10 * day),
			history: map[string]int64{
				InactiveUserDeletionWarn2mTemplateID: now - 1000,
				InactiveUserDeletionFinalTemplateID:  now - 100,
			},
			want: inactivityEmailStageNone,
		},
		{
			name:         "activity reset starts a new cycle",
			lastActivity: now - inactiveUserWarn2MonthsInMicroSeconds,
			now:          now,
			history: map[string]int64{
				InactiveUserDeletionWarn2mTemplateID: now - inactiveUserWarn2MonthsInMicroSeconds - day,
			},
			want: inactivityEmailStageWarn2m,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := nextInactivityEmailStage(tc.lastActivity, tc.now, tc.history)
			if got != tc.want {
				t.Fatalf("unexpected stage: got %q want %q", got, tc.want)
			}
		})
	}
}

func TestProcessCandidateBatchRecoversPanics(t *testing.T) {
	orchestrator := &InactiveUserOrchestrator{}
	candidates := []repo.UserInactivityCandidate{
		{
			UserID:       42,
			LastActivity: 0,
		},
	}

	results := orchestrator.processCandidateBatch(candidates, 0, nil)
	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}

	result := results[0]
	if result.UserID != 42 {
		t.Fatalf("unexpected user id in result: %d", result.UserID)
	}
	if result.Sent {
		t.Fatal("expected sent=false for panic recovery path")
	}
	if result.Stage != inactivityEmailStageNone {
		t.Fatalf("expected stage none for panic recovery path, got %q", result.Stage)
	}
	if result.Err == nil {
		t.Fatal("expected error result for panic recovery path")
	}
}
