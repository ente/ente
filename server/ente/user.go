package ente

const (
	OTTTemplate       = "ott.html"
	OTTMobileTemplate = "ott_mobile.html"

	ChangeEmailOTTTemplate = "ott_change_email.html"
	EmailChangedTemplate   = "email_changed.html"
	EmailChangedSubject    = "Email address updated"

	ChangeEmailOTTPurpose = "change"
	SignUpOTTPurpose      = "signup"
	LoginOTTPurpose       = "login"

	ExpectedKDFStrength = int64(1073741824 * 4)
)

type User struct {
	ID                 int64
	Email              string `json:"email"`
	Name               string `json:"name"`
	Hash               string `json:"hash"`
	CreationTime       int64  `json:"creationTime"`
	FamilyAdminID      *int64 `json:"familyAdminID"`
	IsTwoFactorEnabled *bool  `json:"isTwoFactorEnabled"`
	IsEmailMFAEnabled  *bool  `json:"isEmailMFAEnabled"`
}

type SendOTTRequest struct {
	Email   string `json:"email"`
	Client  string `json:"client"`
	Purpose string `json:"purpose"`
	Mobile  bool   `json:"mobile"`
}

type EmailVerificationRequest struct {
	Email  string  `json:"email"`
	OTT    string  `json:"ott"`
	Source *string `json:"source"`
}

type EmailVerificationResponse struct {
	ID            int64         `json:"id"`
	Token         string        `json:"token"`
	KeyAttributes KeyAttributes `json:"keyAttributes"`
	Subscription  Subscription  `json:"subscription"`
}

type EmailAuthorizationResponse struct {
	ID                 int64          `json:"id"`
	KeyAttributes      *KeyAttributes `json:"keyAttributes,omitempty"`
	EncryptedToken     string         `json:"encryptedToken,omitempty"`
	Token              string         `json:"token,omitempty"`
	PasskeySessionID   string         `json:"passkeySessionID"`
	AccountsUrl        string         `json:"accountsUrl"`
	TwoFactorSessionID string         `json:"twoFactorSessionID"`
	// TwoFactorSessionIDV2 is set only if user has both passkey and two factor enabled.
	// This is to ensure older clients keep using passkey flow when both are set. We can remove
	// This field once the clients starts surface both options for performing 2fa
	TwoFactorSessionIDV2 string `json:"twoFactorSessionIDV2"`
	// SRP server proof, set only for SRP logins.
	SrpM2 *string `json:"srpM2,omitempty"`
}

type KeyAttributes struct {
	KEKSalt                           string `json:"kekSalt" binding:"required"`
	KEKHash                           string `json:"kekHash"`
	EncryptedKey                      string `json:"encryptedKey" binding:"required"`
	KeyDecryptionNonce                string `json:"keyDecryptionNonce" binding:"required"`
	PublicKey                         string `json:"publicKey" binding:"required"`
	EncryptedSecretKey                string `json:"encryptedSecretKey" binding:"required"`
	SecretKeyDecryptionNonce          string `json:"secretKeyDecryptionNonce" binding:"required"`
	MemLimit                          int64  `json:"memLimit" binding:"required"`
	OpsLimit                          int64  `json:"opsLimit" binding:"required"`
	MasterKeyEncryptedWithRecoveryKey string `json:"masterKeyEncryptedWithRecoveryKey"`
	MasterKeyDecryptionNonce          string `json:"masterKeyDecryptionNonce"`
	RecoveryKeyEncryptedWithMasterKey string `json:"recoveryKeyEncryptedWithMasterKey"`
	RecoveryKeyDecryptionNonce        string `json:"recoveryKeyDecryptionNonce"`
}

type SetUserAttributesRequest struct {
	KeyAttributes KeyAttributes `json:"keyAttributes" binding:"required"`
}

func (sk *SetUserAttributesRequest) Validate() error {
	strength := sk.KeyAttributes.MemLimit * sk.KeyAttributes.OpsLimit
	if strength != ExpectedKDFStrength {
		return NewBadRequestWithMessage("Unexpected KDF strength")
	}
	if sk.KeyAttributes.MemLimit < 128*1024*1024 {
		return NewBadRequestWithMessage("memory limit must be at least 128MB")
	}
	return nil
}

type UpdateEmailMFA struct {
	IsEnabled *bool `json:"isEnabled" binding:"required"`
}

type UpdateKeysRequest struct {
	KEKSalt            string `json:"kekSalt" binding:"required"`
	EncryptedKey       string `json:"encryptedKey" binding:"required"`
	KeyDecryptionNonce string `json:"keyDecryptionNonce" binding:"required"`
	MemLimit           int64  `json:"memLimit" binding:"required"`
	OpsLimit           int64  `json:"opsLimit" binding:"required"`
}

func (u *UpdateKeysRequest) Validate() error {
	strength := u.MemLimit * u.OpsLimit
	if strength != ExpectedKDFStrength {
		return NewBadRequestWithMessage("Unexpected KDF strength")
	}
	if u.MemLimit < 128*1024*1024 {
		return NewBadRequestWithMessage("memory limit must be at least 128MB")
	}
	return nil
}

type SetRecoveryKeyRequest struct {
	MasterKeyEncryptedWithRecoveryKey string `json:"masterKeyEncryptedWithRecoveryKey"`
	MasterKeyDecryptionNonce          string `json:"masterKeyDecryptionNonce"`
	RecoveryKeyEncryptedWithMasterKey string `json:"recoveryKeyEncryptedWithMasterKey"`
	RecoveryKeyDecryptionNonce        string `json:"recoveryKeyDecryptionNonce"`
}

type EventReportRequest struct {
	Event string `json:"event"`
}

type EncryptionResult struct {
	Cipher []byte
	Nonce  []byte
}

type DeleteChallengeResponse struct {
	AllowDelete        bool    `json:"allowDelete"`
	EncryptedChallenge *string `json:"encryptedChallenge,omitempty"`
	Apps               []App   `json:"apps"`
}

type DeleteAccountRequest struct {
	Challenge      string  `json:"challenge"`
	Feedback       *string `json:"feedback"`
	ReasonCategory *string `json:"reasonCategory"`
	Reason         *string `json:"reason"`
}

func (r *DeleteAccountRequest) GetReasonAttr() map[string]string {
	result := make(map[string]string)
	// Note: mobile client is sending reasonCategory, but web/desktop is sending reason
	if r.ReasonCategory != nil {
		result["reason"] = *r.ReasonCategory
	}
	if r.Reason != nil {
		result["reason"] = *r.Reason
	}
	if r.Feedback != nil {
		result["feedback"] = *r.Feedback
	}
	return result
}

type DeleteAccountResponse struct {
	IsSubscriptionCancelled bool  `json:"isSubscriptionCancelled"`
	UserID                  int64 `json:"userID"`
}

type AccountRecoveryRequest struct {
	Token string `json:"token" binding:"required"`
}

type AccountRecoveryStatus string

const (
	AccountRecoveryReady     AccountRecoveryStatus = "ready"
	AccountRecoveryRecovered AccountRecoveryStatus = "recovered"
)

type AccountRecoveryResponse struct {
	Status AccountRecoveryStatus `json:"status"`
}

type TwoFactorSecret struct {
	SecretCode string `json:"secretCode"`
	QRCode     string `json:"qrCode"`
}

type TwoFactorEnableRequest struct {
	Code                           string `json:"code"`
	EncryptedTwoFactorSecret       string `json:"encryptedTwoFactorSecret"`
	TwoFactorSecretDecryptionNonce string `json:"twoFactorSecretDecryptionNonce"`
}

type TwoFactorVerificationRequest struct {
	SessionID string `json:"sessionID" binding:"required"`
	Code      string `json:"code" binding:"required"`
}

type PasskeyTwoFactorBeginAuthenticationCeremonyRequest struct {
	SessionID string `json:"sessionID" binding:"required"`
}

type PasskeyTwoFactorFinishAuthenticationCeremonyRequest struct {
	SessionID         string `form:"sessionID" binding:"required"`
	CeremonySessionID string `form:"ceremonySessionID" binding:"required"`
}

type TwoFactorAuthorizationResponse struct {
	ID             int64          `json:"id"`
	KeyAttributes  *KeyAttributes `json:"keyAttributes,omitempty"`
	EncryptedToken string         `json:"encryptedToken,omitempty"`
}

type TwoFactorRecoveryResponse struct {
	EncryptedSecret       string `json:"encryptedSecret"`
	SecretDecryptionNonce string `json:"secretDecryptionNonce"`
}

type TwoFactorRemovalRequest struct {
	Secret        string `json:"secret"`
	SessionID     string `json:"sessionID"`
	TwoFactorType string `json:"twoFactorType"`
}

type ProfileData struct {
	CanDisableEmailMFA bool  `json:"canDisableEmailMFA"`
	IsEmailMFAEnabled  bool  `json:"isEmailMFAEnabled"`
	IsTwoFactorEnabled bool  `json:"isTwoFactorEnabled"`
	PasskeyCount       int64 `json:"passkeyCount"`
}

type Session struct {
	Token        string `json:"token"`
	CreationTime int64  `json:"creationTime"`
	IP           string `json:"ip"`
	UA           string `json:"ua"`
	PrettyUA     string `json:"prettyUA"`
	LastUsedTime int64  `json:"lastUsedTime"`
}

type BasicUser struct {
	ID    int64  `json:"id"`
	Email string `json:"email"`
}
