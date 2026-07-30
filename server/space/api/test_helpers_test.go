package api

import (
	"context"

	spacerepo "github.com/ente/museum/space/repo"
)

func testSpaceBytes(value string) []byte {
	return []byte(value)
}

func testCreateSpace(ctx context.Context, module *spacerepo.Module, ownerID int64, spaceSlug string, rootWrappedSpaceKey string, publicKey string, encryptedSecretKey string, _ string, encryptedProfile string) (*spacerepo.SpaceRecord, error) {
	return module.Spaces.CreateSpace(ctx, ownerID, spaceSlug, testSpaceBytes(rootWrappedSpaceKey), testSpaceBytes(publicKey), testSpaceBytes(encryptedSecretKey), testSpaceBytes(encryptedProfile), "")
}
