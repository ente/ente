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

// NormalizeCommentID optionally generates or validates a comment ID.
func NormalizeCommentID(id string) (string, error) {
	return normalizeOrGenerateID(commentIDPrefix, id)
}

// NormalizeReactionID optionally generates or validates a reaction ID.
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
	return id, nil
}

func generatePrefixedID(prefix string) (string, error) {
	random, err := gonanoid.New(nanoidSuffixLength)
	if err != nil {
		return "", err
	}
	return prefix + random, nil
}
