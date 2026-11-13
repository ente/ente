package middleware

import (
	"errors"
	"net/http"
	"time"

	"github.com/ente/museum/pkg/utils/s3config"
	"github.com/gin-gonic/gin"
)

func UploadFailover(config *s3config.S3Config) gin.HandlerFunc {
	if !config.CanFailoverHotStorage() {
		return func(c *gin.Context) { c.Next() }
	}
	return func(c *gin.Context) {
		c.Next()
		if config.HasHotStorageFailedOver() || c.Request.Context().Err() != nil {
			return
		}
		switch c.Request.Method + " " + c.FullPath() {
		case "POST /files/upload-url", "POST /files/multipart-upload-url":
			if c.Writer.Status() == http.StatusOK {
				config.RecordUploadActivity(time.Now())
				return
			}
			for _, err := range c.Errors {
				var initiationError *s3config.MultipartInitiationError
				if errors.As(err, &initiationError) {
					config.RecordUploadActivity(time.Now())
					return
				}
			}
		}
	}
}
