package byteMarshaller

import (
	"encoding/base64"
	"strings"
)

func EncodeSlices(slices [][]byte) string {
	var strSlices []string
	for _, slice := range slices {
		strSlices = append(strSlices, base64.StdEncoding.EncodeToString(slice))
	}
	return strings.Join(strSlices, ",")
}

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
