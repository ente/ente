package remotestore

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"

	"github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/rollout"
	"github.com/spf13/viper"
	"golang.org/x/net/idna"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/repo/remotestore"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	"github.com/sirupsen/logrus"
)

const (
	videoStreamingRolloutPercentage = 75
	videoStreamingRolloutNonce      = "video-streaming-v1"
)

// Controller is interface for exposing business logic related to for remote store
type Controller struct {
	Repo        *remotestore.Repository
	BillingCtrl *controller.BillingController
	UserRepo    *repo.UserRepository
	FamilyRepo  *repo.FamilyRepository
}

// InsertOrUpdate the key's value
func (c *Controller) InsertOrUpdate(ctx *gin.Context, request ente.UpdateKeyValueRequest) error {
	userID := auth.GetUserID(ctx.Request.Header)
	if err := c._validateRequest(userID, request.Key, request.Value, false); err != nil {
		return err
	}
	if request.Key == string(ente.CustomDomain) {
		return c.insertOrUpdateCustomDomain(ctx, userID, *request.Value)
	}
	if *request.Value == "" && ente.FlagKey(request.Key).CanRemove() {
		return c.Repo.RemoveKey(ctx, userID, request.Key)
	}
	return c.Repo.InsertOrUpdate(ctx, userID, request.Key, *request.Value)
}

// RemoveKey removes the key from remote store
func (c *Controller) RemoveKey(ctx *gin.Context, key string) error {
	userID := auth.GetUserID(ctx.Request.Header)
	if valid := ente.IsValidFlagKey(key); !valid {
		return stacktrace.Propagate(ente.NewBadRequestWithMessage(fmt.Sprintf("key %s is not allowed", key)), "invalid flag key")
	}
	if !ente.FlagKey(key).CanRemove() {
		return stacktrace.Propagate(ente.NewBadRequestWithMessage(fmt.Sprintf("key %s is not removable", key)), "key not removable")
	}
	if err := c.Repo.RemoveKey(ctx, userID, key); err != nil {
		return err
	}
	if key == string(ente.CustomDomain) {
		return c.clearFamilyCustomDomainsIfAdmin(ctx, userID)
	}
	return nil
}

func (c *Controller) AdminInsertOrUpdate(ctx *gin.Context, request ente.AdminUpdateKeyValueRequest) error {
	if err := c._validateRequest(request.UserID, request.Key, request.Value, true); err != nil {
		return err
	}
	if request.Key == string(ente.CustomDomain) {
		return c.insertOrUpdateCustomDomain(ctx, request.UserID, *request.Value)
	}
	return c.Repo.InsertOrUpdate(ctx, request.UserID, request.Key, *request.Value)
}

func (c *Controller) Get(ctx *gin.Context, req ente.GetValueRequest) (*ente.GetValueResponse, error) {
	userID := auth.GetUserID(ctx.Request.Header)
	value, err := c.Repo.GetValue(ctx, userID, req.Key)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) && req.DefaultValue != nil {
			return &ente.GetValueResponse{Value: *req.DefaultValue}, nil
		} else {
			return nil, stacktrace.Propagate(err, "")
		}
	}
	if req.Key == string(ente.CustomDomain) {
		resolved, resolveErr := ente.ResolveCustomDomainValue(value)
		if resolveErr != nil {
			return nil, stacktrace.Propagate(resolveErr, "")
		}
		value = resolved
	}
	return &ente.GetValueResponse{Value: value}, nil
}

func (c *Controller) GetFeatureFlags(ctx *gin.Context) (*ente.FeatureFlagResponse, error) {
	userID := auth.GetUserID(ctx.Request.Header)
	values, err := c.Repo.GetAllValues(ctx, userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	response := &ente.FeatureFlagResponse{
		EnableStripe:    true, // enable stripe for all
		DisableCFWorker: false,
		// When true, users will see an option to enable multiple part upload in the app
		// Changing it to false will hide the option and disable multi part upload for everyone
		// except internal user.rt
		EnableMobMultiPart: true,
		ServerApiFlag:      ente.UploadV2 | ente.Comments | ente.BackupOptions | ente.CastSessionsV2,
		CastUrl:            viper.GetString("apps.cast"),
		EmbedUrl:           viper.GetString("apps.embed-albums"),
		CustomDomainCNAME:  viper.GetString("apps.custom-domain.cname"),
	}
	for key, value := range values {
		flag := ente.FlagKey(key)
		switch flag {
		case ente.RecoveryKeyVerified:
			response.RecoveryKeyVerified = value == "true"
		case ente.MapEnabled:
			response.MapEnabled = value == "true"
		case ente.FaceSearchEnabled:
			response.FaceSearchEnabled = value == "true"
		case ente.PassKeyEnabled:
			response.PassKeyEnabled = value == "true"
		case ente.IsInternalUser:
			response.InternalUser = value == "true"
		case ente.IsBetaUser:
			response.BetaUser = value == "true"
		case ente.CustomDomain:
			if value != "" {
				resolved, resolveErr := ente.ResolveCustomDomainValue(value)
				if resolveErr != nil {
					return nil, stacktrace.Propagate(resolveErr, "")
				}
				if resolved != "" {
					response.CustomDomain = &resolved
				}
			}
		}
	}

	if response.InternalUser ||
		rollout.IsInPercentageRollout(userID, videoStreamingRolloutNonce, videoStreamingRolloutPercentage) {
		response.ServerApiFlag |= ente.VideoStreaming
	}

	return response, nil
}

func (c *Controller) insertOrUpdateCustomDomain(ctx *gin.Context, userID int64, value string) error {
	if value == "" {
		if err := c.Repo.RemoveKey(ctx, userID, string(ente.CustomDomain)); err != nil {
			return err
		}
		return c.clearFamilyCustomDomainsIfAdmin(ctx, userID)
	}
	if strings.HasPrefix(value, "_") {
		return stacktrace.Propagate(ente.NewBadRequestWithMessage("invalid custom domain"), "family pointer not allowed in request")
	}
	if isReservedCustomDomain(value, viper.GetString("apps.custom-domain.cname")) {
		return stacktrace.Propagate(ente.NewBadRequestWithMessage("custom domain is reserved"), "reserved custom domain")
	}
	ownerID, err := c.DomainOwner(ctx, value)
	if err == nil {
		if ownerID != nil && *ownerID == userID {
			if err := c.Repo.InsertOrUpdate(ctx, userID, string(ente.CustomDomain), value); err != nil {
				return err
			}
			return c.updateFamilyCustomDomainsIfAdmin(ctx, userID, value)
		}
		familyAdminID, adminErr := c.UserRepo.GetFamilyAdminID(userID)
		if adminErr != nil {
			return stacktrace.Propagate(adminErr, "")
		}
		if familyAdminID != nil && ownerID != nil && *familyAdminID == *ownerID {
			adminDomain, domainErr := c.Repo.GetDomain(ctx, *ownerID)
			if domainErr != nil {
				return domainErr
			}
			if adminDomain == nil || *adminDomain == "" {
				return stacktrace.Propagate(ente.NewBadRequestWithMessage("family admin has no custom domain"), "")
			}
			pointer := ente.BuildFamilyCustomDomainPointer(userID, *adminDomain)
			return c.Repo.InsertOrUpdate(ctx, userID, string(ente.CustomDomain), pointer)
		}
		return ente.NewConflictError("custom domain already exists for another user")
	}
	if !errors.Is(err, &ente.ErrNotFoundError) {
		return stacktrace.Propagate(err, "")
	}
	if err := c.Repo.InsertOrUpdate(ctx, userID, string(ente.CustomDomain), value); err != nil {
		return err
	}
	return c.updateFamilyCustomDomainsIfAdmin(ctx, userID, value)
}

func isReservedCustomDomain(value, configuredCNAME string) bool {
	for _, domain := range []string{configuredCNAME, "my.ente.com", "my.ente.io"} {
		if domain != "" && strings.EqualFold(value, domain) {
			return true
		}
	}
	return false
}

func (c *Controller) updateFamilyCustomDomainsIfAdmin(ctx context.Context, userID int64, domain string) error {
	if c.UserRepo == nil || c.FamilyRepo == nil {
		return nil
	}
	familyAdminID, err := c.UserRepo.GetFamilyAdminID(userID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if familyAdminID == nil || *familyAdminID != userID {
		return nil
	}
	members, err := c.FamilyRepo.GetMembersWithStatus(userID, repo.ActiveFamilyMemberStatus)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	for _, member := range members {
		if member.MemberUserID == userID {
			continue
		}
		memberDomain, err := c.Repo.GetDomain(ctx, member.MemberUserID)
		if err != nil {
			logrus.WithFields(logrus.Fields{
				"admin_id":  userID,
				"member_id": member.MemberUserID,
			}).WithError(err).Warn("family custom domain fetch failed")
			continue
		}
		if memberDomain == nil || *memberDomain == "" {
			continue
		}
		_, _, isPointer, parseErr := ente.ParseFamilyCustomDomainPointer(*memberDomain)
		if parseErr != nil {
			logrus.WithFields(logrus.Fields{
				"admin_id":  userID,
				"member_id": member.MemberUserID,
				"domain":    *memberDomain,
			}).WithError(parseErr).Warn("family custom domain parse failed")
			continue
		}
		if !isPointer {
			continue
		}
		pointer := ente.BuildFamilyCustomDomainPointer(member.MemberUserID, domain)
		if err := c.Repo.InsertOrUpdate(ctx, member.MemberUserID, string(ente.CustomDomain), pointer); err != nil {
			return err
		}
	}
	return nil
}

func (c *Controller) clearFamilyCustomDomainsIfAdmin(ctx context.Context, userID int64) error {
	if c.UserRepo == nil || c.FamilyRepo == nil {
		return nil
	}
	familyAdminID, err := c.UserRepo.GetFamilyAdminID(userID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if familyAdminID == nil || *familyAdminID != userID {
		return nil
	}
	members, err := c.FamilyRepo.GetMembersWithStatus(userID, repo.ActiveFamilyMemberStatus)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	for _, member := range members {
		if member.MemberUserID == userID {
			continue
		}
		memberDomain, err := c.Repo.GetDomain(ctx, member.MemberUserID)
		if err != nil {
			logrus.WithFields(logrus.Fields{
				"admin_id":  userID,
				"member_id": member.MemberUserID,
			}).WithError(err).Warn("family custom domain fetch failed")
			continue
		}
		if memberDomain == nil || *memberDomain == "" {
			continue
		}
		_, _, isPointer, parseErr := ente.ParseFamilyCustomDomainPointer(*memberDomain)
		if parseErr != nil {
			logrus.WithFields(logrus.Fields{
				"admin_id":  userID,
				"member_id": member.MemberUserID,
				"domain":    *memberDomain,
			}).WithError(parseErr).Warn("family custom domain parse failed")
			continue
		}
		if !isPointer {
			continue
		}
		if err := c.Repo.RemoveKey(ctx, member.MemberUserID, string(ente.CustomDomain)); err != nil {
			return err
		}
	}
	return nil
}

func (c *Controller) DomainOwner(ctx *gin.Context, domain string) (*int64, error) {
	ownerID, err := c.Repo.DomainOwner(ctx, domain)
	if err == nil || !errors.Is(err, &ente.ErrNotFoundError) {
		return ownerID, err
	}

	// Retry with ASCII/Unicode variants so IDN domains stored in either form still resolve.
	var candidates []string
	if asciiDomain, convErr := idna.ToASCII(domain); convErr == nil && asciiDomain != domain {
		candidates = append(candidates, asciiDomain)
	}
	if unicodeDomain, convErr := idna.ToUnicode(domain); convErr == nil && unicodeDomain != domain {
		candidates = append(candidates, unicodeDomain)
	}

	for _, candidate := range candidates {
		ownerID, candidateErr := c.Repo.DomainOwner(ctx, candidate)
		if candidateErr == nil || !errors.Is(candidateErr, &ente.ErrNotFoundError) {
			return ownerID, candidateErr
		}
	}
	return ownerID, err
}

func (c *Controller) _validateRequest(userID int64, key string, valuePtr *string, byAdmin bool) error {
	if !ente.IsValidFlagKey(key) {
		return stacktrace.Propagate(ente.NewBadRequestWithMessage(fmt.Sprintf("key %s is not allowed", key)), "invalid flag key")
	}
	if valuePtr == nil {
		return stacktrace.Propagate(ente.NewBadRequestWithMessage("value is missing"), "value is nil")
	}
	value := *valuePtr
	flag := ente.FlagKey(key)
	if err := flag.IsValidValue(value); err != nil {
		return stacktrace.Propagate(err, "")
	}
	if !flag.UserEditable() && !byAdmin {
		return stacktrace.Propagate(ente.NewBadRequestWithMessage(fmt.Sprintf("key %s is not user editable", key)), "key not user editable")
	}
	if byAdmin && !flag.IsAdminEditable() {
		return stacktrace.Propagate(ente.NewBadRequestWithMessage(fmt.Sprintf("key %s is not admin editable", key)), "key not admin editable")
	}

	if flag.NeedSubscription() {
		return c.BillingCtrl.HasActiveSelfOrFamilySubscription(userID, true)
	}
	return nil
}
