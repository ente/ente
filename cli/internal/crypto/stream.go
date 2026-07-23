package crypto

import (
	"bytes"
	"crypto/rand"
	"encoding/binary"
	"errors"
	"golang.org/x/crypto/chacha20"
	"golang.org/x/crypto/chacha20poly1305"
	"golang.org/x/crypto/poly1305"
)

// public constants
const (
	//TagMessage the most common tag, that doesn't add any information about the nature of the message.
	TagMessage = 0
	// TagPush indicates that the message marks the end of a set of messages,
	// but not the end of the stream. For example, a huge JSON string sent as multiple chunks can use this tag to indicate to the application that the string is complete and that it can be decoded. But the stream itself is not closed, and more data may follow.
	TagPush = 0x01
	// TagRekey "forget" the key used to encrypt this message and the previous ones, and derive a new secret key.
	TagRekey = 0x02
	// TagFinal indicates that the message marks the end of the stream, and erases the secret key used to encrypt the previous sequence.
	TagFinal = TagPush | TagRekey

	StreamKeyBytes              = chacha20poly1305.KeySize
	StreamHeaderBytes           = chacha20poly1305.NonceSizeX
	XChaCha20Poly1305IetfABYTES = 16 + 1
)

const cryptoCoreHchacha20InputBytes = 16
const cryptoSecretStreamXchacha20poly1305Counterbytes = 4

var pad0 [16]byte

var invalidKey = errors.New("invalid key")
var invalidInput = errors.New("invalid input")
var cryptoFailure = errors.New("crypto failed")

type streamState struct {
	k     [StreamKeyBytes]byte
	nonce [chacha20poly1305.NonceSize]byte
	pad   [8]byte
}

func (s *streamState) reset() {
	for i := range s.nonce {
		s.nonce[i] = 0
	}
	s.nonce[0] = 1
}

type Encryptor interface {
	Push(m []byte, tag byte) ([]byte, error)
}

type Decryptor interface {
	Pull(m []byte) ([]byte, byte, error)
}

type encryptor struct {
	streamState
}

type decryptor struct {
	streamState
}

func NewStreamKey() []byte {
	k := make([]byte, chacha20poly1305.KeySize)
	rand.Read(k)
	return k
}

func NewEncryptor(key []byte) (Encryptor, []byte, error) {
	if len(key) != StreamKeyBytes {
		return nil, nil, invalidKey
	}

	header := make([]byte, StreamHeaderBytes)
	rand.Read(header)

	stream := &encryptor{}

	k, err := chacha20.HChaCha20(key[:], header[:16])
	if err != nil {
		//fmt.Printf("error: %v", err)
		return nil, nil, err
	}
	copy(stream.k[:], k)
	stream.reset()

	for i := range stream.pad {
		stream.pad[i] = 0
	}

	for i, b := range header[cryptoCoreHchacha20InputBytes:] {
		stream.nonce[i+cryptoSecretStreamXchacha20poly1305Counterbytes] = b
	}
	// fmt.Printf("stream: %+v\n", stream.streamState)

	return stream, header, nil
}

func (s *encryptor) Push(plain []byte, tag byte) ([]byte, error) {
	var err error

	var poly *poly1305.MAC
	var block [64]byte
	var slen [8]byte

	mlen := len(plain)
	out := make([]byte, mlen+XChaCha20Poly1305IetfABYTES)

	chacha, err := chacha20.NewUnauthenticatedCipher(s.k[:], s.nonce[:])
	if err != nil {
		return nil, err
	}
	chacha.XORKeyStream(block[:], block[:])

	var poly_init [32]byte
	copy(poly_init[:], block[:])
	poly = poly1305.New(&poly_init)

	memZero(block[:])
	block[0] = tag

	chacha.XORKeyStream(block[:], block[:])
	_, _ = poly.Write(block[:])
	out[0] = block[0]

	c := out[1:]
	chacha.XORKeyStream(c, plain)
	_, _ = poly.Write(c[:mlen])
	padlen := (0x10 - len(block) + mlen) & 0xf
	_, _ = poly.Write(pad0[:padlen])

	binary.LittleEndian.PutUint64(slen[:], uint64(0))
	_, _ = poly.Write(slen[:])

	binary.LittleEndian.PutUint64(slen[:], uint64(len(block)+mlen))
	_, _ = poly.Write(slen[:])

	mac := c[mlen:]
	copy(mac, poly.Sum(nil))

	xorBuf(s.nonce[cryptoSecretStreamXchacha20poly1305Counterbytes:], mac)
	bufInc(s.nonce[:cryptoSecretStreamXchacha20poly1305Counterbytes])

	return out, nil
}

func NewDecryptor(key, header []byte) (Decryptor, error) {
	stream := &decryptor{}

	k, err := chacha20.HChaCha20(key, header[:16])
	if err != nil {
		return nil, err
	}
	copy(stream.k[:], k)

	stream.reset()
	copy(stream.nonce[cryptoSecretStreamXchacha20poly1305Counterbytes:],
		header[cryptoCoreHchacha20InputBytes:])
	copy(stream.pad[:], pad0[:])

	return stream, nil
}

func (s *decryptor) Pull(cipher []byte) ([]byte, byte, error) {
	cipherLen := len(cipher)

	var poly1305State [32]byte
	var block [64]byte
	var slen [8]byte

	if cipherLen < XChaCha20Poly1305IetfABYTES {
		return nil, 0, invalidInput
	}
	mlen := cipherLen - XChaCha20Poly1305IetfABYTES

	chacha, err := chacha20.NewUnauthenticatedCipher(s.k[:], s.nonce[:])
	if err != nil {
		return nil, 0, err
	}
	chacha.XORKeyStream(block[:], block[:])

	copy(poly1305State[:], block[:])
	poly := poly1305.New(&poly1305State)

	memZero(block[:])
	block[0] = cipher[0]
	chacha.XORKeyStream(block[:], block[:])

	tag := block[0]
	block[0] = cipher[0]
	if _, err = poly.Write(block[:]); err != nil {
		return nil, 0, err
	}

	c := cipher[1:]
	if _, err = poly.Write(c[:mlen]); err != nil {
		return nil, 0, err
	}
	padLen := (0x10 - len(block) + mlen) & 0xf
	if _, err = poly.Write(pad0[:padLen]); err != nil {
		return nil, 0, err
	}

	binary.LittleEndian.PutUint64(slen[:], uint64(0))
	if _, err = poly.Write(slen[:]); err != nil {
		return nil, 0, err
	}

	binary.LittleEndian.PutUint64(slen[:], uint64(len(block)+mlen))
	if _, err = poly.Write(slen[:]); err != nil {
		return nil, 0, err
	}

	mac := poly.Sum(nil)
	memZero(poly1305State[:])

	storedMac := c[mlen:]
	if !bytes.Equal(mac, storedMac) {
		memZero(mac)
		return nil, 0, cryptoFailure
	}

	m := make([]byte, mlen)
	chacha.XORKeyStream(m, c[:mlen])

	xorBuf(s.nonce[cryptoSecretStreamXchacha20poly1305Counterbytes:], mac)
	bufInc(s.nonce[:cryptoSecretStreamXchacha20poly1305Counterbytes])

	return m, tag, nil
}
