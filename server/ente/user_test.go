package ente

import (
	"testing"

	"github.com/stretchr/testify/require"
)

const (
	validArgonMemLimit = 128 * 1024 * 1024
	validArgonOpsLimit = 32
)

func TestKeyRequestValidation(t *testing.T) {
	validators := []struct {
		name     string
		validate func(memLimit, opsLimit int64) error
	}{
		{name: "set attributes", validate: func(memLimit, opsLimit int64) error {
			return (&SetUserAttributesRequest{KeyAttributes: KeyAttributes{
				MemLimit: memLimit,
				OpsLimit: opsLimit,
			}}).Validate()
		}},
		{name: "update keys", validate: func(memLimit, opsLimit int64) error {
			return (&UpdateKeysRequest{MemLimit: memLimit, OpsLimit: opsLimit}).Validate()
		}},
	}

	for _, validator := range validators {
		t.Run(validator.name, func(t *testing.T) {
			assertBadRequestMessage(
				t,
				validator.validate(validArgonMemLimit, validArgonOpsLimit-1),
				"Unexpected KDF strength",
			)
			require.NoError(t, validator.validate(validArgonMemLimit, validArgonOpsLimit))
			assertBadRequestMessage(
				t,
				validator.validate(64*1024*1024, 64),
				"memory limit must be at least 128MB",
			)
		})
	}
}

func assertBadRequestMessage(t *testing.T, err error, wantMessage string) {
	t.Helper()

	if err == nil {
		t.Fatalf("expected validation error %q, got nil", wantMessage)
	}

	apiErr, ok := err.(*ApiError)
	if !ok {
		t.Fatalf("expected *ApiError, got %T", err)
	}

	if apiErr.Code != BadRequest {
		t.Fatalf("expected error code %q, got %q", BadRequest, apiErr.Code)
	}

	if apiErr.Message != wantMessage {
		t.Fatalf("expected error message %q, got %q", wantMessage, apiErr.Message)
	}
}
