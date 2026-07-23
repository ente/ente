package legacy_kit

import (
	"testing"
	"time"

	"github.com/ente/museum/ente"
	legacykitrepo "github.com/ente/museum/pkg/repo/legacy_kit"
	timeutil "github.com/ente/museum/pkg/utils/time"
	"github.com/google/uuid"
	"github.com/spf13/viper"
	"github.com/stretchr/testify/require"
)

func TestLegacyURLUsesDefaultWhenUnset(t *testing.T) {
	previousURL := viper.GetString("apps.legacy")
	viper.Set("apps.legacy", "")
	t.Cleanup(func() {
		viper.Set("apps.legacy", previousURL)
	})

	require.Equal(t, defaultLegacyURL, legacyURL())
}

func TestLegacyURLUsesConfiguredURLWithoutTrailingSlash(t *testing.T) {
	previousURL := viper.GetString("apps.legacy")
	viper.Set("apps.legacy", " http://localhost:3013/ ")
	t.Cleanup(func() {
		viper.Set("apps.legacy", previousURL)
	})

	require.Equal(t, "http://localhost:3013", legacyURL())
}

func TestToRecoverySessionReturnsRemainingWaitTime(t *testing.T) {
	row := &legacykitrepo.RecoverySessionRow{
		ID:        uuid.New(),
		KitID:     uuid.New(),
		Status:    ente.LegacyKitRecoveryStatusWaiting,
		WaitTill:  timeutil.MicrosecondsAfterHours(1),
		CreatedAt: timeutil.Microseconds(),
	}

	session := toRecoverySession(row)

	require.Equal(t, ente.LegacyKitRecoveryStatusWaiting, session.Status)
	require.Greater(t, session.WaitTill, int64(0))
	require.LessOrEqual(t, session.WaitTill, time.Hour.Microseconds())
}

func TestToRecoverySessionMarksExpiredWaitingSessionReady(t *testing.T) {
	row := &legacykitrepo.RecoverySessionRow{
		ID:        uuid.New(),
		KitID:     uuid.New(),
		Status:    ente.LegacyKitRecoveryStatusWaiting,
		WaitTill:  timeutil.Microseconds() - 1,
		CreatedAt: timeutil.Microseconds(),
	}

	session := toRecoverySession(row)

	require.Equal(t, ente.LegacyKitRecoveryStatusReady, session.Status)
	require.Equal(t, int64(0), session.WaitTill)
}
