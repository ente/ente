package byteMarshaller

import (
	"encoding/base64"
	"strings"
)

// Encode a [][]byte into a single string.
func EncodeSlices(slices [][]byte) string {
	var strSlices []string
	for _, slice := range slices {
		strSlices = append(strSlices, base64.StdEncoding.EncodeToString(slice))
	}
	// Join the encoded strings with a comma, which is not in the base64 alphabet.
	return strings.Join(strSlices, ",")
}

// Decode a string back into a [][]byte.
func DecodeString(encoded string) ([][]byte, error) {
	var byteSlices [][]byte
	for str := range strings.SplitSeq(encoded, ",") {
		slice, err := base64.StdEncoding.DecodeString(str)
		if err != nil {
			return nil, err
		}
		byteSlices = append(byteSlices, slice)
	}
	return byteSlices, nil
}
