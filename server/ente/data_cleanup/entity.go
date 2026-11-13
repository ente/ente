package data_cleanup

type Stage string

const (
	Scheduled  Stage = "scheduled"
	Collection Stage = "collection"
	Trash      Stage = "trash"
	Storage    Stage = "storage"
	Completed  Stage = "completed"
)

type DataCleanup struct {
	UserID            int64
	Stage             Stage
	StageScheduleTime int64
	StageAttemptCount int
	CreatedAt         int64
	UpdatedAt         int64
}
