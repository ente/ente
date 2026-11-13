package random

import (
	"fmt"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/stacktrace"
	"unicode"
)

func GenerateSixDigitOtp() (string, error) {
	n, err := auth.GenerateRandomInt(1_000_000)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	return fmt.Sprintf("%06d", n), nil
}

func GenerateAlphaNumString(length int) (string, error) {
	alphabet := "ABCDEFGHIJKLMNPQRSTUVWXYZ"
	alphaNum := fmt.Sprintf("%s123456789", alphabet)
	result := make([]byte, length)
	r0, err := auth.GenerateRandomInt(int64(len(alphabet)))
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	result[0] = alphabet[r0]
	for i := 1; i < length; i++ {
		ri, err := auth.GenerateRandomInt(int64(len(alphaNum)))
		if err != nil {
			return "", stacktrace.Propagate(err, "")
		}
		result[i] = alphaNum[ri]
	}
	return string(result), nil
}

func IsAlphanumeric(s string) bool {
	for _, r := range s {
		if !unicode.IsLetter(r) && !unicode.IsDigit(r) {
			return false
		}
	}
	return true
}
