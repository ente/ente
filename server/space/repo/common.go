package repo

import (
	"fmt"
	"strings"

	"github.com/ente/museum/ente"
	"github.com/ente/stacktrace"
)

func normalizeSlug(input string) string {
	return strings.ToLower(strings.TrimSpace(input))
}

func optionalInt(limit int, fallback int) int {
	if limit <= 0 {
		return fallback
	}
	return limit
}

const spaceRecordSelectColumns = `
	s.space_id,
	s.owner_id,
	s.space_slug,
	s.root_wrapped_space_key,
	s.encrypted_profile,
	s.current_version,
	s.public_key,
	s.encrypted_secret_key,
	s.referred_by_space_id,
	avatar.object_id AS avatar_object_id,
	avatar.key_version AS avatar_key_version,
	avatar.size AS avatar_size,
	cover.object_id AS cover_object_id,
	cover.key_version AS cover_key_version,
	cover.size AS cover_size,
	s.created_at,
	s.updated_at
`

const spaceRecordProfileAssetJoins = `
	LEFT JOIN space_profile_assets avatar
	  ON avatar.space_id = s.space_id
	 AND avatar.asset_type = 'avatar'
	LEFT JOIN space_profile_assets cover
	  ON cover.space_id = s.space_id
	 AND cover.asset_type = 'cover'
`

func spaceActorScanDest(actor *SpaceActorRecord) []any {
	return []any{
		&actor.SpaceID,
		&actor.SpaceSlug,
		&actor.PublicKey,
		&actor.KeyVersion,
		&actor.EncryptedProfile,
		&actor.AvatarObjectID,
		&actor.AvatarKeyVersion,
		&actor.AvatarSize,
		&actor.UpdatedAt,
	}
}

func spaceActorSelectColumns(spaceAlias string, avatarAlias string, prefix string) string {
	return strings.Join([]string{
		fmt.Sprintf("%s.space_id AS %s_space_id", spaceAlias, prefix),
		fmt.Sprintf("%s.space_slug AS %s_space_slug", spaceAlias, prefix),
		fmt.Sprintf("%s.public_key AS %s_public_key", spaceAlias, prefix),
		fmt.Sprintf("%s.current_version AS %s_current_version", spaceAlias, prefix),
		fmt.Sprintf("%s.encrypted_profile AS %s_encrypted_profile", spaceAlias, prefix),
		fmt.Sprintf("%s.object_id AS %s_avatar_object_id", avatarAlias, prefix),
		fmt.Sprintf("%s.key_version AS %s_avatar_key_version", avatarAlias, prefix),
		fmt.Sprintf("%s.size AS %s_avatar_size", avatarAlias, prefix),
		fmt.Sprintf("%s.updated_at AS %s_updated_at", spaceAlias, prefix),
	}, ",\n\t")
}

func spaceActorPublicSelectColumns(spaceAlias string, prefix string) string {
	return strings.Join([]string{
		fmt.Sprintf("%s.space_id AS %s_space_id", spaceAlias, prefix),
		fmt.Sprintf("%s.space_slug AS %s_space_slug", spaceAlias, prefix),
		fmt.Sprintf("%s.public_key AS %s_public_key", spaceAlias, prefix),
		fmt.Sprintf("%s.current_version AS %s_current_version", spaceAlias, prefix),
		fmt.Sprintf("'\\x'::bytea AS %s_encrypted_profile", prefix),
		fmt.Sprintf("NULL::text AS %s_avatar_object_id", prefix),
		fmt.Sprintf("NULL::integer AS %s_avatar_key_version", prefix),
		fmt.Sprintf("NULL::bigint AS %s_avatar_size", prefix),
		fmt.Sprintf("%s.updated_at AS %s_updated_at", spaceAlias, prefix),
	}, ",\n\t")
}

func spaceActorAvatarJoin(spaceAlias string, avatarAlias string) string {
	return fmt.Sprintf("LEFT JOIN space_profile_assets %s ON %s.space_id = %s.space_id AND %s.asset_type = 'avatar'", avatarAlias, avatarAlias, spaceAlias, avatarAlias)
}

func wrapUnique(err error, message string) error {
	if err == nil {
		return nil
	}
	if strings.Contains(strings.ToLower(err.Error()), "duplicate key value") {
		return ente.NewAlreadyExistsError(message)
	}
	return stacktrace.Propagate(err, "")
}
