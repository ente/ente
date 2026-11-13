package dbmetrics

import (
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

type Operation string

const (
	CollectionAddFiles Operation = "collection_add_files"
	FileCreate         Operation = "file_create"
	UserEntityUpdate   Operation = "user_entity_update"
)

var phaseDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
	Name:    "museum_db_phase_duration_seconds",
	Help:    "Elapsed time of selected write-operation phases. Phases ending in _with_checkout include connection acquisition.",
	Buckets: []float64{0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 20, 30, 60},
}, []string{"operation", "phase", "result"})

func Start(operation Operation, phase string) func(error) {
	startedAt := time.Now()
	return func(err error) {
		elapsed := time.Since(startedAt).Seconds()
		result := "success"
		if err != nil {
			result = "error"
		}
		phaseDuration.WithLabelValues(string(operation), phase, result).Observe(elapsed)
	}
}
