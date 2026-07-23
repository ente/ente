package legacy_kit

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"strings"

	ctrl "github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/controller/user"
	"github.com/ente/museum/pkg/repo"
	legacykitrepo "github.com/ente/museum/pkg/repo/legacy_kit"
	servercrypto "github.com/ente/museum/pkg/utils/crypto"
	"github.com/ente/museum/pkg/utils/network"
	timeutil "github.com/ente/museum/pkg/utils/time"

	"github.com/ente/museum/ente"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/spf13/viper"
)

var validNoticePeriods = map[int]struct{}{
	0:   {},
	24:  {},
	168: {},
	360: {},
	720: {},
}

const (
	maxActiveLegacyKits = 5
	defaultLegacyURL    = "https://legacy.ente.com"
)

type Controller struct {
	Repo              *legacykitrepo.Repository
	UserRepo          *repo.UserRepository
	UserCtrl          *user.UserController
	PasskeyController *ctrl.PasskeyController
}

func (c *Controller) CreateKit(ctx *gin.Context, userID int64, req ente.CreateLegacyKitRequest) (*ente.LegacyKit, error) {
	if req.NoticePeriodInHours == nil {
		return nil, stacktrace.Propagate(ente.NewBadRequestWithMessage("legacy kit notice period is required"), "")
	}
	if err := validateLegacyKitVariant(req.Variant); err != nil {
		return nil, err
	}
	if err := validateNoticePeriod(*req.NoticePeriodInHours); err != nil {
		return nil, err
	}
	if err := servercrypto.ValidateSealedBoxPublicKey(req.AuthPublicKey); err != nil {
		return nil, stacktrace.Propagate(ente.NewBadRequestWithMessage("invalid legacy kit auth public key"), "")
	}
	if err := c.Repo.CreateKitWithLimit(ctx, userID, req, maxActiveLegacyKits); err != nil {
		return nil, err
	}
	row, err := c.Repo.GetKitForOwner(ctx, userID, req.ID)
	if err != nil {
		return nil, err
	}
	return toLegacyKit(row, nil), nil
}

func (c *Controller) ListKits(ctx *gin.Context, userID int64) (*ente.ListLegacyKitsResponse, error) {
	kits, err := c.Repo.ListKits(ctx, userID)
	if err != nil {
		return nil, err
	}
	sessions, err := c.Repo.ListActiveSessionsForUser(ctx, userID)
	if err != nil {
		return nil, err
	}
	sessionByKit := make(map[uuid.UUID]*legacykitrepo.RecoverySessionRow, len(sessions))
	for i := range sessions {
		session := sessions[i]
		sessionByKit[session.KitID] = &session
	}

	resp := &ente.ListLegacyKitsResponse{Kits: make([]*ente.LegacyKit, 0, len(kits))}
	for i := range kits {
		row := kits[i]
		resp.Kits = append(resp.Kits, toLegacyKit(&row, sessionByKit[row.ID]))
	}
	return resp, nil
}

func (c *Controller) DownloadKitContent(ctx *gin.Context, userID int64, kitID uuid.UUID) (*ente.LegacyKitDownloadContentResponse, error) {
	row, err := c.Repo.GetKitForOwner(ctx, userID, kitID)
	if err != nil {
		return nil, err
	}
	return &ente.LegacyKitDownloadContentResponse{
		ID:                 row.ID,
		Variant:            row.Variant,
		EncryptedOwnerBlob: row.EncryptedOwnerBlob,
	}, nil
}

func (c *Controller) UpdateRecoveryNotice(ctx *gin.Context, userID int64, req ente.UpdateLegacyKitRecoveryNoticeRequest) error {
	if req.NoticePeriodInHours == nil {
		return stacktrace.Propagate(ente.NewBadRequestWithMessage("legacy kit notice period is required"), "")
	}
	if err := validateNoticePeriod(*req.NoticePeriodInHours); err != nil {
		return err
	}
	updated, err := c.Repo.UpdateRecoveryNotice(ctx, userID, req.KitID, int32(*req.NoticePeriodInHours))
	if err != nil {
		return err
	}
	if !updated {
		return stacktrace.Propagate(ente.ErrNotFound, "legacy kit not found")
	}
	return nil
}

func (c *Controller) DeleteKit(ctx *gin.Context, userID int64, kitID uuid.UUID) error {
	updated, err := c.Repo.DeleteKit(ctx, userID, kitID)
	if err != nil {
		return err
	}
	if !updated {
		return stacktrace.Propagate(ente.ErrNotFound, "legacy kit not found")
	}
	return nil
}

func (c *Controller) BlockRecovery(ctx *gin.Context, userID int64, kitID uuid.UUID) error {
	// Current product semantics: blocking cancels only the active WAITING/READY
	// session. The kit itself remains usable, so a holder can start a new
	// recovery session later unless product semantics change.
	updated, err := c.Repo.BlockActiveSessionForKit(ctx, kitID, userID)
	if err != nil {
		return err
	}
	if !updated {
		return stacktrace.Propagate(ente.ErrNotFound, "active legacy kit recovery session not found")
	}
	return nil
}

func (c *Controller) GetOwnerRecoverySession(
	ctx context.Context,
	userID int64,
	kitID uuid.UUID,
) (*ente.LegacyKitOwnerRecoverySessionResponse, error) {
	if _, err := c.Repo.GetKitForOwner(ctx, userID, kitID); err != nil {
		return nil, err
	}
	session, err := c.Repo.GetActiveSessionByKit(ctx, kitID)
	if err != nil {
		return nil, err
	}
	if session == nil {
		return &ente.LegacyKitOwnerRecoverySessionResponse{
			Session:    nil,
			Initiators: []ente.LegacyKitRecoveryInitiator{},
		}, nil
	}
	recoverySession := toRecoverySession(session)
	return &ente.LegacyKitOwnerRecoverySessionResponse{
		Session:    &recoverySession,
		Initiators: session.Initiators,
	}, nil
}

func (c *Controller) CreateChallenge(ctx context.Context, req ente.LegacyKitChallengeRequest) (*ente.LegacyKitChallengeResponse, error) {
	kit, err := c.Repo.GetKitByID(ctx, req.KitID)
	if err != nil {
		return nil, err
	}
	if kit.IsDeleted {
		return nil, stacktrace.Propagate(ente.ErrNotFound, "legacy kit not found")
	}
	challengeBytes := make([]byte, 32)
	rand.Read(challengeBytes)
	challenge := base64.StdEncoding.EncodeToString(challengeBytes)
	challenge = formatChallenge(req.KitID, challenge)
	encryptedChallenge, err := servercrypto.GetEncryptedToken(base64.URLEncoding.EncodeToString([]byte(challenge)), kit.AuthPublicKey)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to seal legacy kit challenge")
	}
	expiresAt := timeutil.MicrosecondsAfterHours(1)
	if err := c.Repo.CreateChallenge(ctx, req.KitID, challenge, expiresAt); err != nil {
		return nil, err
	}
	return &ente.LegacyKitChallengeResponse{
		KitID:              req.KitID,
		EncryptedChallenge: encryptedChallenge,
		ExpiresAt:          expiresAt,
	}, nil
}

func (c *Controller) OpenRecovery(ctx *gin.Context, req ente.LegacyKitOpenRecoveryRequest) (*ente.LegacyKitOpenRecoveryResponse, error) {
	if err := validateUsedPartIndexes(req.UsedPartIndexes, ente.LegacyKitVariantTwoOfThree); err != nil {
		return nil, err
	}
	initiator := &ente.LegacyKitRecoveryInitiator{
		UsedPartIndexes: req.UsedPartIndexes,
		IP:              network.GetClientIP(ctx),
		UserAgent:       strings.TrimSpace(ctx.GetHeader("User-Agent")),
	}
	kit, session, sessionToken, createdSession, err := c.Repo.OpenOrResumeRecovery(
		ctx,
		req.KitID,
		req.Challenge,
		timeutil.Microseconds(),
		initiator,
	)
	if err != nil {
		return nil, err
	}
	if createdSession {
		go c.sendRecoveryStartedNotification(context.Background(), kit.UserID, session, req.Email)
	}
	return &ente.LegacyKitOpenRecoveryResponse{
		Session:      toRecoverySession(session),
		SessionToken: sessionToken,
	}, nil
}

func (c *Controller) GetSession(ctx context.Context, req ente.LegacyKitSessionRequest) (*ente.LegacyKitRecoverySession, error) {
	session, err := c.Repo.GetSessionByIDAndTokenForUse(ctx, req.SessionID, strings.TrimSpace(req.SessionToken), timeutil.Microseconds())
	if err != nil {
		return nil, err
	}
	if session == nil {
		return nil, stacktrace.Propagate(ente.ErrNotFound, "legacy kit recovery session not found")
	}
	recoverySession := toRecoverySession(session)
	return &recoverySession, nil
}

func (c *Controller) GetRecoveryInfo(ctx context.Context, req ente.LegacyKitSessionRequest) (*ente.LegacyKitRecoveryInfoResponse, error) {
	session, err := c.Repo.GetSessionByIDAndTokenForUse(ctx, req.SessionID, strings.TrimSpace(req.SessionToken), timeutil.Microseconds())
	if err != nil {
		return nil, err
	}
	if session == nil {
		return nil, stacktrace.Propagate(ente.ErrNotFound, "legacy kit recovery session not found")
	}
	if session.Status != ente.LegacyKitRecoveryStatusReady {
		return nil, stacktrace.Propagate(ente.NewBadRequestWithMessage("legacy kit recovery is not ready"), "")
	}
	kit, err := c.Repo.GetKitByID(ctx, session.KitID)
	if err != nil {
		return nil, err
	}
	keyAttr, err := c.UserRepo.GetKeyAttributes(session.UserID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to fetch user key attributes")
	}
	return &ente.LegacyKitRecoveryInfoResponse{
		EncryptedRecoveryBlob: kit.EncryptedRecoveryBlob,
		UserKeyAttr:           keyAttr,
	}, nil
}

func (c *Controller) InitChangePassword(ctx *gin.Context, req ente.LegacyKitRecoverySrpSetupRequest) (*ente.SetupSRPResponse, error) {
	session, err := c.Repo.GetSessionByIDAndTokenForUse(ctx, req.SessionID, strings.TrimSpace(req.SessionToken), timeutil.Microseconds())
	if err != nil {
		return nil, err
	}
	if session == nil {
		return nil, stacktrace.Propagate(ente.ErrNotFound, "legacy kit recovery session not found")
	}
	if session.Status != ente.LegacyKitRecoveryStatusReady {
		return nil, stacktrace.Propagate(ente.NewBadRequestWithMessage("legacy kit recovery is not ready"), "")
	}
	resp, err := c.UserCtrl.SetupSRP(ctx, session.UserID, req.SetupSRPRequest)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to initialize legacy kit password reset")
	}
	return resp, nil
}

func (c *Controller) ChangePassword(ctx *gin.Context, req ente.LegacyKitRecoveryUpdateSRPRequest) (*ente.UpdateSRPSetupResponse, error) {
	session, err := c.Repo.GetSessionByIDAndTokenForUse(ctx, req.SessionID, strings.TrimSpace(req.SessionToken), timeutil.Microseconds())
	if err != nil {
		return nil, err
	}
	if session == nil {
		return nil, stacktrace.Propagate(ente.ErrNotFound, "legacy kit recovery session not found")
	}
	if session.Status != ente.LegacyKitRecoveryStatusReady {
		return nil, stacktrace.Propagate(ente.NewBadRequestWithMessage("legacy kit recovery is not ready"), "")
	}
	// Known and accepted for the current recovery flow: once a legacy-kit session
	// is READY, we clear existing second-factor requirements before applying the
	// recovered password update, so an old TOTP/passkey enrollment does not block
	// the beneficiary from completing takeover.
	if err := c.UserCtrl.DisableTwoFactor(session.UserID); err != nil {
		return nil, stacktrace.Propagate(err, "failed to disable two-factor")
	}
	if err := c.PasskeyController.RemovePasskey2FA(session.UserID); err != nil {
		return nil, stacktrace.Propagate(err, "failed to disable passkeys")
	}
	resp, err := c.UserCtrl.UpdateSrpAndKeyAttributes(ctx, session.UserID, req.UpdateSrpAndKeysRequest, false)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to update password via legacy kit")
	}
	if _, err := c.Repo.UpdateSessionStatus(ctx, session.ID, ente.LegacyKitRecoveryStatusRecovered); err != nil {
		return nil, err
	}
	go c.sendRecoveryCompletedNotification(context.Background(), session.UserID)
	return resp, nil
}

func toLegacyKit(row *legacykitrepo.KitRow, session *legacykitrepo.RecoverySessionRow) *ente.LegacyKit {
	kit := &ente.LegacyKit{
		ID:                  row.ID,
		Variant:             row.Variant,
		NoticePeriodInHours: row.NoticePeriodInHrs,
		LegacyURL:           legacyURL(),
		EncryptedOwnerBlob:  row.EncryptedOwnerBlob,
		CreatedAt:           row.CreatedAt,
		UpdatedAt:           row.UpdatedAt,
	}
	if session != nil {
		recoverySession := toRecoverySession(session)
		kit.ActiveRecoverySession = &recoverySession
	}
	return kit
}

func legacyURL() string {
	url := strings.TrimRight(strings.TrimSpace(viper.GetString("apps.legacy")), "/")
	if url == "" {
		return defaultLegacyURL
	}
	return url
}

func toRecoverySession(row *legacykitrepo.RecoverySessionRow) ente.LegacyKitRecoverySession {
	waitRemaining := max(row.WaitTill-timeutil.Microseconds(), 0)
	status := row.Status
	if status == ente.LegacyKitRecoveryStatusWaiting && waitRemaining == 0 {
		status = ente.LegacyKitRecoveryStatusReady
	}
	return ente.LegacyKitRecoverySession{
		ID:        row.ID,
		KitID:     row.KitID,
		Status:    status,
		WaitTill:  waitRemaining,
		CreatedAt: row.CreatedAt,
	}
}

func validateNoticePeriod(hours int) error {
	if _, ok := validNoticePeriods[hours]; !ok {
		return stacktrace.Propagate(ente.NewBadRequestWithMessage("invalid legacy kit notice period"), "")
	}
	return nil
}

func validateLegacyKitVariant(variant ente.LegacyKitVariant) error {
	switch variant {
	case ente.LegacyKitVariantTwoOfThree:
		return nil
	default:
		return stacktrace.Propagate(ente.NewBadRequestWithMessage("invalid legacy kit variant"), "")
	}
}

func legacyKitVariantConfig(variant ente.LegacyKitVariant) (threshold int, partCount int, err error) {
	switch variant {
	case ente.LegacyKitVariantTwoOfThree:
		return 2, 3, nil
	default:
		return 0, 0, stacktrace.Propagate(ente.NewBadRequestWithMessage("invalid legacy kit variant"), "")
	}
}

func validateUsedPartIndexes(indexes []int, variant ente.LegacyKitVariant) error {
	if len(indexes) == 0 {
		return nil
	}
	threshold, partCount, err := legacyKitVariantConfig(variant)
	if err != nil {
		return err
	}
	if len(indexes) != threshold {
		return stacktrace.Propagate(ente.NewBadRequestWithMessage("legacy kit usedPartIndexes count does not match kit variant"), "")
	}
	seen := make(map[int]struct{}, len(indexes))
	for _, index := range indexes {
		if index < 1 || index > partCount {
			return stacktrace.Propagate(ente.NewBadRequestWithMessage("legacy kit usedPartIndexes is outside kit variant range"), "")
		}
		if _, ok := seen[index]; ok {
			return stacktrace.Propagate(ente.NewBadRequestWithMessage("legacy kit usedPartIndexes must be unique"), "")
		}
		seen[index] = struct{}{}
	}
	return nil
}

func formatChallenge(kitID uuid.UUID, challenge string) string {
	return fmt.Sprintf("legacy-kit-open:v1\n%s\n%s\n", kitID.String(), challenge)
}
