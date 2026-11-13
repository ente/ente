package user

import (
	"strings"
	"testing"
)

func TestRecoveryProof(t *testing.T) {
	for _, vector := range []struct {
		factor string
		secret string
		proof  string
	}{
		{"totp", "JBSWY3DPEHPK3PXP", "ywYHGQTm3D5kuYVTy8ZJf6KFUJMs/og5sRvtw19ungI="},
		{"passkey", "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=", "f+nF2g7+BGieMdZ8uJLndOcDP5GX2ffGgLk5DhHqKFI="},
	} {
		t.Run(vector.factor, func(t *testing.T) {
			if !verifyRecoveryProof(vector.secret, vector.factor, "recovery-session", vector.proof) {
				t.Fatal("valid proof rejected")
			}
			for _, tc := range []struct {
				name, secret, factor, session, proof string
			}{
				{"wrong secret", vector.secret + "x", vector.factor, "recovery-session", vector.proof},
				{"wrong factor", vector.secret, "other", "recovery-session", vector.proof},
				{"wrong session", vector.secret, vector.factor, "another-session", vector.proof},
				{"unpadded", vector.secret, vector.factor, "recovery-session", strings.TrimSuffix(vector.proof, "=")},
				{"url encoding", vector.secret, vector.factor, "recovery-session", strings.NewReplacer("/", "_", "+", "-").Replace(vector.proof)},
				{"newline", vector.secret, vector.factor, "recovery-session", vector.proof + "\n"},
				{"empty", vector.secret, vector.factor, "recovery-session", ""},
				{"malformed", vector.secret, vector.factor, "recovery-session", "!" + vector.proof[1:]},
			} {
				t.Run(tc.name, func(t *testing.T) {
					if verifyRecoveryProof(tc.secret, tc.factor, tc.session, tc.proof) {
						t.Fatal("invalid proof accepted")
					}
				})
			}
		})
	}
}
