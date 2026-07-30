package pkg

import (
	"context"
	"fmt"
	"github.com/ente/cli/internal"
	"github.com/ente/cli/internal/api"
	eCrypto "github.com/ente/cli/internal/crypto"
	"github.com/ente/cli/pkg/model"
	"github.com/ente/cli/utils/browser"
	"github.com/ente/cli/utils/encoding"
	"log"

	"github.com/kong/go-srp"
)

func (c *ClICtrl) signInViaPassword(ctx context.Context, srpAttr *api.SRPAttributes) (*api.AuthorizationResponse, []byte, error) {
	for {
		// CLI prompt for password
		password, flowErr := internal.GetSensitiveField("Enter password")
		if flowErr != nil {
			return nil, nil, flowErr
		}
		fmt.Println("\nPlease wait authenticating...")
		keyEncKey, err := eCrypto.DeriveArgonKey(password, srpAttr.KekSalt, srpAttr.MemLimit, srpAttr.OpsLimit)
		if err != nil {
			fmt.Printf("error deriving key encryption key: %v", err)
			return nil, nil, err
		}
		loginKey := eCrypto.DeriveLoginKey(keyEncKey)

		srpParams := srp.GetParams(4096)
		identify := []byte(srpAttr.SRPUserID.String())
		salt := encoding.DecodeBase64(srpAttr.SRPSalt)
		clientSecret := srp.GenKey()
		srpClient := srp.NewClient(srpParams, salt, identify, loginKey, clientSecret)
		clientA := srpClient.ComputeA()
		session, err := c.Client.CreateSRPSession(ctx, srpAttr.SRPUserID, encoding.EncodeBase64(clientA))
		if err != nil {
			return nil, nil, err
		}
		serverB := session.SRPB
		srpClient.SetB(encoding.DecodeBase64(serverB))
		clientM := srpClient.ComputeM1()
		authResp, err := c.Client.VerifySRPSession(ctx, srpAttr.SRPUserID, session.SessionID, encoding.EncodeBase64(clientM))
		if err != nil {
			log.Printf("failed to verify %v", err)
			continue
		}
		return authResp, keyEncKey, nil
	}
}

// Parameters:
//   - keyEncKey: key encryption key is derived from user's password. During SRP based login, this key is already derived.
//     So, we can pass it to avoid asking for password again.
func (c *ClICtrl) decryptAccSecretInfo(
	_ context.Context,
	authResp *api.AuthorizationResponse,
	keyEncKey []byte,
) (*model.AccSecretInfo, error) {
	var currentKeyEncKey []byte
	var err error
	var masterKey, secretKey, tokenKey []byte
	var publicKey = encoding.DecodeBase64(authResp.KeyAttributes.PublicKey)
	for {
		if keyEncKey == nil {
			// CLI prompt for password
			password, flowErr := internal.GetSensitiveField("Enter password")
			if flowErr != nil {
				return nil, flowErr
			}
			fmt.Println("\nPlease wait authenticating...")
			currentKeyEncKey, err = eCrypto.DeriveArgonKey(password,
				authResp.KeyAttributes.KEKSalt, authResp.KeyAttributes.MemLimit, authResp.KeyAttributes.OpsLimit)
			if err != nil {
				fmt.Printf("error deriving key encryption key: %v", err)
				return nil, err
			}
		} else {
			currentKeyEncKey = keyEncKey
		}

		encryptedKey := encoding.DecodeBase64(authResp.KeyAttributes.EncryptedKey)
		encryptedKeyNonce := encoding.DecodeBase64(authResp.KeyAttributes.KeyDecryptionNonce)
		masterKey, err = eCrypto.SecretBoxOpen(encryptedKey, encryptedKeyNonce, currentKeyEncKey)
		if err != nil {
			if keyEncKey != nil {
				fmt.Printf("Failed to get key from keyEncryptionKey %s", err)
				return nil, err
			} else {
				fmt.Printf("Incorrect password, error decrypting master key: %v", err)
				continue
			}
		}
		secretKey, err = eCrypto.SecretBoxOpen(
			encoding.DecodeBase64(authResp.KeyAttributes.EncryptedSecretKey),
			encoding.DecodeBase64(authResp.KeyAttributes.SecretKeyDecryptionNonce),
			masterKey,
		)
		if err != nil {
			fmt.Printf("error decrypting master key: %v", err)
			return nil, err
		}
		tokenKey, err = eCrypto.SealedBoxOpen(
			encoding.DecodeBase64(authResp.EncryptedToken),
			publicKey,
			secretKey,
		)
		if err != nil {
			fmt.Printf("error decrypting token: %v", err)
			return nil, err
		}
		break
	}
	return &model.AccSecretInfo{
		MasterKey: masterKey,
		SecretKey: secretKey,
		Token:     tokenKey,
		PublicKey: publicKey,
	}, nil
}

func (c *ClICtrl) validateTOTP(ctx context.Context, authResp *api.AuthorizationResponse) (*api.AuthorizationResponse, error) {
	if !authResp.IsMFARequired() {
		return authResp, nil
	}
	for {
		// CLI prompt for TOTP
		totp, flowErr := internal.GetCode("Enter TOTP", 6)
		if flowErr != nil {
			return nil, flowErr
		}
		totpResp, err := c.Client.VerifyTotp(ctx, authResp.TwoFactorSessionID, totp)
		if err != nil {
			log.Printf("failed to verify %v", err)
			continue
		}
		return totpResp, nil
	}
}

func (c *ClICtrl) verifyPassKey(ctx context.Context, authResp *api.AuthorizationResponse, app api.App) (*api.AuthorizationResponse, error) {
	if !authResp.IsPasskeyRequired() {
		return authResp, nil
	}
	passkeyAuthUrl := fmt.Sprintf("%s/passkeys/verify?passkeySessionID=%s&redirect=ente-cli://passkey&clientPackage=%s", authResp.AccountsUrl, authResp.PassKeySessionID, app.ClientPkg())
	fmt.Printf("Open this url in browser to verify passkey: %s\n", passkeyAuthUrl)
	err := browser.OpenURL(passkeyAuthUrl)
	if err != nil {
		fmt.Printf("Failed to open browser: %v\n", err)
	}
	for {
		err = internal.WaitForEnter("Press enter once you have completed the passkey verification")
		if err != nil {
			return nil, err
		}
		totpResp, err := c.Client.CheckPasskeyStatus(ctx, authResp.PassKeySessionID)
		if err != nil {
			log.Printf("failed to verify %v", err)
			continue
		}
		return totpResp, nil
	}
}

func (c *ClICtrl) validateEmail(ctx context.Context, email string) (*api.AuthorizationResponse, error) {
	err := c.Client.SendLoginOTP(ctx, email)
	if err != nil {
		return nil, err
	}
	for {
		// CLI prompt for OTP
		ott, flowErr := internal.GetCode("Enter OTP", 6)
		if flowErr != nil {
			return nil, flowErr
		}
		authResponse, err := c.Client.VerifyEmail(ctx, email, ott)
		if err != nil {
			log.Printf("failed to verify %v", err)
			continue
		}
		return authResponse, nil
	}
}
