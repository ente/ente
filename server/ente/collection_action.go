package ente

type CollectionAction struct {
	ID           string                 `json:"id"`
	UserID       int64                  `json:"userID"`
	ActorUserID  int64                  `json:"actorUserID"`
	CollectionID int64                  `json:"collectionID"`
	FileID       *int64                 `json:"fileID,omitempty"`
	Action       string                 `json:"action"`
	IsPending    bool                   `json:"isPending"`
	Data         map[string]interface{} `json:"data,omitempty"`
	CreatedAt    int64                  `json:"createdAt"`
	UpdatedAt    int64                  `json:"updatedAt"`
}
