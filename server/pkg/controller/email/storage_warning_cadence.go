package email

type storageWarningCadenceRequirement struct {
	TemplateID      string
	StageKey        string
	FreshnessWindow int64
}

func storageWarningCadenceBroken(snapshot storageWarningSnapshot) (bool, string) {
	requirement, ok := storageWarningCadenceRequirementForSnapshot(snapshot)
	if !ok {
		return false, ""
	}

	previousSentAt := snapshot.NotificationHistory[requirement.TemplateID]
	if !storageWarningTemplateSentInCycle(snapshot.NotificationHistory, requirement.TemplateID, snapshot.WarningCycleStart) ||
		previousSentAt < snapshot.EvaluatedAt-requirement.FreshnessWindow {
		return true, buildStorageWarningCadenceAlert(snapshot, requirement.StageKey, previousSentAt)
	}

	return false, ""
}

func storageWarningCadenceRequirementForSnapshot(snapshot storageWarningSnapshot) (storageWarningCadenceRequirement, bool) {
	switch snapshot.Bucket {
	case storageWarningBucketExpired:
		return expiredWarningCadenceRequirement(snapshot)
	case storageWarningBucketActiveOverage:
		return activeOverageWarningCadenceRequirement(snapshot)
	default:
		return storageWarningCadenceRequirement{}, false
	}
}

func expiredWarningCadenceRequirement(snapshot storageWarningSnapshot) (storageWarningCadenceRequirement, bool) {
	requirement := storageWarningCadenceRequirement{
		FreshnessWindow: storageWarningPreviousStageFreshnessWindow,
	}

	switch snapshot.ExpiredStage {
	case expiredWarningStage30:
		requirement.TemplateID = storageWarningExpired0TemplateID
		requirement.StageKey = string(expiredWarningStage0)
	case expiredWarningStage60:
		requirement.TemplateID = storageWarningExpired30TemplateID
		requirement.StageKey = string(expiredWarningStage30)
		if snapshot.ExpiredBufferedCycle {
			requirement.TemplateID = storageWarningExpired0TemplateID
			requirement.StageKey = string(expiredWarningStage0)
			requirement.FreshnessWindow = maxStorageWarningFreshnessWindow(
				requirement.FreshnessWindow,
				expiredBufferedWarning60At(snapshot.WarningCycleStart, snapshot.AutoDeleteDate)-snapshot.WarningCycleStart+storageWarningOneDayInMicroseconds+storageWarningBufferedCadenceExtraGrace,
			)
		}
	case expiredWarningStage90:
		requirement.TemplateID = storageWarningExpired60TemplateID
		requirement.StageKey = string(expiredWarningStage60)
	case expiredWarningStage119:
		requirement.TemplateID = storageWarningExpired90TemplateID
		requirement.StageKey = string(expiredWarningStage90)
		if snapshot.ExpiredBufferedCycle {
			requirement.TemplateID = storageWarningExpired60TemplateID
			requirement.StageKey = string(expiredWarningStage60)
			requirement.FreshnessWindow = maxStorageWarningFreshnessWindow(
				requirement.FreshnessWindow,
				expiredBufferedWarning119At(snapshot.AutoDeleteDate)-expiredBufferedWarning60At(snapshot.WarningCycleStart, snapshot.AutoDeleteDate)+storageWarningOneDayInMicroseconds+storageWarningBufferedCadenceExtraGrace,
			)
		}
	case expiredWarningStageScheduledDeletion:
		requirement.TemplateID = storageWarningExpired119TemplateID
		requirement.StageKey = string(expiredWarningStage119)
	default:
		return storageWarningCadenceRequirement{}, false
	}

	return requirement, true
}

func activeOverageWarningCadenceRequirement(snapshot storageWarningSnapshot) (storageWarningCadenceRequirement, bool) {
	requirement := storageWarningCadenceRequirement{
		FreshnessWindow: storageWarningPreviousStageFreshnessWindow,
	}

	switch snapshot.ActiveOverageStage {
	case activeOverageWarningStage30:
		requirement.TemplateID = StorageWarningActiveOverageAnchorTemplateID
		requirement.StageKey = string(activeOverageWarningStage0)
	case activeOverageWarningStage60:
		requirement.TemplateID = storageWarningActiveOverage30TemplateID
		requirement.StageKey = string(activeOverageWarningStage30)
	case activeOverageWarningStage89:
		requirement.TemplateID = storageWarningActiveOverage60TemplateID
		requirement.StageKey = string(activeOverageWarningStage60)
	case activeOverageWarningStageScheduledDeletion:
		requirement.TemplateID = storageWarningActiveOverage89TemplateID
		requirement.StageKey = string(activeOverageWarningStage89)
	default:
		return storageWarningCadenceRequirement{}, false
	}

	return requirement, true
}

func maxStorageWarningFreshnessWindow(lhs int64, rhs int64) int64 {
	if lhs >= rhs {
		return lhs
	}
	return rhs
}
