package ente

type MemoryShareType string

const (
	MemoryShareTypeShare MemoryShareType = "share"
	MemoryShareTypeLane  MemoryShareType = "lane"
)

type MemoryShare struct {
	ID                 int64           `json:"id"`
	UserID             int64           `json:"-"`
	Type               MemoryShareType `json:"type"`
	MemoryHash         string          `json:"memoryHash,omitempty"`
	MetadataCipher     string          `json:"metadataCipher,omitempty"`
	MetadataNonce      string          `json:"metadataNonce,omitempty"`
	EncryptedKey       string          `json:"encryptedKey,omitempty"`
	KeyDecryptionNonce string          `json:"keyDecryptionNonce,omitempty"`
	AccessToken        string          `json:"accessToken,omitempty"`
	IsDeleted          bool            `json:"isDeleted,omitempty"`
	CreatedAt          int64           `json:"createdAt"`
	UpdatedAt          int64           `json:"updatedAt,omitempty"`
	URL                string          `json:"url,omitempty"`
}

type MemoryShareFile struct {
	ID                 int64  `json:"id"`
	MemoryShareID      int64  `json:"-"`
	FileID             int64  `json:"fileID"`
	FileOwnerID        int64  `json:"-"`
	Position           int64  `json:"position,omitempty"`
	EncryptedKey       string `json:"encryptedKey"`
	KeyDecryptionNonce string `json:"keyDecryptionNonce"`
	CreatedAt          int64  `json:"createdAt"`
}

type CreateMemoryShareRequest struct {
	Type               MemoryShareType       `json:"type,omitempty"`
	MemoryHash         string                `json:"memoryHash,omitempty"`
	MetadataCipher     string                `json:"metadataCipher"`
	MetadataNonce      string                `json:"metadataNonce"`
	EncryptedKey       string                `json:"encryptedKey" binding:"required"`
	KeyDecryptionNonce string                `json:"keyDecryptionNonce" binding:"required"`
	Files              []MemoryShareFileItem `json:"files" binding:"required,min=1"`
}

type MemoryShareFileItem struct {
	FileID             int64  `json:"fileID" binding:"required"`
	Position           *int64 `json:"position,omitempty"`
	EncryptedKey       string `json:"encryptedKey" binding:"required"`
	KeyDecryptionNonce string `json:"keyDecryptionNonce" binding:"required"`
}

type CreateMemoryShareResponse struct {
	MemoryShare MemoryShare `json:"memoryShare"`
}

type ListMemorySharesResponse struct {
	MemoryShares []MemoryShare `json:"memoryShares"`
}

type PublicMemoryShareResponse struct {
	MemoryShare MemoryShare `json:"memoryShare"`
}

type PublicMemoryShareFile struct {
	File               File   `json:"file"`
	Position           int64  `json:"position"`
	EncryptedKey       string `json:"encryptedKey"`
	KeyDecryptionNonce string `json:"keyDecryptionNonce"`
}

type PublicMemoryShareFilesResponse struct {
	Files []PublicMemoryShareFile `json:"files"`
}

type MemoryShareAccessContext struct {
	ID          int64
	ShareID     int64
	AccessToken string
	IP          string
	UserAgent   string
}
