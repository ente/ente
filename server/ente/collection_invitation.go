package ente

type CollectionAcceptanceStatus string

const (
	CollectionPending  CollectionAcceptanceStatus = "pending"
	CollectionAccepted CollectionAcceptanceStatus = "accepted"
	CollectionRejected CollectionAcceptanceStatus = "rejected"
)

type CollectionInvitation struct {
	CollectionID        int64          `json:"collectionID"`
	Inviter             CollectionUser `json:"inviter"`
	EncryptedKey        string         `json:"encryptedKey"`
	Name                string         `json:"name,omitempty"`
	EncryptedName       string         `json:"encryptedName,omitempty"`
	NameDecryptionNonce string         `json:"nameDecryptionNonce,omitempty"`
	SharedAt            int64          `json:"sharedAt"`
}

type AcceptCollectionInvitationsRequest struct {
	CollectionIDs []int64 `json:"collectionIDs" binding:"required,min=1,dive,gt=0"`
}

type RejectCollectionInvitationRequest struct {
	CollectionID int64 `json:"collectionID" binding:"required,gt=0"`
}

type AcceptCollectionInvitationsResponse struct {
	AcceptedCollectionIDs []int64      `json:"acceptedCollectionIDs"`
	Collections           []Collection `json:"collections"`
}

type JoinCollectionResponse struct {
	AcceptedCollectionIDs []int64    `json:"acceptedCollectionIDs"`
	Collection            Collection `json:"collection"`
}
