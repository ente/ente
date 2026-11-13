package details

// LockerUsageResponse describes locker usage against the applicable locker tier
// limits. For family users, used values reflect the combined family totals
// because that is what locker upload enforcement checks against.
type LockerUsageResponse struct {
	IsPaid             bool  `json:"isPaid"`
	IsFamily           bool  `json:"isFamily"`
	UsedFileCount      int64 `json:"usedFileCount"`
	FileLimit          int64 `json:"fileLimit"`
	RemainingFileCount int64 `json:"remainingFileCount"`
	UsedStorage        int64 `json:"usedStorage"`
	StorageLimit       int64 `json:"storageLimit"`
	RemainingStorage   int64 `json:"remainingStorage"`
	UserFileCount      int64 `json:"userFileCount"`
	UserStorage        int64 `json:"userStorage"`
}
