package base

import (
	"errors"
	"fmt"
	"github.com/google/uuid"
	"github.com/matoous/go-nanoid/v2"
)

const alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

func NewID(prefix string) (*string, error) {
	if len(prefix) < 2 {
		return nil, errors.New("prefix must be at least 2 characters long")
	}
	for _, c := range prefix {
		if !(c >= 'a' && c <= 'z') {
			return nil, errors.New("prefix must only contain lower case alphabet characters")
		}
	}
	id, err := gonanoid.Generate(alphabet, 22)
	if err != nil {
		return nil, err
	}
	result := fmt.Sprintf("%s_%s", prefix, id)
	return &result, nil
}

func MustNewID(prefix string) string {
	id, err := NewID(prefix)
	if err != nil {
		panic(err)
	}
	return *id
}

func ServerReqID() string {
	id, err := NewID("ser")
	if err != nil {
		return "ser_" + uuid.New().String()
	}
	return *id
}
