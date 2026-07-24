package middleware

import (
	"bytes"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/ente/museum/pkg/utils/network"

	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/stacktrace"
	"github.com/gin-contrib/requestid"

	timeUtil "github.com/ente/museum/pkg/utils/time"

	"github.com/ente/museum/pkg/utils/handler"
	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/sirupsen/logrus"
)

var latency = promauto.NewHistogramVec(prometheus.HistogramOpts{
	Name:    "museum_latency",
	Help:    "The amount of time the server is taking to respond to requests",
	Buckets: []float64{10, 50, 100, 200, 500, 1000, 10000, 30000, 60000, 120000, 600000},
}, []string{"code", "method", "host", "url"})

// shouldSkipBodyLog returns true if the body should not be logged.
// This is useful for endpoints that receive large or sensitive payloads.
func shouldSkipBodyLog(method string, path string) bool {
	isReadOnly := method == http.MethodGet || method == http.MethodHead || method == http.MethodOptions
	if method == "PUT" && path == "/embeddings" {
		return true
	}
	if path == "/user-entity/entity" && (method == "POST" || method == "PUT") {
		return true
	}
	if path == "/contacts" && method == http.MethodPost {
		return true
	}
	if strings.HasPrefix(path, "/contacts/") && method == http.MethodPut {
		return true
	}
	if path == "/files/data" && method == "PUT" {
		return true
	}
	if path == "/admin/user/terminate-session" {
		return true
	}
	if method == http.MethodPost && (path == "/events" || path == "/events/user") {
		return true
	}
	if method == http.MethodPost && (path == "/paste/create" || path == "/paste/guard" || path == "/paste/consume") {
		return true
	}
	if method == http.MethodPost && (path == "/users/recover-account" || path == "/users/recover-account/validate") {
		return true
	}
	if !isReadOnly && (strings.HasPrefix(path, "/space") || strings.HasPrefix(path, "/account/space")) {
		return true
	}
	if !isReadOnly && (path == "/user-entity/key" || path == "/user-entity/key/ensure") {
		return true
	}
	return false
}

// Logger logs the details regarding an incoming request
func Logger(urlSanitizer func(_ *gin.Context) string) gin.HandlerFunc {
	return func(c *gin.Context) {
		startTime := time.Now()
		reqID := requestid.Get(c)
		buf, err := io.ReadAll(c.Request.Body)
		if err != nil {
			handler.Error(c, err)
		}
		rdr1 := io.NopCloser(bytes.NewBuffer(buf))
		// Creating a new Buffer, because rdr1 will be read
		rdr2 := io.NopCloser(bytes.NewBuffer(buf))

		userAgent := c.GetHeader("User-Agent")
		clientVersion := c.GetHeader("X-Client-Version")
		clientPkg := c.GetHeader("X-Client-Package")
		clientIP := network.GetClientIP(c)
		reqMethod := c.Request.Method
		queryValues, _ := url.ParseQuery(c.Request.URL.RawQuery)
		if queryValues.Has("token") {
			queryValues.Set("token", "redacted-value")
		}
		queryParamsForLog := queryValues.Encode()
		reqContextLogger := logrus.WithFields(logrus.Fields{
			"client_ip":      clientIP,
			"client_pkg":     clientPkg,
			"client_version": clientVersion,
			"query":          queryParamsForLog,
			"req_id":         reqID,
			"req_method":     reqMethod,
			"req_uri":        c.Request.URL.Path,
			"ua":             userAgent,
		})
		skipRequestLogUnlessError := shouldSkipBodyLog(reqMethod, c.Request.URL.Path)
		if skipRequestLogUnlessError {
			reqContextLogger = reqContextLogger.WithField("req_body", "redacted")
		} else {
			body, err := readBody(rdr1)
			if err != nil {
				logrus.Error("Error reading body", err)
			} else {
				reqContextLogger = reqContextLogger.WithField("req_body", body)
			}
		}
		reqContextLogger.Info("incoming")
		c.Request.Body = rdr2
		// Processing request
		c.Next()
		statusCode := c.Writer.Status()
		latencyTime := time.Since(startTime)
		reqURI := urlSanitizer(c)
		if reqMethod != http.MethodOptions {
			latency.WithLabelValues(strconv.Itoa(statusCode), reqMethod,
				c.Request.Host, reqURI).
				Observe(float64(latencyTime.Milliseconds()))
		}
		if statusCode >= 400 && !skipRequestLogUnlessError {
			body, err := readBody(rdr1)
			if err != nil {
				logrus.Error("Error reading body", err)
			} else {
				reqContextLogger = reqContextLogger.WithField("req_body", body)
			}
		}
		reqContextLogger.WithFields(logrus.Fields{
			"latency_time": latencyTime,
			"h_latency":    timeUtil.HumanFriendlyDuration(latencyTime),
			"status_code":  statusCode,
			"user_id":      auth.GetUserID(c.Request.Header),
		}).Info("outgoing")
	}
}

func readBody(reader io.Reader) (string, error) {
	buf := new(bytes.Buffer)
	_, err := buf.ReadFrom(reader)
	return buf.String(), stacktrace.Propagate(err, "")
}
