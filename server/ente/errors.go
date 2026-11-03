package ente

import (
	"errors"
	"fmt"
	"net/http"
)

var ErrPermissionDenied = errors.New("insufficient permissions to perform this action")

var ErrIncorrectOTT = errors.New("incorrect OTT")

var ErrExpiredOTT = errors.New("no active OTT")

var ErrIncorrectTOTP = errors.New("incorrect TOTP")

var ErrNotFound = errors.New("not found")

var ErrCollectionDeleted = &ApiError{
	Code:           "COLLECTION_DELETED",
	Message:        "",
	HttpStatusCode: http.StatusNotFound,
}

var ErrFileLimitReached = ApiError{
	Code:           FileLimitReached,
	Message:        "Maximum file limit reached",
	HttpStatusCode: http.StatusForbidden,
}

var ErrBadRequest = errors.New("bad request")

var ErrTooManyBadRequest = errors.New("too many bad request")

var ErrUnexpectedState = errors.New("unexpected state")

var ErrCannotDowngrade = errors.New("usage is greater than selected plan, cannot downgrade")

var ErrCannotSwitchPaymentProvider = errors.New("cannot switch payment provider")

var ErrNoActiveSubscription = errors.New("no Active Subscription")

var ErrStorageLimitExceeded = errors.New("storage Limit exceeded")

var ErrFileTooLarge = errors.New("file too large")

var ErrSharingDisabledForFreeAccounts = errors.New("sharing Feature is disabled for free accounts")

var ErrDuplicateFileObjectFound = errors.New("file object already exists")

var ErrFavoriteCollectionAlreadyExist = errors.New("favorites collection already exists")

var ErrUncategorizeCollectionAlreadyExists = errors.New("uncategorized collection already exists")

var ErrDuplicateThumbnailObjectFound = errors.New("thumbnail object already exists")

var ErrFileUploadConflict = &ApiError{
	Code:           "FILE_UPLOAD_CONFLICT",
	Message:        "File upload conflicts with an existing file",
	HttpStatusCode: http.StatusBadRequest,
}

var ErrVersionMismatch = errors.New("client version is out of sync")

var ErrCanNotInviteUserWithPaidPlan = errors.New("can not invite user with active paid plan")

var ErrBatchSizeTooLarge = errors.New("batch size greater than API limit")

var ErrAuthenticationRequired = errors.New("authentication required")

var ErrInvalidPassword = errors.New("invalid password")

var ErrCanNotInviteUserAlreadyInFamily = errors.New("can not invite user who is already part of a family")

var ErrFamilySizeLimitReached = errors.New("can't invite new member, family already at max allowed size")

var ErrUserDeleted = errors.New("user account has been deleted")

var ErrLockUnavailable = errors.New("could not acquire lock")

var ErrActiveLinkAlreadyExists = errors.New("link already exists for this entity")

var ErrAccessTokenInUse = errors.New("access token already in use")

// ErrNotImplemented indicates that the action that we tried to perform is not
// available at this museum instance. e.g. this could be something that is not
// enabled on this particular instance of museum.
//
// Semantically, it could've been better called as NotAvailable, but
// NotAvailable is meant to be used for temporary errors, whilst we wish to
// indicate that this instance will not serve this request at all.
var ErrNotImplemented = errors.New("not implemented")

var ErrInvalidApp = errors.New("invalid app")

var ErrSubscriptionAlreadyClaimed = ApiError{
	Code:           SubscriptionAlreadyClaimed,
	HttpStatusCode: http.StatusConflict,
	Message:        "Subscription is already associted with different account",
}

var ErrUserAlreadyRegistered = &ApiError{
	Code:           "USER_ALREADY_REGISTERED",
	HttpStatusCode: http.StatusConflict,
	Message:        "User is already registered",
}

var ErrUserNotRegistered = &ApiError{
	Code:           "USER_NOT_REGISTERED",
	HttpStatusCode: http.StatusNotFound,
	Message:        "User is not registered",
}

var ErrUserSignupIncomplete = &ApiError{
	Code:           UserSignupIncomplete,
	HttpStatusCode: http.StatusNotFound,
	Message:        "User signup is incomplete",
}

var ErrCollectionNotEmpty = ApiError{
	Code:           CollectionNotEmpty,
	HttpStatusCode: http.StatusConflict,
	Message:        "The collection is not empty",
}

var ErrFileNotFoundInAlbum = ApiError{
	Code:           FileNotFoundInAlbum,
	HttpStatusCode: http.StatusNotFound,
	Message:        "File is either deleted or moved to different collection",
}

var ErrSessionAlreadyClaimed = ApiError{
	Code:           "SESSION_ALREADY_CLAIMED",
	Message:        "Session is already claimed",
	HttpStatusCode: http.StatusConflict,
}

var ErrPublicCollectDisabled = ApiError{
	Code:           PublicCollectDisabled,
	Message:        "User has not enabled public collect for this url",
	HttpStatusCode: http.StatusMethodNotAllowed,
}

var ErrPublicCommentDisabled = ApiError{
	Code:           PublicCommentDisabled,
	Message:        "User has not enabled public comments for this url",
	HttpStatusCode: http.StatusMethodNotAllowed,
}

var ErrPublicCommentTooLong = ApiError{
	Code:           PublicCommentTooLong,
	Message:        "Comments are limited to 280 characters",
	HttpStatusCode: http.StatusBadRequest,
}

var ErrAnonNameTooLong = ApiError{
	Code:           AnonNameTooLong,
	Message:        "Anonymous names are limited to 50 characters",
	HttpStatusCode: http.StatusBadRequest,
}

var ErrNotFoundError = ApiError{
	Code:           NotFoundError,
	Message:        "",
	HttpStatusCode: http.StatusNotFound,
}

var ErrObjSizeFetchFailed = &ApiError{
	Code:           "OBJECT_SIZE_FETCH_FAILED",
	Message:        "",
	HttpStatusCode: http.StatusServiceUnavailable,
}

var ErrUserNotFound = &ApiError{
	Code:           "USER_NOT_FOUND",
	Message:        "User is either deleted or not found",
	HttpStatusCode: http.StatusNotFound,
}

var ErrRecipientIdentityMismatch = &ApiError{
	Code:           "RECIPIENT_IDENTITY_MISMATCH",
	Message:        "Recipient identity does not match",
	HttpStatusCode: http.StatusConflict,
}

var ErrAutomaticShareRecipientNotEligible = &ApiError{
	Code:           "AUTOMATIC_SHARE_RECIPIENT_NOT_ELIGIBLE",
	Message:        "Automatic share recipient is not eligible",
	HttpStatusCode: http.StatusForbidden,
}

var ErrMaxPasskeysReached = ApiError{
	Code:           MaxPasskeysReached,
	Message:        "Max passkeys limit reached",
	HttpStatusCode: http.StatusConflict,
}
var ErrPassProtectedResource = ApiError{
	Code:           "PASS_PROTECTED_RESOURCE",
	Message:        "This resource is password protected",
	HttpStatusCode: http.StatusForbidden,
}

var ErrCastPermissionDenied = ApiError{
	Code:           "CAST_PERMISSION_DENIED",
	Message:        "Permission denied",
	HttpStatusCode: http.StatusForbidden,
}

var ErrCastIPMismatch = ApiError{
	Code:           "CAST_IP_MISMATCH",
	Message:        "IP mismatch",
	HttpStatusCode: http.StatusForbidden,
}

var ErrLinkEditNotAllowed = ApiError{
	Code:           LinkEditNotAllowed,
	Message:        "Editing link settings is not allowed for free accounts",
	HttpStatusCode: http.StatusForbidden,
}

var ErrLinkDeviceLimitExceeded = ApiError{
	Code:           LinkDeviceLimitExceeded,
	Message:        "Public link device limit reached",
	HttpStatusCode: http.StatusForbidden,
}

var ErrActiveRecoverySession = ApiError{
	Code:           ActiveRecoverySession,
	Message:        "cannot update recovery notice while there is an active recovery session",
	HttpStatusCode: http.StatusBadRequest,
}

var ErrFileInTrash = ApiError{
	Code:           FileInTrash,
	Message:        "One or more files are in trash or have been deleted, please restore them first",
	HttpStatusCode: http.StatusConflict,
}

var ErrLockerRegistrationDisabled = &ApiError{
	Code:           LockerRegistrationDisabled,
	Message:        "Locker is restricted to paid users currently",
	HttpStatusCode: http.StatusForbidden,
}

var ErrLockerRollOutLimit = &ApiError{
	Code:           LockerRolloutLimit,
	Message:        "Sorry, locker registration is paused temporarily, please try again later",
	HttpStatusCode: http.StatusForbidden,
}

type ErrorCode string

const (
	BadRequest    ErrorCode = "BAD_REQUEST"
	CONFLICT      ErrorCode = "CONFLICT"
	AlreadyExists ErrorCode = "ALREADY_EXISTS"

	InternalError ErrorCode = "INTERNAL_ERROR"

	NotFoundError ErrorCode = "NOT_FOUND"

	FamilySizeLimitExceeded ErrorCode = "FAMILY_SIZE_LIMIT_EXCEEDED"

	UserSignupIncomplete ErrorCode = "USER_SIGNUP_INCOMPLETE"

	SubscriptionAlreadyClaimed ErrorCode = "SUBSCRIPTION_ALREADY_CLAIMED"

	FileNotFoundInAlbum ErrorCode = "FILE_NOT_FOUND_IN_ALBUM"

	AuthKeyNotCreated ErrorCode = "AUTH_KEY_NOT_CREATED"

	PublicCollectDisabled ErrorCode = "PUBLIC_COLLECT_DISABLED"

	PublicCommentDisabled ErrorCode = "PUBLIC_COMMENT_DISABLED"

	PublicCommentTooLong ErrorCode = "PUBLIC_COMMENT_TOO_LONG"

	AnonNameTooLong ErrorCode = "ANON_NAME_TOO_LONG"

	CollectionNotEmpty ErrorCode = "COLLECTION_NOT_EMPTY"

	MaxPasskeysReached ErrorCode = "MAX_PASSKEYS_REACHED"

	LockerRegistrationDisabled ErrorCode = "LOCKER_REGISTRATION_DISABLED"

	LockerRolloutLimit ErrorCode = "LOCKER_ROLLOUT_LIMIT"

	FileLimitReached ErrorCode = "FILE_LIMIT_REACHED"

	FileInTrash ErrorCode = "FILE_IN_TRASH"

	SessionExpired ErrorCode = "SESSION_EXPIRED"

	LinkEditNotAllowed ErrorCode = "LINK_EDIT_NOT_ALLOWED"

	LinkDeviceLimitExceeded ErrorCode = "LINK_DEVICE_LIMIT_EXCEEDED"
	LinkExpired             ErrorCode = "LINK_EXPIRED"
	LinkDisabled            ErrorCode = "LINK_DISABLED"
	LinkUnavailable         ErrorCode = "LINK_UNAVAILABLE"

	ActiveRecoverySession ErrorCode = "ACTIVE_RECOVERY_SESSION"
)

type ApiError struct {
	// Code will be returned as part of the response body. Clients are expected to rely on this code while handling any error
	Code ErrorCode `json:"code"`
	// Optional message, which can give additional details about this error. Say for generic 404 error, it can return what entity is not found
	// like file/album/user. Client should never consume this message for showing err on screen or any special handling.
	Message        string `json:"message"`
	HttpStatusCode int    `json:"-"`
}

func (e *ApiError) NewErr(message string) *ApiError {
	return &ApiError{
		Code:           e.Code,
		Message:        message,
		HttpStatusCode: e.HttpStatusCode,
	}
}
func (e *ApiError) Error() string {
	return fmt.Sprintf("%s : %s", string(e.Code), e.Message)
}

type ApiErrorParams struct {
	HttpStatusCode *int
	Code           ErrorCode
	Message        string
}

var badRequestApiError = ApiError{
	Code:           BadRequest,
	HttpStatusCode: http.StatusBadRequest,
	Message:        "BAD_REQUEST",
}

func NewBadRequestError(params *ApiErrorParams) *ApiError {
	if params == nil {
		return &badRequestApiError
	}
	apiError := badRequestApiError
	if params.HttpStatusCode != nil {
		apiError.HttpStatusCode = *params.HttpStatusCode
	}
	if params.Message != "" {
		apiError.Message = params.Message
	}
	if params.Code != "" {
		apiError.Code = params.Code
	}
	return &apiError
}
func NewBadRequestWithMessage(message string) *ApiError {
	return &ApiError{
		Code:           BadRequest,
		HttpStatusCode: http.StatusBadRequest,
		Message:        message,
	}
}

func NewPermissionDeniedError(message string) *ApiError {
	return &ApiError{
		Code:           "PERMISSION_DENIED",
		HttpStatusCode: http.StatusForbidden,
		Message:        message,
	}
}

func NewConflictError(message string) *ApiError {
	return &ApiError{
		Code:           CONFLICT,
		HttpStatusCode: http.StatusConflict,
		Message:        message,
	}
}

func NewAlreadyExistsError(message string) *ApiError {
	return &ApiError{
		Code:           AlreadyExists,
		HttpStatusCode: http.StatusConflict,
		Message:        message,
	}
}

func NewInternalError(message string) *ApiError {
	apiError := ApiError{
		Code:           InternalError,
		HttpStatusCode: http.StatusInternalServerError,
		Message:        message,
	}
	return &apiError
}
