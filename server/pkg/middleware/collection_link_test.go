package middleware

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestShouldCheckCollectionLinkDeviceLimit(t *testing.T) {
	require.True(t, shouldCheckCollectionLinkDeviceLimit("/public-collection/info"))
	require.True(t, shouldCheckCollectionLinkDeviceLimit("/public-collection/diff"))

	require.False(t, shouldCheckCollectionLinkDeviceLimit("/public-collection/files/download/1"))
	require.False(t, shouldCheckCollectionLinkDeviceLimit("/public-collection/upload-url"))
	require.False(t, shouldCheckCollectionLinkDeviceLimit("/public-collection/verify-password"))
}
