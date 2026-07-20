package models

type AssetRedirectRequest struct {
	SpaceID       string `form:"spaceId"`
	ViewerSpaceID string `form:"viewerSpaceId"`
	ObjectKey     string `form:"objectKey"`
	AssetType     string `form:"assetType"`
	ObjectID      string `form:"objectID"`
}

type SpaceBrowserSessionRequest struct {
	SessionWrapKey string `json:"sessionWrapKey" binding:"required"`
}

type SpaceBrowserSessionResponse struct {
	SessionToken string `json:"sessionToken"`
}

type SpaceBrowserSessionBootstrapResponse struct {
	SessionWrapKey string `json:"sessionWrapKey"`
}

type GetSpaceProfileRequest struct {
	SpaceID       string `form:"spaceId"`
	ViewerSpaceID string `form:"viewerSpaceId"`
	Version       *int   `form:"version"`
}

type ListPostsRequest struct {
	SpaceID       string `form:"spaceId"`
	ViewerSpaceID string `form:"viewerSpaceId"`
	Cursor        string `form:"cursor"`
	Limit         int    `form:"limit"`
}

type ListFeedRequest struct {
	Cursor string `form:"cursor"`
	Limit  int    `form:"limit"`
}

type GetPostRequest struct {
	SpaceID       string `form:"spaceId"`
	ViewerSpaceID string `form:"viewerSpaceId"`
}

type ListMessageThreadRequest struct {
	Cursor string `form:"cursor"`
	Limit  int    `form:"limit"`
}

type FriendRelationshipRequest struct {
	TargetSpaceID string `form:"targetSpaceId" binding:"required"`
}

type SpaceKeyResponse struct {
	SpaceID             string `json:"spaceId"`
	SpaceSlug           string `json:"spaceSlug"`
	RootWrappedSpaceKey string `json:"rootWrappedSpaceKey"`
	PublicKey           string `json:"publicKey,omitempty"`
	EncryptedSecretKey  string `json:"encryptedSecretKey,omitempty"`
	EncryptedProfile    string `json:"encryptedProfile,omitempty"`
	KeyVersion          int    `json:"keyVersion"`
}

type PresignUploadRequest struct {
	Size       int64   `json:"size" binding:"required,gt=0"`
	ContentMD5 string  `json:"contentMD5" binding:"required"`
	Purpose    *string `json:"purpose,omitempty" binding:"omitempty,oneof=post avatar cover"`
}

type PresignUploadResponse struct {
	URL       string            `json:"url"`
	Method    string            `json:"method"`
	Headers   map[string]string `json:"headers"`
	ObjectKey string            `json:"objectKey"`
	ExpiresIn int               `json:"expiresIn"`
}

type AssetDownloadResponse struct {
	URL       string `json:"url"`
	ExpiresIn int    `json:"expiresIn"`
}

type ProfileAvatarPayload struct {
	ObjectID string `json:"objectID" binding:"required"`
	Size     int64  `json:"size,omitempty" binding:"omitempty,gt=0"`
}

type ProfileAvatarResponse struct {
	ObjectID   string `json:"objectID"`
	KeyVersion int    `json:"keyVersion"`
	Size       int64  `json:"size,omitempty"`
	UpdatedAt  string `json:"updatedAt,omitempty"`
}

type ProfileCoverPayload = ProfileAvatarPayload
type ProfileCoverResponse = ProfileAvatarResponse

type SpaceActorResponse struct {
	SpaceID          string                 `json:"spaceId,omitempty"`
	SpaceSlug        string                 `json:"spaceSlug"`
	PublicKey        string                 `json:"publicKey,omitempty"`
	KeyVersion       int                    `json:"keyVersion,omitempty"`
	EncryptedProfile string                 `json:"encryptedProfile,omitempty"`
	Avatar           *ProfileAvatarResponse `json:"avatar,omitempty"`
}

type AddFriendPayload struct {
	TargetSpaceID                 string `json:"targetSpaceId,omitempty"`
	TargetUsername                string `json:"targetUsername,omitempty"`
	RequesterFriendSealedSpaceKey string `json:"requesterFriendSealedSpaceKey" binding:"required"`
	RequesterKeyVersion           int    `json:"requesterKeyVersion" binding:"required,gt=0"`
}

type ConfirmFriendRequestPayload struct {
	TargetFriendSealedSpaceKey string `json:"targetFriendSealedSpaceKey" binding:"required"`
	TargetKeyVersion           int    `json:"targetKeyVersion" binding:"required,gt=0"`
}

type FriendTargetPayload struct {
	TargetUsername *string `json:"targetUsername,omitempty"`
	TargetSpaceID  *string `json:"targetSpaceId,omitempty"`
}

type FriendShareResponse struct {
	Friend               string `json:"friend"`
	SpaceID              string `json:"spaceId"`
	SpaceSlug            string `json:"spaceSlug"`
	FriendSealedSpaceKey string `json:"friendSealedSpaceKey"`
	KeyVersion           int    `json:"keyVersion"`
}

type FriendStatusResponse struct {
	Status string `json:"status"`
}

type SpaceFriendRequestResponse struct {
	RequestID int64              `json:"requestId"`
	Requester SpaceActorResponse `json:"requester"`
	CreatedAt string             `json:"createdAt"`
}

type FriendRelationshipResponse struct {
	Relationship string `json:"relationship"`
}

type UpdateSpaceProfileRequest struct {
	KeyVersion       int                   `json:"keyVersion" binding:"required,gt=0"`
	EncryptedProfile string                `json:"encryptedProfile" binding:"required"`
	Avatar           *ProfileAvatarPayload `json:"avatar,omitempty" binding:"omitempty"`
	Cover            *ProfileCoverPayload  `json:"cover,omitempty" binding:"omitempty"`
	RemoveAvatar     bool                  `json:"removeAvatar,omitempty"`
	RemoveCover      bool                  `json:"removeCover,omitempty"`
}

type UpdateSpaceProfileResponse struct {
	Status string                 `json:"status"`
	Avatar *ProfileAvatarResponse `json:"avatar,omitempty"`
	Cover  *ProfileCoverResponse  `json:"cover,omitempty"`
}

type CreateSpaceRequest struct {
	SpaceSlug           string `json:"spaceSlug" binding:"required"`
	RootWrappedSpaceKey string `json:"rootWrappedSpaceKey" binding:"required"`
	PublicKey           string `json:"publicKey" binding:"required"`
	EncryptedSecretKey  string `json:"encryptedSecretKey" binding:"required"`
	EncryptedProfile    string `json:"encryptedProfile"`
	ReferredBySpaceID   string `json:"referredBySpaceId,omitempty"`
}

type SpaceProfileResponse struct {
	SpaceID          string                 `json:"spaceId"`
	SpaceSlug        string                 `json:"spaceSlug"`
	Version          int                    `json:"version"`
	EncryptedProfile string                 `json:"encryptedProfile,omitempty"`
	UpdatedAt        string                 `json:"updatedAt,omitempty"`
	Avatar           *ProfileAvatarResponse `json:"avatar,omitempty"`
	Cover            *ProfileCoverResponse  `json:"cover,omitempty"`
	Friends          int64                  `json:"friends"`
}

type UpdateSpaceSlugRequest struct {
	SpaceSlug string `json:"spaceSlug" binding:"required"`
}

type SpaceLookupResponse struct {
	SpaceID   string `json:"spaceId"`
	SpaceSlug string `json:"spaceSlug"`
	Owner     string `json:"owner"`
	PublicKey string `json:"publicKey,omitempty"`
}

type SpaceSlugAvailabilityResponse struct {
	Available bool `json:"available"`
}

type RotateSpaceKeyRequest struct {
	KeyVersion          int    `json:"keyVersion" binding:"required,gt=0"`
	RootWrappedSpaceKey string `json:"rootWrappedSpaceKey" binding:"required"`
	WrappedPrevKey      string `json:"wrappedPrevKey" binding:"required"`
	EncryptedProfile    string `json:"encryptedProfile" binding:"required"`
}

type SpaceKeyVersionResponse struct {
	Version        int    `json:"version"`
	WrappedPrevKey string `json:"wrappedPrevKey,omitempty"`
	CreatedAt      string `json:"createdAt"`
}

type SpaceFriendResponse struct {
	Friend          SpaceActorResponse `json:"friend"`
	ShareKeyVersion int                `json:"shareKeyVersion"`
	CreatedAt       string             `json:"createdAt"`
}

type RefreshFriendSharesRequest struct {
	KeyVersion int                  `json:"keyVersion" binding:"required,gt=0"`
	Shares     []ShareUpdatePayload `json:"shares" binding:"required,min=1,dive"`
}

type ShareUpdatePayload struct {
	FriendSpaceID        string `json:"friendSpaceId" binding:"required"`
	FriendSealedSpaceKey string `json:"friendSealedSpaceKey" binding:"required"`
}

type CreatePostRequest struct {
	EncryptedPostKey string              `json:"encryptedPostKey" binding:"required"`
	KeyVersion       int                 `json:"keyVersion" binding:"required,gt=0"`
	CaptionCipher    *string             `json:"captionCipher,omitempty"`
	Objects          []PostObjectPayload `json:"objects" binding:"required,min=1,max=10,dive"`
}

type CreatePostResponse struct {
	PostID int64 `json:"postId"`
}

type LikePostResponse struct {
	Liked bool `json:"liked"`
}

type UpdatePostCaptionRequest struct {
	CaptionCipher *string `json:"captionCipher,omitempty"`
}

type CreateMessageRequest struct {
	MessageID                    string `json:"messageId,omitempty"`
	MessageCipher                string `json:"messageCipher" binding:"required"`
	SenderEncryptedMessageKey    string `json:"senderEncryptedMessageKey" binding:"required"`
	RecipientEncryptedMessageKey string `json:"recipientEncryptedMessageKey" binding:"required"`
	ReplyMessageID               string `json:"replyMessageId,omitempty"`
}

type LikeMessageResponse struct {
	Liked bool `json:"liked"`
}

type MessageResponse struct {
	MessageID           string  `json:"messageId"`
	Kind                string  `json:"kind"`
	SenderSpaceID       string  `json:"senderSpaceId"`
	RecipientSpaceID    string  `json:"recipientSpaceId"`
	MessageCipher       string  `json:"messageCipher,omitempty"`
	EncryptedMessageKey string  `json:"encryptedMessageKey,omitempty"`
	Text                string  `json:"text,omitempty"`
	ReplyPostID         *int64  `json:"replyPostId,omitempty"`
	ReplyMessageID      *string `json:"replyMessageId,omitempty"`
	Liked               bool    `json:"liked"`
	ViewerLiked         bool    `json:"viewerLiked"`
	IsDeleted           bool    `json:"isDeleted"`
	CreatedAt           string  `json:"createdAt"`
	UpdatedAt           string  `json:"updatedAt"`
}

type MessagePage struct {
	Items      []MessageResponse `json:"items"`
	NextCursor string            `json:"nextCursor,omitempty"`
}

type MessageConversationActivityResponse struct {
	ID                  string  `json:"id"`
	Type                string  `json:"type"`
	Kind                string  `json:"kind,omitempty"`
	CreatedAt           string  `json:"createdAt"`
	Outgoing            bool    `json:"outgoing,omitempty"`
	MessageID           *string `json:"messageId,omitempty"`
	SenderSpaceID       string  `json:"senderSpaceId,omitempty"`
	RecipientSpaceID    string  `json:"recipientSpaceId,omitempty"`
	MessageCipher       string  `json:"messageCipher,omitempty"`
	EncryptedMessageKey string  `json:"encryptedMessageKey,omitempty"`
	ReplyMessageID      *string `json:"replyMessageId,omitempty"`
	PostID              *int64  `json:"postId,omitempty"`
	PostSpaceID         string  `json:"postSpaceId,omitempty"`
}

type ConversationChatSummaryResponse struct {
	LatestActivity   MessageConversationActivityResponse   `json:"latestActivity"`
	UnreadActivities []MessageConversationActivityResponse `json:"unreadActivities"`
}

type ConversationsResponse struct {
	Friends         []SpaceFriendResponse                      `json:"friends"`
	PendingRequests []SpaceFriendRequestResponse               `json:"pendingRequests"`
	ChatSummaries   map[string]ConversationChatSummaryResponse `json:"chatSummaries"`
}

type PostObjectPayload struct {
	ObjectKey      string `json:"objectKey" binding:"required"`
	Size           int64  `json:"size,omitempty" binding:"omitempty,gt=0"`
	Position       int    `json:"position,omitempty" binding:"gte=0"`
	MetadataCipher string `json:"metadataCipher" binding:"required"`
}

type PostResponse struct {
	PostID           int64               `json:"postId"`
	SpaceID          string              `json:"spaceId"`
	SpaceSlug        string              `json:"spaceSlug"`
	Author           SpaceActorResponse  `json:"author"`
	EncryptedPostKey string              `json:"encryptedPostKey"`
	CaptionCipher    string              `json:"captionCipher,omitempty"`
	KeyVersion       int                 `json:"keyVersion"`
	Objects          []PostObjectPayload `json:"objects,omitempty"`
	CreatedAt        string              `json:"createdAt"`
	ViewerLiked      bool                `json:"viewerLiked"`
}

type SpaceUnreadStatusResponse struct {
	NotificationsUnread bool `json:"notificationsUnread"`
}

type PostPage struct {
	Items      []PostResponse `json:"items"`
	NextCursor string         `json:"nextCursor,omitempty"`
}

type FeedPage struct {
	Items      []PostResponse `json:"items"`
	NextCursor string         `json:"nextCursor,omitempty"`
}
