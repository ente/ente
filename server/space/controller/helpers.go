package controller

import (
	"time"

	"github.com/ente/museum/space/models"
	spacerepo "github.com/ente/museum/space/repo"
)

func formatMicros(value int64) string {
	if value <= 0 {
		return ""
	}
	return time.UnixMicro(value).UTC().Format(time.RFC3339Nano)
}

func toAvatarResponse(space *spacerepo.SpaceRecord) *models.ProfileAvatarResponse {
	if !space.AvatarObjectID.Valid {
		return nil
	}
	resp := &models.ProfileAvatarResponse{
		ObjectID:   space.AvatarObjectID.String,
		KeyVersion: int(space.AvatarKeyVersion.Int64),
		UpdatedAt:  formatMicros(space.UpdatedAt),
	}
	if space.AvatarSize.Valid {
		resp.Size = space.AvatarSize.Int64
	}
	return resp
}

func toCoverResponse(space *spacerepo.SpaceRecord) *models.ProfileCoverResponse {
	if !space.CoverObjectID.Valid {
		return nil
	}
	resp := &models.ProfileCoverResponse{
		ObjectID:   space.CoverObjectID.String,
		KeyVersion: int(space.CoverKeyVersion.Int64),
		UpdatedAt:  formatMicros(space.UpdatedAt),
	}
	if space.CoverSize.Valid {
		resp.Size = space.CoverSize.Int64
	}
	return resp
}

func toActorAvatarResponse(actor spacerepo.SpaceActorRecord) *models.ProfileAvatarResponse {
	if !actor.AvatarObjectID.Valid {
		return nil
	}
	resp := &models.ProfileAvatarResponse{
		ObjectID:   actor.AvatarObjectID.String,
		KeyVersion: int(actor.AvatarKeyVersion.Int64),
		UpdatedAt:  formatMicros(actor.UpdatedAt),
	}
	if actor.AvatarSize.Valid {
		resp.Size = actor.AvatarSize.Int64
	}
	return resp
}

func toActorResponse(actor spacerepo.SpaceActorRecord, includePrivate bool) models.SpaceActorResponse {
	resp := models.SpaceActorResponse{
		SpaceSlug: actor.SpaceSlug,
	}
	if !includePrivate {
		return resp
	}
	resp.SpaceID = actor.SpaceID
	resp.PublicKey = encodeSpaceField(actor.PublicKey)
	resp.KeyVersion = actor.KeyVersion
	resp.EncryptedProfile = encodeSpaceField(actor.EncryptedProfile)
	resp.Avatar = toActorAvatarResponse(actor)
	return resp
}

func toSpaceKeyResponse(space *spacerepo.SpaceRecord) *models.SpaceKeyResponse {
	return &models.SpaceKeyResponse{
		SpaceID:             space.SpaceID,
		SpaceSlug:           space.SpaceSlug,
		RootWrappedSpaceKey: encodeSpaceField(space.RootWrappedSpaceKey),
		PublicKey:           encodeSpaceField(space.PublicKey),
		EncryptedSecretKey:  encodeSpaceField(space.EncryptedSecretKey),
		EncryptedProfile:    encodeSpaceField(space.EncryptedProfile),
		KeyVersion:          space.CurrentVersion,
	}
}

func toPostObjectPayload(asset spacerepo.SpacePostAssetRecord) models.PostObjectPayload {
	resp := models.PostObjectPayload{
		ObjectKey: asset.ObjectKey,
		Position:  asset.Position,
	}
	if asset.Size.Valid {
		resp.Size = asset.Size.Int64
	}
	if len(asset.MetadataCipher) > 0 {
		resp.MetadataCipher = encodeSpaceField(asset.MetadataCipher)
	}
	return resp
}

func toPostResponse(post *spacerepo.SpacePostRecord, assets []spacerepo.SpacePostAssetRecord, includeAuthorPrivate bool) *models.PostResponse {
	resp := &models.PostResponse{
		PostID:           post.PostID,
		SpaceID:          post.SpaceID,
		SpaceSlug:        post.SpaceSlug,
		Author:           toActorResponse(post.Author, includeAuthorPrivate),
		EncryptedPostKey: encodeSpaceField(post.EncryptedPostKey),
		CaptionCipher:    encodeSpaceField(post.CaptionCipher),
		KeyVersion:       post.KeyVersion,
		CreatedAt:        formatMicros(post.CreatedAt),
		ViewerLiked:      post.ViewerLiked,
	}
	if len(assets) > 0 {
		resp.Objects = make([]models.PostObjectPayload, 0, len(assets))
		for _, asset := range assets {
			resp.Objects = append(resp.Objects, toPostObjectPayload(asset))
		}
	}
	return resp
}
