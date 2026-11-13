package storagebonus

import (
	"net/http"
	"testing"

	"github.com/ente/museum/ente"
	entity "github.com/ente/museum/ente/storagebonus"
	"github.com/stretchr/testify/require"
)

func TestTrackReferralAndInviteeBonusAlreadyApplied(t *testing.T) {
	ctx := t.Context()
	repo := newStorageBonusTestRepository(t)
	invitee := int64(101)
	firstCodeOwner := int64(102)
	secondCodeOwner := int64(103)

	require.NoError(t, repo.TrackReferralAndInviteeBonus(ctx, invitee, firstCodeOwner, entity.TenGbOnUpgrade))

	err := repo.TrackReferralAndInviteeBonus(ctx, invitee, secondCodeOwner, entity.TenGbOnUpgrade)
	require.ErrorIs(t, err, entity.CodeAlreadyAppliedErr)
	var apiErr *ente.ApiError
	require.ErrorAs(t, err, &apiErr)
	require.Equal(t, http.StatusConflict, apiErr.HttpStatusCode)
	require.Equal(t, entity.CodeAlreadyAppliedErr.Code, apiErr.Code)

	var trackingCount int
	require.NoError(t, repo.DB.QueryRowContext(ctx, "SELECT COUNT(*) FROM referral_tracking WHERE invitee_id = $1", invitee).Scan(&trackingCount))
	require.Equal(t, 1, trackingCount)

	var bonusCount int
	require.NoError(t, repo.DB.QueryRowContext(ctx, "SELECT COUNT(*) FROM storage_bonus WHERE user_id = $1 AND type = $2", invitee, entity.SignUp).Scan(&bonusCount))
	require.Equal(t, 1, bonusCount)
}
