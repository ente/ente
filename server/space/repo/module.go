package repo

import (
	"database/sql"

	"github.com/ente/museum/pkg/utils/s3config"
)

type Module struct {
	Spaces   *SpacesRepository
	Posts    *PostsRepository
	Friends  *FriendsRepository
	Messages *MessagesRepository
	Assets   *AssetsRepository
	Read     *ReadMarkersRepository
	Sessions *SessionsRepository
	Drips    *DripsRepository
}

type SpacesRepository struct {
	DB *sql.DB
}

type PostsRepository struct {
	DB *sql.DB
}

type FriendsRepository struct {
	DB *sql.DB
}

type MessagesRepository struct {
	DB *sql.DB
}

type AssetsRepository struct {
	DB       *sql.DB
	S3Config *s3config.S3Config
}

type ReadMarkersRepository struct {
	DB *sql.DB
}

type SessionsRepository struct {
	DB *sql.DB
}

type DripsRepository struct {
	DB *sql.DB
}

type SpaceRecord struct {
	SpaceID             string
	OwnerID             int64
	SpaceSlug           string
	RootWrappedSpaceKey []byte
	PublicKey           []byte
	EncryptedSecretKey  []byte
	EncryptedProfile    []byte
	CurrentVersion      int
	ReferredBySpaceID   sql.NullString
	AvatarObjectID      sql.NullString
	AvatarKeyVersion    sql.NullInt64
	AvatarSize          sql.NullInt64
	CoverObjectID       sql.NullString
	CoverKeyVersion     sql.NullInt64
	CoverSize           sql.NullInt64
	CreatedAt           int64
	UpdatedAt           int64
}

type ProfileAssetUpdate struct {
	ObjectID string
	BucketID string
	Size     int64
}

type SpaceVersionRecord struct {
	SpaceID             string
	Version             int
	RootWrappedSpaceKey []byte
	EncryptedProfile    []byte
	WrappedPrevKey      []byte
	CreatedAt           int64
}

type SpacePostRecord struct {
	PostID           int64
	SpaceID          string
	SpaceSlug        string
	OwnerID          int64
	Author           SpaceActorRecord
	EncryptedPostKey []byte
	CaptionCipher    []byte
	KeyVersion       int
	CreatedAt        int64
	ViewerLiked      bool
}

type SpacePostAssetRecord struct {
	AssetID        int64
	PostID         int64
	ObjectKey      string
	BucketID       string
	Size           sql.NullInt64
	Position       int
	MetadataCipher []byte
	CreatedAt      int64
}

type SpaceTempObjectRecord struct {
	ObjectKey    string
	SpaceID      sql.NullString
	Purpose      string
	BucketID     string
	ExpectedSize int64
	ExpiresAt    int64
	CleanupAfter int64
	CreatedAt    int64
}

type SpaceMessageRecord struct {
	MessageID           string
	Kind                string
	SenderSpaceID       string
	RecipientSpaceID    string
	MessageCipher       []byte
	EncryptedMessageKey []byte
	ReplyPostID         sql.NullInt64
	ReplyMessageID      sql.NullString
	Liked               bool
	ViewerLiked         bool
	IsDeleted           bool
	Text                string
	CreatedAt           int64
	UpdatedAt           int64
}

type SpaceConversationChatSummaryRecord struct {
	FriendSpaceID    string
	LatestActivity   SpaceMessageConversationActivityRecord
	UnreadActivities []SpaceMessageConversationActivityRecord
}

type SpaceMessageConversationActivityRecord struct {
	ID                  string
	Type                string
	Kind                sql.NullString
	CreatedAt           int64
	Outgoing            bool
	MessageID           sql.NullString
	SenderSpaceID       sql.NullString
	RecipientSpaceID    sql.NullString
	MessageCipher       []byte
	EncryptedMessageKey []byte
	ReplyMessageID      sql.NullString
	PostID              sql.NullInt64
	PostSpaceID         sql.NullString
}

type CreateSpaceMessageRecord struct {
	MessageID                    string
	Kind                         string
	SenderSpaceID                string
	RecipientSpaceID             string
	MessageCipher                []byte
	SenderEncryptedMessageKey    []byte
	RecipientEncryptedMessageKey []byte
	ReplyPostID                  sql.NullInt64
	ReplyMessageID               sql.NullString
}

type SpaceActorRecord struct {
	SpaceID          string
	SpaceSlug        string
	PublicKey        []byte
	KeyVersion       int
	EncryptedProfile []byte
	AvatarObjectID   sql.NullString
	AvatarKeyVersion sql.NullInt64
	AvatarSize       sql.NullInt64
	UpdatedAt        int64
}

type SpaceShareRecord struct {
	SpaceID              string
	SpaceSlug            string
	FriendSealedSpaceKey []byte
	KeyVersion           int
	CreatedAt            int64
}

type SpaceShareUpdateRecord struct {
	FriendSpaceID        string
	FriendSealedSpaceKey []byte
}

type SpaceFriendRecord struct {
	Friend          SpaceActorRecord
	ShareKeyVersion int
	CreatedAt       int64
}

type SpaceFriendRequestRecord struct {
	RequestID                     int64
	RequesterID                   int64
	RequesterSpaceID              string
	TargetID                      int64
	TargetSpaceID                 string
	RequesterFriendSealedSpaceKey []byte
	RequesterKeyVersion           int
	CreatedAt                     int64
	Requester                     SpaceActorRecord
}

type SpaceBrowserSessionRecord struct {
	TokenHash      []byte
	UserID         int64
	SessionWrapKey string
	ExpiresAt      int64
	CreatedAt      int64
	UpdatedAt      int64
	LastUsedAt     int64
}

func NewModule(db *sql.DB, s3Config *s3config.S3Config) *Module {
	return &Module{
		Spaces:   &SpacesRepository{DB: db},
		Posts:    &PostsRepository{DB: db},
		Friends:  &FriendsRepository{DB: db},
		Messages: &MessagesRepository{DB: db},
		Assets:   &AssetsRepository{DB: db, S3Config: s3Config},
		Read:     &ReadMarkersRepository{DB: db},
		Sessions: &SessionsRepository{DB: db},
		Drips:    &DripsRepository{DB: db},
	}
}
