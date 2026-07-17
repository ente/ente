package middleware

import (
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/http/httputil"
	"os"
	"runtime/debug"
	"strings"
	"syscall"

	"github.com/gin-contrib/requestid"
	"github.com/gin-gonic/gin"
	log "github.com/sirupsen/logrus"
)

// PanicRecover is similar to Gin's CustomRecoveryWithWriter but with custom logger.
// There's no easy way to plugin application logger instance & log custom attributes (like requestID)
func PanicRecover() gin.HandlerFunc {
	return func(c *gin.Context) {
		defer func() {
			if err := recover(); err != nil {
				// Check for a broken connection, as it is not really a
				// condition that warrants a panic stack trace.
				//
				// Newer versions of gin might fix this (the PR is not yet
				// merged as on writing):
				// https://github.com/gin-gonic/gin/pull/2150
				var brokenPipe bool

				// Legacy check, not sure if it ever worked. Retaining this, can
				// remove both when the gin PR is merged.
				if ne, ok := err.(*net.OpError); ok {
					if se, ok := ne.Err.(*os.SyscallError); ok {
						if strings.Contains(strings.ToLower(se.Error()), "broken pipe") || strings.Contains(strings.ToLower(se.Error()), "connection reset by peer") {
							brokenPipe = true
						}
					}
				}

				// Newer check. Also untested.
				if !brokenPipe {
					if re, ok := err.(error); ok {
						if errors.Is(re, syscall.EPIPE) {
							brokenPipe = true
						}
					}
				}

				httpRequest, _ := httputil.DumpRequest(c.Request, false)
				requestData := strings.Split(string(httpRequest), "\r\n")
				for idx, header := range requestData {
					current := strings.Split(header, ":")
					if current[0] == "Authorization" || current[0] == "X-Auth-Token" || current[0] == "X-Space-Session-Token" {
						requestData[idx] = current[0] + ": *"
					}
				}
				reqDataWithoutAuthHeaders := strings.Join(requestData, "\r\n")
				var logWithAttributes = log.WithFields(log.Fields{
					"request_data": reqDataWithoutAuthHeaders,
					"req_id":       requestid.Get(c),
					"req_uri":      c.Request.URL.Path,
					"panic":        err,
					"broken_pipe":  brokenPipe,
					"stack":        string(debug.Stack()),
				})
				if brokenPipe {
					log.Warn("Panic Recovery: Broken pipe")
					// If the connection is dead, we can't write a status to it.
					c.Error(err.(error)) // nolint: errcheck
					c.Abort()
					return
				}
				if fmt.Sprintf("%v", err) == "client disconnected" {
					// https://github.com/gin-gonic/gin/issues/2279#issuecomment-768349478
					logWithAttributes.Warn("Client request cancelled")
					c.Request.Context().Done()
				} else {
					logWithAttributes.Error("Recovery from Panic")
					c.AbortWithStatus(http.StatusInternalServerError)
				}
			}
		}()
		c.Next()
	}
}
