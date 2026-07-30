package email

import (
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/time"
)

const (
	storageWarningExpiredTemplate                  = "storage-warning/storage_warning_expired.html"
	storageWarningExpiredScheduledDeletionTemplate = "storage-warning/storage_warning_expired_scheduled_deletion.html"

	storageWarningExpiredAnchorDelay              = 30 * 24 * time.MicroSecondsInOneHour
	storageWarningExpiredDeletionDelay            = 120 * 24 * time.MicroSecondsInOneHour
	storageWarningExpiredWarning0Delay            = 0
	storageWarningExpiredWarning30Delay           = 30 * 24 * time.MicroSecondsInOneHour
	storageWarningExpiredWarning60Delay           = 60 * 24 * time.MicroSecondsInOneHour
	storageWarningExpiredWarning90Delay           = 90 * 24 * time.MicroSecondsInOneHour
	storageWarningExpiredWarning119Delay          = 119 * 24 * time.MicroSecondsInOneHour
	storageWarningExpiredBackfillThreshold        = storageWarningExpiredWarning30Delay
	storageWarningExpiredBackfillMinRecoveryDelay = 30 * 24 * time.MicroSecondsInOneHour

	storageWarningExpired0TemplateID   = "storage_warning_expired_0d"
	storageWarningExpired30TemplateID  = "storage_warning_expired_30d"
	storageWarningExpired60TemplateID  = "storage_warning_expired_60d"
	storageWarningExpired90TemplateID  = "storage_warning_expired_90d"
	storageWarningExpired119TemplateID = "storage_warning_expired_119d"

	storageWarningExpired0Subject                 = "Action needed: Your Ente subscription has expired"
	storageWarningExpired30Subject                = "Reminder: Your Ente data is scheduled for deletion"
	storageWarningExpired60Subject                = "Reminder: Renew your Ente plan to avoid data deletion"
	storageWarningExpired90Subject                = "30-day reminder: Your Ente data will be deleted in 30 days"
	storageWarningExpired119Subject               = "Final reminder: Your Ente data will be deleted tomorrow"
	storageWarningExpiredScheduledDeletionSubject = "Your Ente data is scheduled for deletion"
)

type expiredWarningStage string

const (
	expiredWarningStageNone              expiredWarningStage = "none"
	expiredWarningStage0                 expiredWarningStage = "expired_0d"
	expiredWarningStage30                expiredWarningStage = "expired_30d"
	expiredWarningStage60                expiredWarningStage = "expired_60d"
	expiredWarningStage90                expiredWarningStage = "expired_90d"
	expiredWarningStage119               expiredWarningStage = "expired_119d"
	expiredWarningStageScheduledDeletion expiredWarningStage = "expired_scheduled_deletion"
)

type expiredWarningResolution struct {
	Stage          expiredWarningStage
	CycleStart     int64
	AutoDeleteDate int64
	BufferedCycle  bool
}

type expiredWarningSpec struct {
	Stage        expiredWarningStage
	Delay        int64
	TemplateID   string
	TemplateName string
	Subject      string
}

var expiredWarningSpecs = []expiredWarningSpec{
	{
		Stage:        expiredWarningStage0,
		Delay:        storageWarningExpiredWarning0Delay,
		TemplateID:   storageWarningExpired0TemplateID,
		TemplateName: storageWarningExpiredTemplate,
		Subject:      storageWarningExpired0Subject,
	},
	{
		Stage:        expiredWarningStage30,
		Delay:        storageWarningExpiredWarning30Delay,
		TemplateID:   storageWarningExpired30TemplateID,
		TemplateName: storageWarningExpiredTemplate,
		Subject:      storageWarningExpired30Subject,
	},
	{
		Stage:        expiredWarningStage60,
		Delay:        storageWarningExpiredWarning60Delay,
		TemplateID:   storageWarningExpired60TemplateID,
		TemplateName: storageWarningExpiredTemplate,
		Subject:      storageWarningExpired60Subject,
	},
	{
		Stage:        expiredWarningStage90,
		Delay:        storageWarningExpiredWarning90Delay,
		TemplateID:   storageWarningExpired90TemplateID,
		TemplateName: storageWarningExpiredTemplate,
		Subject:      storageWarningExpired90Subject,
	},
	{
		Stage:        expiredWarningStage119,
		Delay:        storageWarningExpiredWarning119Delay,
		TemplateID:   storageWarningExpired119TemplateID,
		TemplateName: storageWarningExpiredTemplate,
		Subject:      storageWarningExpired119Subject,
	},
	{
		Stage:        expiredWarningStageScheduledDeletion,
		Delay:        storageWarningExpiredDeletionDelay,
		TemplateID:   repo.StorageWarningExpiredScheduledDeletionTemplateID,
		TemplateName: storageWarningExpiredScheduledDeletionTemplate,
		Subject:      storageWarningExpiredScheduledDeletionSubject,
	},
}

var expiredBufferedWarningSpecs = []expiredWarningSpec{
	{
		Stage:      expiredWarningStage0,
		TemplateID: storageWarningExpired0TemplateID,
	},
	{
		Stage:      expiredWarningStage60,
		TemplateID: storageWarningExpired60TemplateID,
	},
	{
		Stage:      expiredWarningStage119,
		TemplateID: storageWarningExpired119TemplateID,
	},
	{
		Stage:      expiredWarningStageScheduledDeletion,
		TemplateID: repo.StorageWarningExpiredScheduledDeletionTemplateID,
	},
}

func expiredWarningTemplateDetails(stage expiredWarningStage) (templateID string, templateName string, subject string, ok bool) {
	for _, spec := range expiredWarningSpecs {
		if spec.Stage == stage {
			return spec.TemplateID, spec.TemplateName, spec.Subject, true
		}
	}
	return "", "", "", false
}

func expiredWarningTemplateIDs() []string {
	templateIDs := make([]string, 0, len(expiredWarningSpecs))
	for _, spec := range expiredWarningSpecs {
		templateIDs = append(templateIDs, spec.TemplateID)
	}
	return templateIDs
}

// Template IDs use days since the expired-warning anchor, which is raw expiry + 30 days.
func resolveExpiredWarningStage(expiredWarningAnchor int64, now int64, history map[string]int64) expiredWarningStage {
	if expiredWarningAnchor <= 0 || expiredWarningAnchor > now {
		return expiredWarningStageNone
	}

	daysSinceAnchor := now - expiredWarningAnchor
	for _, spec := range expiredWarningSpecs {
		if daysSinceAnchor >= spec.Delay &&
			!storageWarningTemplateSentInCycle(history, spec.TemplateID, expiredWarningAnchor) {
			return spec.Stage
		}
	}
	return expiredWarningStageNone
}

func resolveExpiredWarning(expiredWarningAnchor int64, now int64, history map[string]int64) expiredWarningResolution {
	if expiredWarningAnchor <= 0 || expiredWarningAnchor > now {
		return expiredWarningResolution{}
	}

	standardAutoDeleteDate := expiredWarningAnchor + storageWarningExpiredDeletionDelay
	if cycleStart, ok := expiredBufferedCycleStart(expiredWarningAnchor, history); ok {
		autoDeleteDate := max(standardAutoDeleteDate, cycleStart+storageWarningExpiredBackfillMinRecoveryDelay)
		stage := resolveExpiredBufferedWarningStage(cycleStart, autoDeleteDate, now, history)
		return expiredWarningResolution{
			Stage:          stage,
			CycleStart:     cycleStart,
			AutoDeleteDate: expiredWarningAutoDeleteDate(autoDeleteDate, stage, now),
			BufferedCycle:  true,
		}
	}

	if shouldUseExpiredBufferedCycle(expiredWarningAnchor, now, history) {
		cycleStart := now
		autoDeleteDate := max(standardAutoDeleteDate, cycleStart+storageWarningExpiredBackfillMinRecoveryDelay)

		stage := resolveExpiredBufferedWarningStage(cycleStart, autoDeleteDate, now, history)
		return expiredWarningResolution{
			Stage:          stage,
			CycleStart:     cycleStart,
			AutoDeleteDate: expiredWarningAutoDeleteDate(autoDeleteDate, stage, now),
			BufferedCycle:  true,
		}
	}

	stage := resolveExpiredWarningStage(expiredWarningAnchor, now, history)
	return expiredWarningResolution{
		Stage:          stage,
		CycleStart:     expiredWarningAnchor,
		AutoDeleteDate: expiredWarningAutoDeleteDate(standardAutoDeleteDate, stage, now),
	}
}

func shouldUseExpiredBufferedCycle(expiredWarningAnchor int64, now int64, history map[string]int64) bool {
	if expiredWarningAnchor <= 0 || now < expiredWarningAnchor+storageWarningExpiredBackfillThreshold {
		return false
	}
	return !hasExpiredWarningHistoryInCycle(history, expiredWarningAnchor)
}

func expiredBufferedCycleStart(expiredWarningAnchor int64, history map[string]int64) (int64, bool) {
	sentAt := history[storageWarningExpired0TemplateID]
	if sentAt <= 0 || sentAt < expiredWarningAnchor+storageWarningExpiredBackfillThreshold {
		return 0, false
	}
	return sentAt, true
}

func hasExpiredWarningHistoryInCycle(history map[string]int64, cycleStart int64) bool {
	for _, templateID := range expiredWarningTemplateIDs() {
		if storageWarningTemplateSentInCycle(history, templateID, cycleStart) {
			return true
		}
	}
	return false
}

func resolveExpiredBufferedWarningStage(cycleStart int64, autoDeleteDate int64, now int64, history map[string]int64) expiredWarningStage {
	if cycleStart <= 0 || cycleStart > now {
		return expiredWarningStageNone
	}

	for _, spec := range expiredBufferedWarningSpecs {
		if now >= expiredBufferedWarningAt(spec.Stage, cycleStart, autoDeleteDate) &&
			!storageWarningTemplateSentInCycle(history, spec.TemplateID, cycleStart) {
			return spec.Stage
		}
	}
	return expiredWarningStageNone
}

func expiredBufferedWarningAt(stage expiredWarningStage, cycleStart int64, autoDeleteDate int64) int64 {
	switch stage {
	case expiredWarningStage0:
		return cycleStart
	case expiredWarningStage60:
		return expiredBufferedWarning60At(cycleStart, autoDeleteDate)
	case expiredWarningStage119:
		return expiredBufferedWarning119At(autoDeleteDate)
	case expiredWarningStageScheduledDeletion:
		return autoDeleteDate
	default:
		return 0
	}
}

func expiredBufferedWarning60At(cycleStart int64, autoDeleteDate int64) int64 {
	if autoDeleteDate <= cycleStart {
		return cycleStart
	}
	return cycleStart + ((autoDeleteDate - cycleStart) / 2)
}

func expiredBufferedWarning119At(autoDeleteDate int64) int64 {
	return autoDeleteDate - storageWarningOneDayInMicroseconds
}

func expiredWarningAutoDeleteDate(autoDeleteDate int64, stage expiredWarningStage, now int64) int64 {
	if stage == expiredWarningStage119 && autoDeleteDate <= now {
		return now + storageWarningOneDayInMicroseconds
	}
	return autoDeleteDate
}

func expiredWarningAnchorFromSubscriptionExpiry(subscriptionExpiry int64) int64 {
	if subscriptionExpiry <= 0 {
		return 0
	}
	return subscriptionExpiry + storageWarningExpiredAnchorDelay
}
