package legacy_kit

import (
	"testing"

	"github.com/ente/museum/ente"
	legacykitrepo "github.com/ente/museum/pkg/repo/legacy_kit"
	timeutil "github.com/ente/museum/pkg/utils/time"
	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

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
