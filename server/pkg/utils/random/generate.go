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

// GenerateAlphaNumString returns AlphaNumeric code of given length
// which exclude number 0 and letter O. The code always starts with an
// alphabet
func GenerateAlphaNumString(length int) (string, error) {
	// Define the alphabet and numbers to be used in the string.
	alphabet := "ABCDEFGHIJKLMNPQRSTUVWXYZ"
	// Define the alphabet and numbers to be used in the string.
	alphaNum := fmt.Sprintf("%s123456789", alphabet)
	// Allocate a byte slice with the desired length.
	result := make([]byte, length)
	// Generate the first letter as an alphabet.
	r0, err := auth.GenerateRandomInt(int64(len(alphabet)))
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	result[0] = alphabet[r0]
	// Generate the remaining characters as alphanumeric.
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
