package ente

import (
	"encoding/base64"
	"strings"
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
			request := testSetAttributesRequest(testRecoveryKeyRequest())
			request.KeyAttributes.MemLimit = memLimit
			request.KeyAttributes.OpsLimit = opsLimit
			return request.Validate()
		}},
		{name: "update keys", validate: func(memLimit, opsLimit int64) error {
			request := testUpdateKeysRequest(testSetAttributesRequest(testRecoveryKeyRequest()).KeyAttributes)
			request.MemLimit = memLimit
			request.OpsLimit = opsLimit
			return request.Validate()
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

func TestKeyAttributeValidation(t *testing.T) {
	valid := testSetAttributesRequest(testRecoveryKeyRequest())
	require.NoError(t, valid.Validate())
	update := testUpdateKeysRequest(valid.KeyAttributes)
	require.NoError(t, update.Validate())

	for _, field := range []struct {
		name   string
		size   int
		value  func(*KeyAttributes) *string
		update bool
	}{
		{"salt", 16, func(k *KeyAttributes) *string { return &k.KEKSalt }, true},
		{"encrypted key", 48, func(k *KeyAttributes) *string { return &k.EncryptedKey }, true},
		{"key nonce", 24, func(k *KeyAttributes) *string { return &k.KeyDecryptionNonce }, true},
		{"public key", 32, func(k *KeyAttributes) *string { return &k.PublicKey }, false},
		{"encrypted secret key", 48, func(k *KeyAttributes) *string { return &k.EncryptedSecretKey }, false},
		{"secret key nonce", 24, func(k *KeyAttributes) *string { return &k.SecretKeyDecryptionNonce }, false},
	} {
		for _, invalid := range invalidBase64Values(field.size) {
			t.Run(field.name+"/"+invalid.name, func(t *testing.T) {
				request := valid
				*field.value(&request.KeyAttributes) = invalid.value
				assertBadRequestMessage(t, request.Validate(), invalid.message)
				if field.update {
					update := testUpdateKeysRequest(request.KeyAttributes)
					assertBadRequestMessage(t, update.Validate(), invalid.message)
				}
			})
		}
	}
}

func TestRecoveryKeyValidation(t *testing.T) {
	valid := testRecoveryKeyRequest()
	require.NoError(t, valid.Validate())
	setup := testSetAttributesRequest(valid)
	require.NoError(t, setup.Validate())

	for _, field := range []struct {
		name  string
		size  int
		value func(*SetRecoveryKeyRequest) *string
	}{
		{"master key", 48, func(r *SetRecoveryKeyRequest) *string { return &r.MasterKeyEncryptedWithRecoveryKey }},
		{"master key nonce", 24, func(r *SetRecoveryKeyRequest) *string { return &r.MasterKeyDecryptionNonce }},
		{"recovery key", 48, func(r *SetRecoveryKeyRequest) *string { return &r.RecoveryKeyEncryptedWithMasterKey }},
		{"recovery key nonce", 24, func(r *SetRecoveryKeyRequest) *string { return &r.RecoveryKeyDecryptionNonce }},
	} {
		for _, invalid := range invalidBase64Values(field.size) {
			t.Run(field.name+"/"+invalid.name, func(t *testing.T) {
				request := valid
				*field.value(&request) = invalid.value
				assertBadRequestMessage(t, request.Validate(), invalid.message)
				setup := testSetAttributesRequest(request)
				assertBadRequestMessage(t, setup.Validate(), invalid.message)
			})
		}
	}
}

func invalidBase64Values(size int) []struct{ name, value, message string } {
	valid := base64.StdEncoding.EncodeToString(make([]byte, size))
	values := []struct{ name, value, message string }{
		{"empty", "", "invalid length"},
		{"invalid base64", strings.Repeat("!", base64.StdEncoding.EncodedLen(size)), "invalid base64"},
		{"short", base64.StdEncoding.EncodeToString(make([]byte, size-1)), "invalid length"},
		{"long", base64.StdEncoding.EncodeToString(make([]byte, size+1)), "invalid length"},
		{"carriage return", valid[:4] + "\r" + valid[4:], "invalid length"},
		{"newline", valid[:4] + "\n" + valid[4:], "invalid length"},
	}
	if size%3 != 0 {
		lastSymbol := strings.IndexByte(valid, '=') - 1
		values = append(values,
			struct{ name, value, message string }{"missing padding", base64.RawStdEncoding.EncodeToString(make([]byte, size)), "invalid length"},
			struct{ name, value, message string }{"padding bits", valid[:lastSymbol] + "B" + valid[lastSymbol+1:], "invalid base64"},
		)
	}
	return values
}

func testRecoveryKeyRequest() SetRecoveryKeyRequest {
	encryptedKey := base64.StdEncoding.EncodeToString(make([]byte, 48))
	nonce := base64.StdEncoding.EncodeToString(make([]byte, 24))
	return SetRecoveryKeyRequest{
		MasterKeyEncryptedWithRecoveryKey: encryptedKey,
		MasterKeyDecryptionNonce:          nonce,
		RecoveryKeyEncryptedWithMasterKey: encryptedKey,
		RecoveryKeyDecryptionNonce:        nonce,
	}
}

func testSetAttributesRequest(recovery SetRecoveryKeyRequest) SetUserAttributesRequest {
	encryptedKey := base64.StdEncoding.EncodeToString(make([]byte, 48))
	nonce := base64.StdEncoding.EncodeToString(make([]byte, 24))
	return SetUserAttributesRequest{KeyAttributes: KeyAttributes{
		KEKSalt:                           base64.StdEncoding.EncodeToString(make([]byte, 16)),
		EncryptedKey:                      encryptedKey,
		KeyDecryptionNonce:                nonce,
		PublicKey:                         base64.StdEncoding.EncodeToString(make([]byte, 32)),
		EncryptedSecretKey:                encryptedKey,
		SecretKeyDecryptionNonce:          nonce,
		MemLimit:                          validArgonMemLimit,
		OpsLimit:                          validArgonOpsLimit,
		MasterKeyEncryptedWithRecoveryKey: recovery.MasterKeyEncryptedWithRecoveryKey,
		MasterKeyDecryptionNonce:          recovery.MasterKeyDecryptionNonce,
		RecoveryKeyEncryptedWithMasterKey: recovery.RecoveryKeyEncryptedWithMasterKey,
		RecoveryKeyDecryptionNonce:        recovery.RecoveryKeyDecryptionNonce,
	}}
}

func testUpdateKeysRequest(keys KeyAttributes) UpdateKeysRequest {
	return UpdateKeysRequest{
		KEKSalt:            keys.KEKSalt,
		EncryptedKey:       keys.EncryptedKey,
		KeyDecryptionNonce: keys.KeyDecryptionNonce,
		MemLimit:           keys.MemLimit,
		OpsLimit:           keys.OpsLimit,
	}
}

func TestUpdateSRPAndKeysRequestValidation(t *testing.T) {
	request := UpdateSRPAndKeysRequest{}
	assertBadRequestMessage(t, request.Validate(), "updatedKeyAttr is required")

	update := testUpdateKeysRequest(testSetAttributesRequest(testRecoveryKeyRequest()).KeyAttributes)
	request.UpdateAttributes = &update
	request.UpdateAttributes.OpsLimit--
	assertBadRequestMessage(t, request.Validate(), "Unexpected KDF strength")

	request.UpdateAttributes.OpsLimit = validArgonOpsLimit
	require.NoError(t, request.Validate())
	request.UpdateAttributes.EncryptedKey = strings.Repeat("!", base64.StdEncoding.EncodedLen(48))
	assertBadRequestMessage(t, request.Validate(), "invalid base64")
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
