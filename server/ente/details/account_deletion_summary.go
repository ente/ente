package details

type AccountDeletionSummaryResponse struct {
	PhotosAndVideosCount    int64 `json:"photosAndVideosCount"`
	AuthenticatorCodesCount int64 `json:"authenticatorCodesCount"`
	LockerRecordsCount      int64 `json:"lockerRecordsCount"`
}
