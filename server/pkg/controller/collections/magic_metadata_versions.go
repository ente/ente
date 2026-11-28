package collections

import (
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

var magicMetadataVersions = promauto.NewCounterVec(prometheus.CounterOpts{
	Name: "museum_collection_magic_metadata_versions_total",
	Help: "Collection magic metadata writes by route, client and how the sent version compares with the stored one.",
}, []string{"route", "client", "outcome"})

func countMagicMetadataVersion(ctx *gin.Context, route string, sentVersion int, expectedVersion int64) {
	magicMetadataVersions.WithLabelValues(
		route,
		metadataClient(ctx.GetHeader("X-Client-Package")),
		versionOutcome(int64(sentVersion), expectedVersion),
	).Inc()
}

func metadataClient(clientPackage string) string {
	switch {
	case clientPackage == "io.ente.photos.web":
		return "web"
	case strings.HasPrefix(clientPackage, "io.ente.photos.desktop"):
		return "desktop"
	case strings.HasPrefix(clientPackage, "io.ente.photos"), strings.HasPrefix(clientPackage, "io.ente.frame"):
		return "mobile"
	default:
		return "other"
	}
}

func versionOutcome(sent, expected int64) string {
	switch {
	case sent == expected:
		return "match"
	case sent == expected+1:
		return "ahead_one"
	case sent < expected:
		return "stale"
	default:
		return "ahead"
	}
}
