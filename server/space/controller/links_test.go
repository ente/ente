package controller

import (
	"testing"

	"github.com/ente/museum/space/models"
	"github.com/stretchr/testify/require"
)

func TestDecodeSpaceLinkWriteRequestValidatesWireParameters(t *testing.T) {
	request := models.SpaceLinkWriteRequest{
		AuthKey:            encodeSpaceField(make([]byte, spaceLinkAuthKeyBytes)),
		KDFSalt:            encodeSpaceField(make([]byte, spaceLinkKDFSaltBytes)),
		KDFMemLimit:        spaceLinkKDFMemLimit,
		KDFOpsLimit:        spaceLinkKDFOpsLimit,
		KeyVersion:         1,
		EncryptedSpaceKey:  encodeSpaceField([]byte("encrypted-space-key")),
		EncryptedAccessKey: encodeSpaceField([]byte("encrypted-access-key")),
	}
	_, _, _, _, err := decodeSpaceLinkWriteRequest(request)
	require.NoError(t, err)

	request.KDFSalt = encodeSpaceField(make([]byte, spaceLinkKDFSaltBytes-1))
	_, _, _, _, err = decodeSpaceLinkWriteRequest(request)
	require.ErrorContains(t, err, "kdfSalt must be 16 bytes")

	request.KDFSalt = encodeSpaceField(make([]byte, spaceLinkKDFSaltBytes))
	request.KDFOpsLimit++
	_, _, _, _, err = decodeSpaceLinkWriteRequest(request)
	require.ErrorContains(t, err, "unsupported space link KDF parameters")
}
