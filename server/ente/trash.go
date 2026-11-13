package ente

type Trash struct {
	File       File  `json:"file"`
	IsDeleted  bool  `json:"isDeleted"`
	IsRestored bool  `json:"isRestored"`
	DeleteBy   int64 `json:"deleteBy"`
	CreatedAt  int64 `json:"createdAt"`
	UpdatedAt  int64 `json:"updatedAt"`
}

type DeleteTrashFilesRequest struct {
	FileIDs []int64 `json:"fileIDs" binding:"required"`
	// Set from the authenticated user after binding.
	OwnerID int64
}

type EmptyTrashRequest struct {
	// Empty only entries at or before this timestamp so queued work cannot
	// delete newly trashed files.
	LastUpdatedAt int64 `json:"lastUpdatedAt" binding:"required"`
}

type TrashCollectionV3Request struct {
	CollectionID int64 `json:"collectionID" form:"collectionID" binding:"required"`
	// If true, deletion requires an empty collection. Otherwise remaining files
	// move to trash.
	KeepFiles *bool `json:"keepFiles" form:"keepFiles" binding:"required"`
}
