package storagebonus

import (
	"net/http"

	"github.com/ente/museum/ente"
)

const (
	invalid            ente.ErrorCode = "INVALID_CODE"
	codeApplied        ente.ErrorCode = "CODE_ALREADY_APPLIED"
	codeExists         ente.ErrorCode = "CODE_ALREADY_EXISTS"
	accountNotEligible ente.ErrorCode = "ACCOUNT_NOT_ELIGIBLE"
)

// InvalidCodeErr is thrown when user gives a code which either doesn't exist or belong to a now deleted user
var InvalidCodeErr = &ente.ApiError{
	Code:           invalid,
	Message:        "Invalid code",
	HttpStatusCode: http.StatusNotFound,
}

var CodeAlreadyAppliedErr = &ente.ApiError{
	Code:           codeApplied,
	Message:        "User has already applied code",
	HttpStatusCode: http.StatusConflict,
}

var CanNotApplyCodeErr = &ente.ApiError{
	Code:           accountNotEligible,
	Message:        "User is not eligible to apply referral code",
	HttpStatusCode: http.StatusBadRequest,
}

var CodeAlreadyExistsErr = &ente.ApiError{
	Code:           codeExists,
	Message:        "This code already exists",
	HttpStatusCode: http.StatusBadRequest,
}
