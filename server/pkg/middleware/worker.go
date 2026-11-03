package middleware

import (
	"crypto/subtle"

	"github.com/gin-gonic/gin"
	"github.com/spf13/viper"
)

func isTrustedWorker(c *gin.Context) bool {
	secret := viper.GetString("workers.shared-secret")
	return secret != "" && subtle.ConstantTimeCompare([]byte(c.GetHeader("X-Ente-Worker-Secret")), []byte(secret)) == 1
}
