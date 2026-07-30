package api

import (
	"strconv"

	"github.com/ente/museum/ente"
)

const (
	diffDefaultLimit = 1000
	diffMaxLimit     = 2000
)

func parseDiffSinceTime(raw string) (int64, error) {
	if raw == "" {
		return 0, nil
	}
	return strconv.ParseInt(raw, 10, 64)
}

func parseDiffLimit(raw string) (int, error) {
	if raw == "" {
		return diffDefaultLimit, nil
	}
	limit, err := strconv.Atoi(raw)
	if err != nil {
		return 0, err
	}
	if limit <= 0 {
		return 0, ente.ErrBadRequest
	}
	if limit > diffMaxLimit {
		limit = diffMaxLimit
	}
	return limit, nil
}

func parseOptionalInt64(raw string) (*int64, error) {
	if raw == "" {
		return nil, nil
	}
	value, err := strconv.ParseInt(raw, 10, 64)
	if err != nil {
		return nil, err
	}
	return &value, nil
}
