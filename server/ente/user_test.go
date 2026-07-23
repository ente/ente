package ente

import (
	"testing"

	"github.com/stretchr/testify/require"
)

const (
	validArgonMemLimit = 128 * 1024 * 1024
	validArgonOpsLimit = 32
)

func TestSetUserAttributesRequestValidate_RejectsUnexpectedKDFStrength(t *testing.T) {
	req := SetUserAttributesRequest{
		KeyAttributes: KeyAttributes{
			MemLimit: validArgonMemLimit,
			OpsLimit: validArgonOpsLimit - 1,
		},
	}

	assertBadRequestMessage(t, req.Validate(), "Unexpected KDF strength")
}

func TestSetUserAttributesRequestValidate_AllowsMinimumMemory(t *testing.T) {
	req := SetUserAttributesRequest{
		KeyAttributes: KeyAttributes{
			MemLimit: 128 * 1024 * 1024,
			OpsLimit: validArgonOpsLimit,
		},
	}

	require.NoError(t, req.Validate())
}

func TestSetUserAttributesRequestValidate_RejectsLowMemoryLimit(t *testing.T) {
	req := SetUserAttributesRequest{
		KeyAttributes: KeyAttributes{
			MemLimit: 64 * 1024 * 1024,
			OpsLimit: 64,
		},
	}

	assertBadRequestMessage(t, req.Validate(), "memory limit must be at least 128MB")
}

func TestUpdateKeysRequestValidate_RejectsUnexpectedKDFStrength(t *testing.T) {
	req := UpdateKeysRequest{
		MemLimit: validArgonMemLimit,
		OpsLimit: validArgonOpsLimit - 1,
	}

	assertBadRequestMessage(t, req.Validate(), "Unexpected KDF strength")
}

func TestUpdateKeysRequestValidate_AllowsMinimumMemory(t *testing.T) {
	req := UpdateKeysRequest{
		MemLimit: 128 * 1024 * 1024,
		OpsLimit: validArgonOpsLimit,
	}

	require.NoError(t, req.Validate())
}

func TestUpdateKeysRequestValidate_RejectsLowMemoryLimit(t *testing.T) {
	req := UpdateKeysRequest{
		MemLimit: 64 * 1024 * 1024,
		OpsLimit: 64,
	}

	assertBadRequestMessage(t, req.Validate(), "memory limit must be at least 128MB")
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
