package network

import (
	"github.com/gin-gonic/gin"
	"github.com/ua-parser/uap-go/uaparser"
)

func GetClientIP(c *gin.Context) string {
	return c.ClientIP()
}

func IsCFWorkerIP(ip string) bool {
	return ip == "2a06:98c0:3600::103"
}

func GetClientCountry(c *gin.Context) string {
	return c.GetHeader("CF-IPCountry")
}

var parser = uaparser.NewFromSaved()

func GetPrettyUA(ua string) string {
	parsedUA := parser.Parse(ua)
	if parsedUA.UserAgent.Family == "Android" {
		return parsedUA.Device.Model + ", " + parsedUA.Os.ToString()
	} else if parsedUA.UserAgent.Family == "CFNetwork" {
		return parsedUA.Device.ToString()
	} else if parsedUA.UserAgent.Family == "Electron" {
		return "Desktop App" + ", " + parsedUA.Os.ToString()
	}
	return parsedUA.UserAgent.Family + ", " + parsedUA.Os.ToString()
}

func GetClientInfo(gin *gin.Context) string {
	client := gin.GetHeader("X-Client-Package")
	version := gin.GetHeader("X-Client-Version")
	if version == "" {
		return client
	}
	return client + "/" + version
}
