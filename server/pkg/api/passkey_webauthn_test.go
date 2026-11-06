// Synthetic WebAuthn messages exercise the real verifier in enrollment tests.
// The fixed scalar below is a public test value, never a real credential.
package api

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"math/big"
	"net/http"
	"net/http/httptest"

	"github.com/fxamacker/cbor/v2"
)

const passkeyTestRPID = "focused-passkey.invalid"
const passkeyTestOrigin = "https://focused-passkey.invalid"

func passkeyTestKey() *ecdsa.PrivateKey {
	curve := elliptic.P256()
	x, y := curve.ScalarBaseMult([]byte{1})
	return &ecdsa.PrivateKey{PublicKey: ecdsa.PublicKey{Curve: curve, X: x, Y: y}, D: big.NewInt(1)}
}
func passkeyTestEncode(b []byte) string { return base64.RawURLEncoding.EncodeToString(b) }
func passkeyTestRequest(v any) (*http.Request, error) {
	b, err := json.Marshal(v)
	if err != nil {
		return nil, err
	}
	r := httptest.NewRequest(http.MethodPost, passkeyTestOrigin+"/synthetic", bytes.NewReader(b))
	r.Header.Set("Content-Type", "application/json")
	return r, nil
}
func passkeyTestClientData(kind, challenge, origin string) ([]byte, error) {
	return json.Marshal(map[string]any{"type": kind, "challenge": challenge, "origin": origin, "crossOrigin": false})
}
func passkeyTestAuthData(rpID string, flags byte) []byte {
	h := sha256.Sum256([]byte(rpID))
	b := append([]byte{}, h[:]...)
	return append(b, flags, 0, 0, 0, 1)
}

// passkeyTestRegistration uses attestation=none, a well-formed ES256 COSE public key,
// and caller-specified challenge/RP/origin/UP+UV flags. No verifier is replaced.
func passkeyTestRegistration(challenge string, id []byte, origin, rpID string, flags byte) (*http.Request, error) {
	k := passkeyTestKey()
	pub, err := cbor.Marshal(map[int]any{1: 2, 3: -7, -1: 1, -2: k.X.FillBytes(make([]byte, 32)), -3: k.Y.FillBytes(make([]byte, 32))})
	if err != nil {
		return nil, err
	}
	a := append(passkeyTestAuthData(rpID, flags|0x40), make([]byte, 16)...)
	a = binary.BigEndian.AppendUint16(a, uint16(len(id)))
	a = append(a, id...)
	a = append(a, pub...)
	att, err := cbor.Marshal(map[string]any{"fmt": "none", "attStmt": map[string]any{}, "authData": a})
	if err != nil {
		return nil, err
	}
	cd, err := passkeyTestClientData("webauthn.create", challenge, origin)
	if err != nil {
		return nil, err
	}
	return passkeyTestRequest(map[string]any{"id": passkeyTestEncode(id), "rawId": passkeyTestEncode(id), "type": "public-key", "response": map[string]any{"clientDataJSON": passkeyTestEncode(cd), "attestationObject": passkeyTestEncode(att), "transports": []string{"internal"}}})
}

func passkeyTestAssertion(challenge string, id []byte, userID []byte, origin, rpID string) (*http.Request, error) {
	cd, err := passkeyTestClientData("webauthn.get", challenge, origin)
	if err != nil {
		return nil, err
	}
	a := passkeyTestAuthData(rpID, 0x05)
	h := sha256.Sum256(cd)
	signed := append(append([]byte{}, a...), h[:]...)
	digest := sha256.Sum256(signed)
	sig, err := ecdsa.SignASN1(rand.Reader, passkeyTestKey(), digest[:])
	if err != nil {
		return nil, err
	}
	return passkeyTestRequest(map[string]any{"id": passkeyTestEncode(id), "rawId": passkeyTestEncode(id), "type": "public-key", "response": map[string]any{"clientDataJSON": passkeyTestEncode(cd), "authenticatorData": passkeyTestEncode(a), "signature": passkeyTestEncode(sig), "userHandle": passkeyTestEncode(userID)}})
}
