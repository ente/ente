package middleware

import (
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

var requests = promauto.NewCounterVec(prometheus.CounterOpts{
	Subsystem: "museum",
	Name:      "requests_total",
	Help:      "How many HTTP requests processed, partitioned by status code and HTTP method.",
}, []string{"code", "method", "handler", "url"})

var requestDuration = promauto.NewSummary(prometheus.SummaryOpts{
	Subsystem: "museum",
	Name:      "request_duration_seconds",
	Help:      "The HTTP request latencies in seconds.",
})

var requestSize = promauto.NewSummary(prometheus.SummaryOpts{
	Subsystem: "museum",
	Name:      "request_size_bytes",
	Help:      "The HTTP request sizes in bytes.",
})

var responseSize = promauto.NewSummary(prometheus.SummaryOpts{
	Subsystem: "museum",
	Name:      "response_size_bytes",
	Help:      "The HTTP response sizes in bytes.",
})

func RequestMetrics(urlSanitizer func(*gin.Context) string) gin.HandlerFunc {
	return func(c *gin.Context) {
		if c.Request.URL.String() == "/metrics" {
			c.Next()
			return
		}

		start := time.Now()
		size := approximateRequestSize(c.Request)
		c.Next()

		requestDuration.Observe(time.Since(start).Seconds())
		requests.WithLabelValues(strconv.Itoa(c.Writer.Status()), metricMethod(c.Request.Method), c.HandlerName(), urlSanitizer(c)).Inc()
		requestSize.Observe(float64(size))
		responseSize.Observe(float64(c.Writer.Size()))
	}
}

func approximateRequestSize(r *http.Request) int {
	size := len(r.URL.String()) + len(r.Method) + len(r.Proto) + len(r.Host)
	for name, values := range r.Header {
		size += len(name)
		for _, value := range values {
			size += len(value)
		}
	}
	if r.ContentLength != -1 {
		size += int(r.ContentLength)
	}
	return size
}
