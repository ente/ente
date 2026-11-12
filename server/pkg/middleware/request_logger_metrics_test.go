package middleware

import (
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/sirupsen/logrus"
	"github.com/stretchr/testify/require"
)

func TestRequestMetricsBoundLabels(t *testing.T) {
	gin.SetMode(gin.TestMode)
	latency.Reset()
	t.Cleanup(latency.Reset)
	requests.Reset()
	t.Cleanup(requests.Reset)
	logger := logrus.StandardLogger()
	output := logger.Out
	logger.SetOutput(io.Discard)
	t.Cleanup(func() { logger.SetOutput(output) })

	router := gin.New()
	urlSanitizer := func(*gin.Context) string { return "/metrics-label-test" }
	router.Use(RequestMetrics(urlSanitizer), Logger(urlSanitizer))
	router.GET("/metrics-label-test", func(c *gin.Context) { c.Status(http.StatusNoContent) })

	for _, request := range []struct{ method, host string }{
		{http.MethodGet, "first.example"},
		{http.MethodGet, "second.example"},
		{"CUSTOM-ONE", "first.example"},
		{"CUSTOM-TWO", "second.example"},
	} {
		recorder := httptest.NewRecorder()
		r := httptest.NewRequest(request.method, "/metrics-label-test", nil)
		r.Host = request.host
		router.ServeHTTP(recorder, r)
	}

	registry := prometheus.NewRegistry()
	require.NoError(t, registry.Register(latency))
	require.NoError(t, registry.Register(requests))
	families, err := registry.Gather()
	require.NoError(t, err)
	counts := make(map[string]map[string]uint64)
	for _, family := range families {
		name := family.GetName()
		if name != "museum_latency" && name != "museum_requests_total" {
			continue
		}
		counts[name] = make(map[string]uint64)
		for _, metric := range family.GetMetric() {
			labels := make(map[string]string)
			for _, label := range metric.GetLabel() {
				labels[label.GetName()] = label.GetValue()
			}
			if labels["url"] == "/metrics-label-test" {
				require.NotContains(t, labels, "host")
				if name == "museum_latency" {
					counts[name][labels["method"]] += metric.GetHistogram().GetSampleCount()
				} else {
					counts[name][labels["method"]] += uint64(metric.GetCounter().GetValue())
				}
			}
		}
	}
	want := map[string]uint64{"GET": 2, "OTHER": 2}
	require.Equal(t, map[string]map[string]uint64{"museum_latency": want, "museum_requests_total": want}, counts)
}
