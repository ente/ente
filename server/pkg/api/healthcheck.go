package api

import (
	"database/sql"
	"fmt"
	"net/http"
	"os"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/stacktrace"
	"github.com/sirupsen/logrus"
	"github.com/spf13/viper"

	"github.com/ente/museum/pkg/utils/config"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/gin-gonic/gin"
)

type HealthCheckHandler struct {
	DB *sql.DB
}

func (h *HealthCheckHandler) Ping(c *gin.Context) {
	res := 0
	err := h.DB.QueryRowContext(c, `SELECT 1`).Scan(&res)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	result := make(map[string]string)
	result["message"] = "pong"
	result["id"] = os.Getenv("GIT_COMMIT")
	if c.Query("host") != "" {
		result["host"], _ = os.Hostname()
	}
	c.JSON(http.StatusOK, result)
}

func (h *HealthCheckHandler) PingDBStats(c *gin.Context) {
	host, _ := os.Hostname()
	stats := h.DB.Stats()
	logrus.WithFields(logrus.Fields{
		"MaxOpenConnections": stats.MaxOpenConnections,
		"Idle":               stats.Idle,
		"InUse":              stats.InUse,
		"OpenConnections":    stats.OpenConnections,
		"WaitCount":          stats.WaitCount,
		"WaitDuration":       stats.WaitDuration.String(),
		"MaxIdleClosed":      stats.MaxIdleClosed,
		"MaxIdleTimeClosed":  stats.MaxIdleTimeClosed,
		"MaxLifetimeClosed":  stats.MaxLifetimeClosed,
	}).Info("DB STATS")

	logrus.Info("DB Ping Start")
	err := h.DB.Ping()
	if err != nil {
		logrus.WithError(err).Error("DB Ping failed")
		handler.Error(c, stacktrace.Propagate(ente.NewInternalError(fmt.Sprintf("DB ping failed on %s", host)), ""))
		return
	}
	c.Status(http.StatusOK)
}

func (h *HealthCheckHandler) PerformHealthCheck() {
	logrus.Info("Performing HC")
	healthCheckURL := viper.GetString("internal.health-check-url")
	if healthCheckURL == "" {
		if !config.IsLocalEnvironment() {
			logrus.Error("Could not obtain health check URL in non-local environment")
		}
		return
	}
	var client = &http.Client{
		Timeout: 10 * time.Second,
	}
	_, err := client.Head(healthCheckURL)
	if err != nil {
		logrus.Error("Error performing health check", err)
	}
}
