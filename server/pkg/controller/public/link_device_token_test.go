package public

import (
	"testing"

	"github.com/ente/museum/pkg/utils/time"
	"github.com/stretchr/testify/require"
)

func TestLinkDeviceTokenValidation(t *testing.T) {
	secret := []byte("test-secret")
	token, _, err := NewLinkDeviceToken(secret, LinkDeviceScopeCollection, "123", "ACCESS", 0)
	require.NoError(t, err)

	claim, err := ValidateLinkDeviceToken(secret, token, LinkDeviceScopeCollection, "123", "ACCESS")
	require.NoError(t, err)
	require.Equal(t, LinkDeviceScopeCollection, claim.Scope)
	require.Equal(t, "123", claim.LinkID)

	_, err = ValidateLinkDeviceToken(secret, token, LinkDeviceScopeFile, "123", "ACCESS")
	require.Error(t, err)

	_, err = ValidateLinkDeviceToken(secret, token, LinkDeviceScopeCollection, "456", "ACCESS")
	require.Error(t, err)

	_, err = ValidateLinkDeviceToken(secret, token, LinkDeviceScopeCollection, "123", "OTHER")
	require.Error(t, err)
}

func TestLinkDeviceTokenExpiryIsCappedByLinkExpiry(t *testing.T) {
	secret := []byte("test-secret")
	validTill := time.MicrosecondsAfterHours(1)

	token, expiry, err := NewLinkDeviceToken(secret, LinkDeviceScopeCollection, "123", "ACCESS", validTill)
	require.NoError(t, err)
	require.Equal(t, validTill, expiry)

	claim, err := ValidateLinkDeviceToken(secret, token, LinkDeviceScopeCollection, "123", "ACCESS")
	require.NoError(t, err)
	require.Equal(t, validTill, claim.ExpiryTime)
}

func TestExpiredLinkDeviceTokenIsRejected(t *testing.T) {
	secret := []byte("test-secret")
	token, _, err := NewLinkDeviceToken(secret, LinkDeviceScopeCollection, "123", "ACCESS", time.MicrosecondsBeforeDays(1))
	require.NoError(t, err)

	_, err = ValidateLinkDeviceToken(secret, token, LinkDeviceScopeCollection, "123", "ACCESS")
	require.Error(t, err)
}
