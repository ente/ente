package models

type CreateCommentRequest struct {
	CommentID string `json:"commentId" binding:"required,max=64"`
	ReplyToID string `json:"replyToId" binding:"max=64"`
	Cipher    string `json:"cipher" binding:"required"`
}

type SetCommentReactionRequest struct {
	Cipher string `json:"cipher" binding:"required"`
}

type CommentReactionResponse struct {
	Actor  SpaceActorResponse `json:"actor"`
	Cipher string             `json:"cipher"`
	IsOwn  bool               `json:"isOwn"`
}

type CommentResponse struct {
	CommentID             string                    `json:"commentId"`
	Author                *SpaceActorResponse       `json:"author"`
	ParentID              string                    `json:"parentId"`
	ReplyToID             string                    `json:"replyToId"`
	Cipher                string                    `json:"cipher"`
	CreatedAt             string                    `json:"createdAt"`
	CanDelete             bool                      `json:"canDelete"`
	Reactions             []CommentReactionResponse `json:"reactions"`
	UnreadNotificationIDs []string                  `json:"unreadNotificationIds"`
}

type CommentPage struct {
	Items      []CommentResponse `json:"items"`
	NextCursor string            `json:"nextCursor"`
}
