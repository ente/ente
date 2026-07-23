package ente

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"time"

	"github.com/ente/museum/pkg/utils/byteMarshaller"
	"github.com/go-webauthn/webauthn/protocol"
	"github.com/go-webauthn/webauthn/webauthn"
	"github.com/google/uuid"
)

// WebAuthnSession is a protocol level session that stores challenges and other metadata during registration and login ceremonies
type WebAuthnSession struct {
	ID uuid.UUID

	Challenge string

	UserID int64

	RPID string

	AllowedCredentialIDs string // [][]byte as b64

	ExpiresAt int64

	UserVerificationRequirement string

	Extensions string // map[string]interface{} as json

	CreatedAt int64
}

func (w *WebAuthnSession) SessionData() (session *webauthn.SessionData, err error) {
	buf := new(bytes.Buffer)
	err = binary.Write(buf, binary.BigEndian, w.UserID)
	if err != nil {
		return
	}

	allowedCredentialIDs, err := byteMarshaller.DecodeString(w.AllowedCredentialIDs)
	if err != nil {
		return
	}

	extensions := map[string]interface{}{}
	err = json.Unmarshal([]byte(w.Extensions), &extensions)
	if err != nil {
		return
	}

	session = &webauthn.SessionData{
		Challenge:            w.Challenge,
		UserID:               buf.Bytes(),
		AllowedCredentialIDs: allowedCredentialIDs,
		Expires:              time.UnixMicro(w.ExpiresAt),

		UserVerification: protocol.UserVerificationRequirement(w.UserVerificationRequirement),
		Extensions:       extensions,
	}

	return
}
