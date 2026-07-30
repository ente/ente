package email

import (
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/time"
)

const (
	StorageWarningActiveOverageAnchorTemplateID          = "storage_warning_active_overage"
	storageWarningActiveOverageTemplate                  = "storage-warning/storage_warning_active_overage.html"
	storageWarningActiveOverageScheduledDeletionTemplate = "storage-warning/storage_warning_active_overage_scheduled_deletion.html"
	storageWarningActiveOverageDeletionDelay             = 90 * 24 * time.MicroSecondsInOneHour
	storageWarningActiveOverageWarning30Delay            = 30 * 24 * time.MicroSecondsInOneHour
	storageWarningActiveOverageWarning60Delay            = 60 * 24 * time.MicroSecondsInOneHour
	storageWarningActiveOverageWarning89Delay            = 89 * 24 * time.MicroSecondsInOneHour
	storageWarningActiveOverage30TemplateID              = "storage_warning_active_overage_30d"
	storageWarningActiveOverage60TemplateID              = "storage_warning_active_overage_60d"
	storageWarningActiveOverage89TemplateID              = "storage_warning_active_overage_89d"
	storageWarningActiveOverage0Subject                  = "Action needed: Reduce usage or upgrade your Ente plan"
	storageWarningActiveOverage30Subject                 = "Reminder: Your Ente data is scheduled for deletion due to overusage"
	storageWarningActiveOverage60Subject                 = "30-day reminder: Your Ente data will be deleted in 30 days due to overusage"
	storageWarningActiveOverage89Subject                 = "Final reminder: Your Ente data will be deleted tomorrow due to overusage"
	storageWarningActiveOverageScheduledDeletionSubject  = "Your Ente data is scheduled for deletion due to overusage"
)

type activeOverageWarningStage string

const (
	activeOverageWarningStageNone              activeOverageWarningStage = "none"
	activeOverageWarningStage0                 activeOverageWarningStage = "active_overage_0d"
	activeOverageWarningStage30                activeOverageWarningStage = "active_overage_30d"
	activeOverageWarningStage60                activeOverageWarningStage = "active_overage_60d"
	activeOverageWarningStage89                activeOverageWarningStage = "active_overage_89d"
	activeOverageWarningStageScheduledDeletion activeOverageWarningStage = "active_overage_scheduled_deletion"
)

type activeOverageWarningResolution struct {
	Stage      activeOverageWarningStage
	CycleStart int64
}

type activeOverageWarningSpec struct {
	Stage        activeOverageWarningStage
	Delay        int64
	TemplateID   string
	TemplateName string
	Subject      string
}

var activeOverageWarningSpecs = []activeOverageWarningSpec{
	{
		Stage:        activeOverageWarningStage0,
		TemplateID:   StorageWarningActiveOverageAnchorTemplateID,
		TemplateName: storageWarningActiveOverageTemplate,
		Subject:      storageWarningActiveOverage0Subject,
	},
	{
		Stage:        activeOverageWarningStage30,
		Delay:        storageWarningActiveOverageWarning30Delay,
		TemplateID:   storageWarningActiveOverage30TemplateID,
		TemplateName: storageWarningActiveOverageTemplate,
		Subject:      storageWarningActiveOverage30Subject,
	},
	{
		Stage:        activeOverageWarningStage60,
		Delay:        storageWarningActiveOverageWarning60Delay,
		TemplateID:   storageWarningActiveOverage60TemplateID,
		TemplateName: storageWarningActiveOverageTemplate,
		Subject:      storageWarningActiveOverage60Subject,
	},
	{
		Stage:        activeOverageWarningStage89,
		Delay:        storageWarningActiveOverageWarning89Delay,
		TemplateID:   storageWarningActiveOverage89TemplateID,
		TemplateName: storageWarningActiveOverageTemplate,
		Subject:      storageWarningActiveOverage89Subject,
	},
	{
		Stage:        activeOverageWarningStageScheduledDeletion,
		Delay:        storageWarningActiveOverageDeletionDelay,
		TemplateID:   repo.StorageWarningActiveOverageScheduledDeletionTemplateID,
		TemplateName: storageWarningActiveOverageScheduledDeletionTemplate,
		Subject:      storageWarningActiveOverageScheduledDeletionSubject,
	},
}

func activeOverageWarningTemplateDetails(stage activeOverageWarningStage) (templateID string, templateName string, subject string, ok bool) {
	for _, spec := range activeOverageWarningSpecs {
		if spec.Stage == stage {
			return spec.TemplateID, spec.TemplateName, spec.Subject, true
		}
	}
	return "", "", "", false
}

func activeOverageWarningTemplateIDs() []string {
	templateIDs := make([]string, 0, len(activeOverageWarningSpecs))
	for _, spec := range activeOverageWarningSpecs {
		templateIDs = append(templateIDs, spec.TemplateID)
	}
	return templateIDs
}

func resolveActiveOverageWarningStage(now int64, history map[string]int64) activeOverageWarningStage {
	return resolveActiveOverageWarning(now, history).Stage
}

func resolveActiveOverageWarning(now int64, history map[string]int64) activeOverageWarningResolution {
	cycleStart := history[StorageWarningActiveOverageAnchorTemplateID]
	scheduledDeletionSentAt := history[repo.StorageWarningActiveOverageScheduledDeletionTemplateID]
	if scheduledDeletionSentAt > 0 {
		if cycleStart <= 0 {
			cycleStart = scheduledDeletionSentAt
		}
		return activeOverageWarningResolution{
			Stage:      activeOverageWarningStageNone,
			CycleStart: cycleStart,
		}
	}
	if cycleStart == 0 {
		return activeOverageWarningResolution{
			Stage:      activeOverageWarningStage0,
			CycleStart: now,
		}
	}
	if overdueForActiveOverageDeletion(now, cycleStart) {
		finalReminderSentAt := history[storageWarningActiveOverage89TemplateID]
		if storageWarningTemplateSentInCycle(history, storageWarningActiveOverage89TemplateID, cycleStart) &&
			finalReminderSentAt >= now-storageWarningPreviousStageFreshnessWindow {
			return activeOverageWarningResolution{
				Stage:      activeOverageWarningStageScheduledDeletion,
				CycleStart: cycleStart,
			}
		}
		// Without an active login-grace marker, stale cadence restarts the warning
		// ladder instead of deleting from an old final reminder. The grace handler
		// in processStorageWarningSnapshot can still force terminal re-block.
		return activeOverageWarningResolution{
			Stage:      activeOverageWarningStage0,
			CycleStart: now,
		}
	}
	for _, spec := range activeOverageWarningSpecs[1:4] {
		if now >= cycleStart+spec.Delay &&
			!storageWarningTemplateSentInCycle(history, spec.TemplateID, cycleStart) {
			return activeOverageWarningResolution{
				Stage:      spec.Stage,
				CycleStart: cycleStart,
			}
		}
	}
	return activeOverageWarningResolution{
		Stage:      activeOverageWarningStageNone,
		CycleStart: cycleStart,
	}
}

func overdueForActiveOverageDeletion(now int64, cycleStart int64) bool {
	return now-cycleStart >= storageWarningActiveOverageDeletionDelay
}

func activeOverageWarningAutoDeleteDate(cycleStart int64, stage activeOverageWarningStage, now int64) int64 {
	if cycleStart <= 0 {
		cycleStart = now
	}
	autoDeleteDate := cycleStart + storageWarningActiveOverageDeletionDelay
	if stage == activeOverageWarningStage89 && autoDeleteDate <= now {
		return now + storageWarningOneDayInMicroseconds
	}
	return autoDeleteDate
}
