package social

import (
	"strings"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/stretchr/testify/require"
)

func TestNormalizeSocialID(t *testing.T) {
	for _, tc := range []struct {
		name      string
		prefix    string
		normalize func(string) (string, error)
	}{
		{"comment", commentIDPrefix, NormalizeCommentID},
		{"reaction", reactionIDPrefix, NormalizeReactionID},
	} {
		t.Run(tc.name, func(t *testing.T) {
			valid := tc.prefix + strings.Repeat("a", nanoidSuffixLength-2) + "_-"
			actual, err := tc.normalize(valid)
			require.NoError(t, err)
			require.Equal(t, valid, actual)

			generated, err := tc.normalize("")
			require.NoError(t, err)
			actual, err = tc.normalize(generated)
			require.NoError(t, err)
			require.Equal(t, generated, actual)

			for _, invalid := range []string{
				tc.prefix + "/../../family/leave?a",
				tc.prefix + strings.Repeat("a", nanoidSuffixLength-3) + "%2F",
			} {
				_, err := tc.normalize(invalid)
				require.ErrorIs(t, err, ente.ErrBadRequest)
			}
		})
	}
}
