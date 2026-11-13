package middleware

import (
	"net/http"
	"sync"
	"time"

	"github.com/ente/museum/pkg/utils/s3config"
	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	log "github.com/sirupsen/logrus"
)

const (
	uploadStallDuration = 2 * time.Minute
	uploadActivityGap   = 30 * time.Second
	uploadStallRequests = 20
)

var hotStorageFailovers = promauto.NewCounterVec(prometheus.CounterOpts{
	Name: "museum_hot_storage_failovers_total",
	Help: "Hot storage switches after upload URL issuance continues without file registration traffic.",
}, []string{"from", "to"})

type uploadFailover struct {
	mu             sync.Mutex
	config         *s3config.S3Config
	startedAt      time.Time
	lastUploadAt   time.Time
	uploadRequests int
}

func UploadFailover(config *s3config.S3Config) gin.HandlerFunc {
	if !config.CanFailoverHotStorage() {
		return func(c *gin.Context) { c.Next() }
	}
	detector := &uploadFailover{config: config}
	return detector.handle
}

func (d *uploadFailover) handle(c *gin.Context) {
	if d.config.HasHotStorageFailedOver() {
		c.Next()
		return
	}
	if c.Request.Method == http.MethodPost && c.FullPath() == "/files" {
		d.mu.Lock()
		d.startedAt = time.Time{}
		d.uploadRequests = 0
		d.mu.Unlock()
	}
	c.Next()
	if c.Writer.Status() != http.StatusOK {
		return
	}
	switch c.Request.Method + " " + c.FullPath() {
	case "POST /files/upload-url", "POST /files/multipart-upload-url":
		d.recordUpload(time.Now())
	}
}

func (d *uploadFailover) recordUpload(now time.Time) {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.startedAt.IsZero() || now.Sub(d.lastUploadAt) > uploadActivityGap {
		d.startedAt = now
		d.uploadRequests = 0
	}
	d.lastUploadAt = now
	d.uploadRequests++
	if now.Sub(d.startedAt) < uploadStallDuration || d.uploadRequests < uploadStallRequests {
		return
	}
	from, to := d.config.GetHotDataCenters()
	if d.config.FailoverHotStorage() {
		hotStorageFailovers.WithLabelValues(from, to).Inc()
		log.WithFields(log.Fields{
			"from": from, "to": to, "upload_url_requests": d.uploadRequests,
		}).Error("Hot storage failed over until restart: upload URLs continued without POST /files traffic")
	}
}
