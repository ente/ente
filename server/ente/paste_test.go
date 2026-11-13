package ente

import (
	"encoding/base64"
	"strings"
	"testing"
)

func newValidPasteRequest() CreatePasteRequest {
	return CreatePasteRequest{
		EncryptedData:          "encrypted-data",
		DecryptionHeader:       "decryption-header",
		EncryptedPasteKey:      "encrypted-paste-key",
		EncryptedPasteKeyNonce: "encrypted-paste-key-nonce",
		KdfNonce:               base64.StdEncoding.EncodeToString(make([]byte, pasteKdfSaltBytes)),
		KdfMemLimit:            pasteKdfMemLimitInteractive,
		KdfOpsLimit:            pasteKdfOpsLimitInteractive,
	}
}

func TestCreatePasteRequestValidate(t *testing.T) {
	tests := []struct {
		name    string
		mutate  func(*CreatePasteRequest)
		wantErr bool
	}{
		{name: "interactive parameters"},
		{name: "moderate parameters", mutate: func(req *CreatePasteRequest) {
			req.KdfMemLimit = pasteKdfMemLimitModerate
			req.KdfOpsLimit = pasteKdfOpsLimitModerate
		}},
		{name: "oversized payload", wantErr: true, mutate: func(req *CreatePasteRequest) {
			req.EncryptedData = strings.Repeat("a", 1025)
		}},
		{name: "oversized decryption header", wantErr: true, mutate: func(req *CreatePasteRequest) {
			req.DecryptionHeader = strings.Repeat("a", pasteDecryptionHeaderMaxLength+1)
		}},
		{name: "oversized encrypted paste key", wantErr: true, mutate: func(req *CreatePasteRequest) {
			req.EncryptedPasteKey = strings.Repeat("a", pasteEncryptedPasteKeyMaxLength+1)
		}},
		{name: "oversized encrypted paste key nonce", wantErr: true, mutate: func(req *CreatePasteRequest) {
			req.EncryptedPasteKeyNonce = strings.Repeat("a", pasteEncryptedPasteKeyNonceMaxLength+1)
		}},
		{name: "oversized KDF nonce", wantErr: true, mutate: func(req *CreatePasteRequest) {
			req.KdfNonce = strings.Repeat("a", pasteKdfNonceMaxLength+1)
		}},
		{name: "invalid KDF nonce encoding", wantErr: true, mutate: func(req *CreatePasteRequest) {
			req.KdfNonce = "not-base64@@@"
		}},
		{name: "invalid KDF nonce length", wantErr: true, mutate: func(req *CreatePasteRequest) {
			req.KdfNonce = base64.StdEncoding.EncodeToString(make([]byte, 8))
		}},
		{name: "invalid KDF cost", wantErr: true, mutate: func(req *CreatePasteRequest) {
			req.KdfMemLimit = pasteKdfMemLimitInteractive * 2
			req.KdfOpsLimit = pasteKdfOpsLimitInteractive * 2
		}},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			req := newValidPasteRequest()
			if test.mutate != nil {
				test.mutate(&req)
			}
			if err := req.Validate(1024); (err != nil) != test.wantErr {
				t.Fatalf("Validate() error = %v, wantErr %t", err, test.wantErr)
			}
		})
	}
}
