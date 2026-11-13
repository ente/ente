package repo

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"errors"
	"testing"

	"github.com/ente/stacktrace"
	"github.com/stretchr/testify/require"
)

func TestSpaceLinkLifecycle(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := context.Background()
	ownerID := insertSpaceUser(t, module, "space-link@example.com", "space-link-public")
	space, err := testCreateSpace(ctx, module, ownerID, "space_link", "root", "public", "secret", "nonce", "profile")
	require.NoError(t, err)

	auth := sha256.Sum256([]byte("first-auth-key"))
	link, err := module.Links.Create(
		ctx,
		space.SpaceID,
		auth[:],
		make([]byte, 16),
		67_108_864,
		2,
		space.CurrentVersion,
		[]byte("first-encrypted-space-key"),
		[]byte("first-encrypted-access-key"),
	)
	require.NoError(t, err)
	require.True(t, link.Active)
	require.Equal(t, "space_link", link.SpaceSlug)

	existing, err := module.Links.Create(
		ctx,
		space.SpaceID,
		[]byte("different-auth-key"),
		make([]byte, 16),
		67_108_864,
		2,
		space.CurrentVersion,
		[]byte("different-space-key"),
		[]byte("different-access-key"),
	)
	require.NoError(t, err)
	require.Equal(t, link.LinkID, existing.LinkID)

	authorized, err := module.Links.GetActiveBySlugAndAuthHash(ctx, space.SpaceSlug, auth[:])
	require.NoError(t, err)
	require.Equal(t, link.LinkID, authorized.LinkID)

	nextAuth := sha256.Sum256([]byte("second-auth-key"))
	rotated, err := module.Links.Rotate(
		ctx,
		space.SpaceID,
		nextAuth[:],
		make([]byte, 16),
		67_108_864,
		2,
		space.CurrentVersion,
		[]byte("second-encrypted-space-key"),
		[]byte("second-encrypted-access-key"),
	)
	require.NoError(t, err)
	require.NotEqual(t, link.LinkID, rotated.LinkID)
	_, err = module.Links.GetActiveBySlugAndAuthHash(ctx, space.SpaceSlug, auth[:])
	require.True(t, errors.Is(stacktrace.RootCause(err), sql.ErrNoRows))
	authorized, err = module.Links.GetActiveBySlugAndAuthHash(ctx, space.SpaceSlug, nextAuth[:])
	require.NoError(t, err)
	require.Equal(t, rotated.LinkID, authorized.LinkID)
}

func TestSpaceKeyRotationRewrapsOrDisablesActiveLink(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := context.Background()
	ownerID := insertSpaceUser(t, module, "space-link-rotation@example.com", "space-link-rotation-public")
	space, err := testCreateSpace(ctx, module, ownerID, "space_link_rotation", "root", "public", "secret", "nonce", "profile")
	require.NoError(t, err)

	auth := sha256.Sum256([]byte("rotation-auth-key"))
	link, err := module.Links.Create(
		ctx,
		space.SpaceID,
		auth[:],
		make([]byte, 16),
		67_108_864,
		2,
		space.CurrentVersion,
		[]byte("encrypted-space-key-v1"),
		[]byte("encrypted-access-key"),
	)
	require.NoError(t, err)
	expectedLinkID := link.LinkID
	endpoint := "https://push.example/key-rotation"
	_, err = module.WebPush.UpsertLinkSubscription(ctx, link.LinkID, endpoint, "p256dh", "auth")
	require.NoError(t, err)

	rotated, err := module.Spaces.RotateKey(
		ctx,
		space.SpaceID,
		space.CurrentVersion,
		[]byte("root-v2"),
		[]byte("wrapped-v1"),
		[]byte("profile-v2"),
		&expectedLinkID,
		[]byte("encrypted-space-key-v2"),
	)
	require.NoError(t, err)
	link, err = module.Links.GetActive(ctx, space.SpaceID)
	require.NoError(t, err)
	require.Equal(t, rotated.CurrentVersion, link.KeyVersion)
	require.Equal(t, []byte("encrypted-space-key-v2"), link.EncryptedSpaceKey)
	require.Equal(t, int64(1), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_web_push_subscriptions WHERE endpoint = $1`, endpoint))

	_, err = module.Spaces.RotateKey(
		ctx,
		space.SpaceID,
		rotated.CurrentVersion,
		[]byte("root-v3"),
		[]byte("wrapped-v2"),
		[]byte("profile-v3"),
		nil,
		nil,
	)
	require.NoError(t, err)
	_, err = module.Links.GetActive(ctx, space.SpaceID)
	require.True(t, errors.Is(stacktrace.RootCause(err), sql.ErrNoRows))
	require.Equal(t, int64(0), countSpaceRows(t, module, `SELECT COUNT(*) FROM space_web_push_subscriptions WHERE endpoint = $1`, endpoint))
}
