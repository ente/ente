package social

type AnonUser struct {
	ID           string `json:"anonUserID"`
	CollectionID int64  `json:"collectionID"`
	Cipher       string `json:"cipher"`
	Nonce        string `json:"nonce"`
	CreatedAt    int64  `json:"createdAt"`
	UpdatedAt    int64  `json:"updatedAt"`
}
