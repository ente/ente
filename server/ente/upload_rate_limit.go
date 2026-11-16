package ente

import "time"

type UploadRateLimitError struct {
	Reason     *ApiError
	RetryAfter time.Duration
}

func (e *UploadRateLimitError) Error() string {
	return e.Reason.Error()
}

func (e *UploadRateLimitError) Unwrap() error {
	return e.Reason
}
