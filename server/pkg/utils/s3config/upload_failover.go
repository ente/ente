package s3config

import (
	"sync"
	"time"

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
	Help: "Hot storage switches after upload activity continues without registration progress in the primary bucket.",
}, []string{"from", "to"})

type MultipartInitiationError struct {
	Err error
}

func (e *MultipartInitiationError) Error() string { return e.Err.Error() }
func (e *MultipartInitiationError) Unwrap() error { return e.Err }

type uploadFailover struct {
	mu             sync.Mutex
	startedAt      time.Time
	lastUploadAt   time.Time
	uploadRequests int
}

func (config *S3Config) RecordUploadProgress(bucket string) {
	if bucket != config.hotDC || config.HasHotStorageFailedOver() {
		return
	}
	d := &config.uploadFailover
	d.mu.Lock()
	defer d.mu.Unlock()
	d.startedAt = time.Time{}
	d.uploadRequests = 0
}

func (config *S3Config) RecordUploadActivity(now time.Time) {
	d := &config.uploadFailover
	d.mu.Lock()
	defer d.mu.Unlock()
	if config.HasHotStorageFailedOver() {
		return
	}
	if d.startedAt.IsZero() || now.Sub(d.lastUploadAt) > uploadActivityGap {
		d.startedAt = now
		d.uploadRequests = 0
	}
	d.lastUploadAt = now
	d.uploadRequests++
	if now.Sub(d.startedAt) < uploadStallDuration || d.uploadRequests < uploadStallRequests {
		return
	}
	from, to := config.GetHotDataCenters()
	if config.FailoverHotStorage() {
		hotStorageFailovers.WithLabelValues(from, to).Inc()
		log.WithFields(log.Fields{
			"from": from, "to": to, "upload_requests": d.uploadRequests,
		}).Error("Hot storage failed over until restart: upload activity continued without registration progress in the primary bucket")
	}
}
