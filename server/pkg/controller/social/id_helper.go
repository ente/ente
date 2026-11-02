package social

import (
	"strings"

	"github.com/ente/museum/ente"
	gonanoid "github.com/matoous/go-nanoid/v2"
)

const (
	commentIDPrefix    = "cmt_"
	reactionIDPrefix   = "rct_"
	anonIDPrefix       = "anon_"
	nanoidSuffixLength = 21
)

func NormalizeCommentID(id string) (string, error) {
	return normalizeOrGenerateID(commentIDPrefix, id)
}

func NormalizeReactionID(id string) (string, error) {
	return normalizeOrGenerateID(reactionIDPrefix, id)
}

func normalizeOrGenerateID(prefix, id string) (string, error) {
	if id == "" {
		return generatePrefixedID(prefix)
	}
	if !strings.HasPrefix(id, prefix) {
		return "", ente.ErrBadRequest
	}
	if len(id) != len(prefix)+nanoidSuffixLength {
		return "", ente.ErrBadRequest
	}
	for _, ch := range id[len(prefix):] {
		if !(ch >= 'a' && ch <= 'z' || ch >= 'A' && ch <= 'Z' || ch >= '0' && ch <= '9' || ch == '_' || ch == '-') {
			return "", ente.ErrBadRequest
		}
	}
	return id, nil
}

func generatePrefixedID(prefix string) (string, error) {
	random, err := gonanoid.New(nanoidSuffixLength)
	if err != nil {
		return "", err
	}
	return prefix + random, nil
}
