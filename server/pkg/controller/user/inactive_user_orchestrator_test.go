package user

import (
	"strings"
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

func TestHasAnyStageSuccess(t *testing.T) {
	stats := newInactiveUserRunStats()
	if hasAnyStageSuccess(stats.SuccessByStage) {
		t.Fatal("expected no stage success")
	}

	stats.SuccessByStage[inactivityEmailStageWarn7d] = 1
	if !hasAnyStageSuccess(stats.SuccessByStage) {
		t.Fatal("expected stage success to be detected")
	}
}

func TestHasInactiveUserRunSummaryActivity(t *testing.T) {
	stats := newInactiveUserRunStats()
	if hasInactiveUserRunSummaryActivity(stats) {
		t.Fatal("expected no summary activity")
	}

	stats.PausedLegacyContact = 1
	if !hasInactiveUserRunSummaryActivity(stats) {
		t.Fatal("expected paused legacy contact to count as summary activity")
	}

	stats.PausedLegacyContact = 0
	stats.SuccessByStage[inactivityEmailStageWarn2m] = 1
	if !hasInactiveUserRunSummaryActivity(stats) {
		t.Fatal("expected stage success to count as summary activity")
	}
}

func TestBuildInactiveUserRunSummary(t *testing.T) {
	stats := newInactiveUserRunStats()
	stats.ProcessedUsers = 12
	stats.SentEmails = 3
	stats.SuccessByStage[inactivityEmailStageWarn2m] = 2
	stats.SuccessByStage[inactivityEmailStageWarn1m] = 1
	stats.FailureByStage[inactivityEmailStageWarn7d] = 4
	stats.PreStageFailures = 2
	stats.PausedLegacyContact = 6

	summary := buildInactiveUserRunSummary(stats, 0)

	mustContain := []string{
		"Inactive user run summary (1970-01-01T00:00:00Z)",
		"processed=12",
		"sent=3",
		"success={warn_2m=2, warn_1m=1}",
		"failures={warn_7d=4}",
		"pre_stage_failures=2",
		"paused_legacy_contact=6",
	}

	for _, fragment := range mustContain {
		if !strings.Contains(summary, fragment) {
			t.Fatalf("summary missing fragment %q: %s", fragment, summary)
		}
	}

	mustNotContain := []string{
		"warn_7d=0",
		"warn_1d=0",
		"confirm_13m=0",
		"warn_2m=0",
		"warn_1m=0",
		"sent=0",
		"pre_stage_failures=0",
	}
	for _, fragment := range mustNotContain {
		if strings.Contains(summary, fragment) {
			t.Fatalf("summary contains zero-value fragment %q: %s", fragment, summary)
		}
	}
}

func TestBuildInactiveUserRunSummaryForPausedOnlyRun(t *testing.T) {
	stats := newInactiveUserRunStats()
	stats.ProcessedUsers = 12
	stats.PausedLegacyContact = 2

	summary := buildInactiveUserRunSummary(stats, 0)
	want := "Inactive user run summary (1970-01-01T00:00:00Z): processed=12 | paused_legacy_contact=2"
	if summary != want {
		t.Fatalf("unexpected summary: got %q want %q", summary, want)
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
