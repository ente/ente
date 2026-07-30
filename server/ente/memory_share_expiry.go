package ente

import enteTime "github.com/ente/museum/pkg/utils/time"

const MemoryShareTTL = 7 * 24 * enteTime.MicroSecondsInOneHour

func IsMemoryShareExpired(createdAt int64) bool {
	return createdAt+MemoryShareTTL <= enteTime.Microseconds()
}

func ActiveMemoryShareCreatedAfter() int64 {
	return enteTime.Microseconds() - MemoryShareTTL
}
