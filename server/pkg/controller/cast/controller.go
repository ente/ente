package cast

import (
	"context"

	"github.com/ente/museum/ente/cast"
	"github.com/ente/museum/pkg/controller/access"
	castRepo "github.com/ente/museum/pkg/repo/cast"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/network"
	"github.com/ente/museum/pkg/utils/ua"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/sirupsen/logrus"
)

type Controller struct {
	CastRepo   *castRepo.Repository
	AccessCtrl access.Controller
}

func NewController(castRepo *castRepo.Repository,
	accessCtrl access.Controller,
) *Controller {
	return &Controller{
		CastRepo:   castRepo,
		AccessCtrl: accessCtrl,
	}
}

func (c *Controller) RegisterDevice(ctx *gin.Context, request *cast.RegisterDeviceRequest) (string, error) {
	ipAddress := network.GetClientIP(ctx)
	userAgent := ctx.GetHeader("User-Agent")
	deviceName, err := ua.GetDeviceType(userAgent)
	if deviceName == "" || err != nil {
		logrus.WithFields(logrus.Fields{
			"userAgent": userAgent,
			"ip":        ipAddress,
			"err":       err,
		}).Warn("RegisterDevice: failed to get device type")
		deviceName = ipAddress
	}
	return c.CastRepo.AddCode(ctx, request.PublicKey, ipAddress, deviceName)
}

func (c *Controller) GetAllDevices(ctx *gin.Context, userID int64) ([]cast.CastInfo, error) {
	return c.CastRepo.GetAllDevices(ctx, userID)
}

func (c *Controller) DeleteDevice(ctx *gin.Context, userID int64, deviceID uuid.UUID) error {
	return c.CastRepo.RevokeForGivenUserAndDevice(ctx, userID, deviceID)
}

func (c *Controller) GetPublicKey(ctx *gin.Context, deviceCode string) (string, error) {
	pubKey, ip, err := c.CastRepo.GetPubKeyAndIp(ctx, deviceCode)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	if ip != network.GetClientIP(ctx) {
		logrus.WithFields(logrus.Fields{
			"deviceCode": deviceCode,
			"ip":         ip,
			"clientIP":   network.GetClientIP(ctx),
		}).Warn("GetPublicKey: IP mismatch")
	}
	return pubKey, nil
}

func (c *Controller) GetEncCastData(ctx context.Context, deviceCode string) (*string, error) {
	return c.CastRepo.GetEncCastData(ctx, deviceCode)
}

func (c *Controller) InsertCastData(ctx *gin.Context, request *cast.CastRequest) error {
	userID := auth.GetUserID(ctx.Request.Header)
	devices, err := c.CastRepo.GetAllDevices(ctx, userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to get existing devices")
	}
	if len(devices) >= 50 {
		return stacktrace.NewError("device limit reached")
	}
	return c.CastRepo.InsertCastData(ctx, userID, request.DeviceCode, request.CollectionID, request.CastToken, request.EncPayload)
}

func (c *Controller) RevokeAllToken(ctx *gin.Context) error {
	userID := auth.GetUserID(ctx.Request.Header)
	return c.CastRepo.RevokeTokenForUser(ctx, userID)
}

func (c *Controller) GetCollectionAndCasterIDForToken(ctx *gin.Context, token string) (*cast.AuthContext, error) {
	collectId, userId, err := c.CastRepo.GetCollectionAndCasterIDForToken(ctx, token)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	_, err = c.AccessCtrl.GetCollection(ctx, &access.GetCollectionParams{CollectionID: collectId, ActorUserID: userId})
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to verify cast access")
	}
	go c.CastRepo.UpdateLastUsedAtForToken(ctx, token)
	return &cast.AuthContext{UserID: userId, CollectionID: collectId}, nil

}
