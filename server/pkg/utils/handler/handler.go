package handler

import (
	"database/sql"
	"errors"
	"io"
	"net/http"
	"syscall"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/stacktrace"
	"github.com/gin-contrib/requestid"
	"github.com/gin-gonic/gin"
	"github.com/go-playground/validator/v10"
	log "github.com/sirupsen/logrus"
)

var errBindJSON = errors.New("bind json")

type bindJSONError struct {
	err error
}

func (e bindJSONError) Error() string {
	return e.err.Error()
}

func (e bindJSONError) Unwrap() error {
	return e.err
}

func (e bindJSONError) Is(target error) bool {
	return target == errBindJSON
}

func BindJSON(c *gin.Context, obj any) error {
	if err := c.ShouldBindJSON(obj); err != nil {
		return bindJSONError{err: err}
	}
	return nil
}

// Error parses the error, translates it into an HTTP response and aborts
// the request
func Error(c *gin.Context, err error) {
	unWrappedErr := errors.Unwrap(err)
	if unWrappedErr == nil {
		unWrappedErr = err
	}
	enteApiErr, isEnteApiErr := unWrappedErr.(*ente.ApiError)

	if level := requestFailureLogLevel(err, enteApiErr); level != nil {
		contextLogger := log.WithError(err).
			WithFields(log.Fields{
				"req_id":  requestid.Get(c),
				"user_id": auth.GetUserID(c.Request.Header),
			})
		contextLogger.Log(*level, "Request failed")
	}
	if isEnteApiErr {
		c.AbortWithStatusJSON(enteApiErr.HttpStatusCode, enteApiErr)
	} else if httpStatus := httpStatusCode(err); httpStatus != 0 {
		c.AbortWithStatusJSON(httpStatus, gin.H{})
	} else {
		if _, ok := stacktrace.RootCause(err).(validator.ValidationErrors); ok {
			c.AbortWithStatusJSON(http.StatusBadRequest, gin.H{})
		} else if isRequestIOError(err) {
			c.AbortWithStatusJSON(http.StatusBadRequest, gin.H{})
		} else {
			c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{})
		}
	}
}

func requestFailureLogLevel(err error, apiErr *ente.ApiError) *log.Level {
	if errors.Is(err, ente.ErrStorageLimitExceeded) ||
		errors.Is(err, ente.ErrNoActiveSubscription) ||
		(apiErr != nil && apiErr.Code == ente.NotFoundError) {
		return nil
	}
	if errors.Is(err, ente.ErrInvalidPassword) ||
		errors.Is(err, ente.ErrIncorrectOTT) ||
		errors.Is(err, ente.ErrIncorrectTOTP) ||
		errors.Is(err, ente.ErrAuthenticationRequired) ||
		errors.Is(err, ente.ErrUserDeleted) ||
		errors.Is(err, sql.ErrNoRows) ||
		errors.Is(err, errBindJSON) ||
		isRequestIOError(err) ||
		(apiErr != nil && apiErr.HttpStatusCode >= 400 && apiErr.HttpStatusCode < 500) {
		return logLevel(log.WarnLevel)
	}
	return logLevel(log.ErrorLevel)
}

func logLevel(level log.Level) *log.Level {
	return &level
}

func isRequestIOError(err error) bool {
	// Tip: To trigger the "unexpected EOF" error, connect with:
	//
	//    echo "GET /ping HTTP/1.0\r\nContent-Length: 300\r\n\r\n" | nc localhost 8080
	return errors.Is(err, io.ErrUnexpectedEOF) ||
		errors.Is(err, syscall.EPIPE) ||
		errors.Is(err, syscall.ECONNRESET)
}

// If `err` directly maps to an HTTP status code, return the HTTP status code.
// Otherwise return 0.
func httpStatusCode(err error) int {
	switch {
	case errors.Is(err, ente.ErrNotFound) ||
		errors.Is(err, sql.ErrNoRows):
		return http.StatusNotFound
	case errors.Is(err, ente.ErrBadRequest) ||
		errors.Is(err, ente.ErrCannotDowngrade) ||
		errors.Is(err, ente.ErrCannotSwitchPaymentProvider) ||
		errors.Is(err, errBindJSON):
		return http.StatusBadRequest
	case errors.Is(err, ente.ErrTooManyBadRequest):
		return http.StatusTooManyRequests
	case errors.Is(err, ente.ErrPermissionDenied):
		return http.StatusForbidden
	case errors.Is(err, ente.ErrIncorrectOTT) ||
		errors.Is(err, ente.ErrIncorrectTOTP) ||
		errors.Is(err, ente.ErrInvalidPassword) ||
		errors.Is(err, ente.ErrAuthenticationRequired):
		return http.StatusUnauthorized
	case errors.Is(err, ente.ErrExpiredOTT) ||
		errors.Is(err, ente.ErrUserDeleted):
		return http.StatusGone
	case errors.Is(err, ente.ErrNoActiveSubscription) ||
		errors.Is(err, ente.ErrSharingDisabledForFreeAccounts):
		return http.StatusPaymentRequired
	case errors.Is(err, ente.ErrStorageLimitExceeded):
		return http.StatusUpgradeRequired
	case errors.Is(err, ente.ErrFileTooLarge):
		return http.StatusRequestEntityTooLarge
	case errors.Is(err, ente.ErrVersionMismatch) ||
		errors.Is(err, ente.ErrCanNotInviteUserWithPaidPlan):
		return http.StatusConflict
	case errors.Is(err, ente.ErrBatchSizeTooLarge):
		return http.StatusRequestEntityTooLarge
	case errors.Is(err, ente.ErrCanNotInviteUserAlreadyInFamily):
		return http.StatusNotAcceptable
	case errors.Is(err, ente.ErrFamilySizeLimitReached):
		return http.StatusPreconditionFailed
	case errors.Is(err, ente.ErrNotImplemented):
		return http.StatusNotImplemented
	default:
		return 0
	}
}
