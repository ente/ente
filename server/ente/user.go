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

// User represents a user in the system
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

// A request to generate and send a verification code (OTT)
type SendOTTRequest struct {
	Email   string `json:"email"`
	Client  string `json:"client"`
	Purpose string `json:"purpose"`
	// Mobile indicates whether the request is coming from a mobile client`
	Mobile bool `json:"mobile"`
}

// EmailVerificationRequest represents an email verification request
type EmailVerificationRequest struct {
	Email string `json:"email"`
	OTT   string `json:"ott"`
	// Indicates where the source form where the user heard about the service
	Source *string `json:"source"`
}

type EmailVerificationResponse struct {
	ID            int64         `json:"id"`
	Token         string        `json:"token"`
	KeyAttributes KeyAttributes `json:"keyAttributes"`
	Subscription  Subscription  `json:"subscription"`
}

// EmailAuthorizationResponse represents the response after user has verified his email,
// if two factor enabled just `TwoFactorSessionID` is sent else the keyAttributes and encryptedToken
type EmailAuthorizationResponse struct {
	ID               int64          `json:"id"`
	KeyAttributes    *KeyAttributes `json:"keyAttributes,omitempty"`
	EncryptedToken   string         `json:"encryptedToken,omitempty"`
	Token            string         `json:"token,omitempty"`
	PasskeySessionID string         `json:"passkeySessionID"`
	// AccountsUrl is the url used for passkey validation
	AccountsUrl        string `json:"accountsUrl"`
	TwoFactorSessionID string `json:"twoFactorSessionID"`
	// TwoFactorSessionIDV2 is set only if user has both passkey and two factor enabled.
	// This is to ensure older clients keep using passkey flow when both are set. We can remove
	// This field once the clients starts surface both options for performing 2fa
	TwoFactorSessionIDV2 string `json:"twoFactorSessionIDV2"`
	// SrpM2 is sent only if the user is logging via SRP
	// SrpM2 is the SRP M2 value aka the proof that the server has the verifier
	SrpM2 *string `json:"srpM2,omitempty"`
}

// KeyAttributes stores the key related attributes for a user
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

// SetUserAttributesRequest represents an incoming request to set UA
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

// UpdateEmailMFA ..
type UpdateEmailMFA struct {
	IsEnabled *bool `json:"isEnabled" binding:"required"`
}

// UpdateKeysRequest represents a request to set user keys
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
	// AllowDelete indicates whether the user is allowed to delete their account via app
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

// TwoFactorSecret represents the two factor secret generator value, user enters in his authenticator app
type TwoFactorSecret struct {
	SecretCode string `json:"secretCode"`
	QRCode     string `json:"qrCode"`
}

// TwoFactorEnableRequest represent the user request to enable two factor after initial setup
type TwoFactorEnableRequest struct {
	Code                           string `json:"code"`
	EncryptedTwoFactorSecret       string `json:"encryptedTwoFactorSecret"`
	TwoFactorSecretDecryptionNonce string `json:"twoFactorSecretDecryptionNonce"`
}

// TwoFactorVerificationRequest represents a two factor verification request
type TwoFactorVerificationRequest struct {
	SessionID string `json:"sessionID" binding:"required"`
	Code      string `json:"code" binding:"required"`
}

// TwoFactorBeginAuthenticationCeremonyRequest represents the request to begin the passkey authentication ceremony
type PasskeyTwoFactorBeginAuthenticationCeremonyRequest struct {
	SessionID string `json:"sessionID" binding:"required"`
}

type PasskeyTwoFactorFinishAuthenticationCeremonyRequest struct {
	SessionID         string `form:"sessionID" binding:"required"`
	CeremonySessionID string `form:"ceremonySessionID" binding:"required"`
}

// TwoFactorAuthorizationResponse represents the response after two factor authentication
type TwoFactorAuthorizationResponse struct {
	ID             int64          `json:"id"`
	KeyAttributes  *KeyAttributes `json:"keyAttributes,omitempty"`
	EncryptedToken string         `json:"encryptedToken,omitempty"`
}

// TwoFactorRecoveryResponse represents the two factor secret encrypted with user's recovery key sent for user to make removal request
type TwoFactorRecoveryResponse struct {
	EncryptedSecret       string `json:"encryptedSecret"`
	SecretDecryptionNonce string `json:"secretDecryptionNonce"`
}

// TwoFactorRemovalRequest represents the the body of two factor removal request consist of decrypted two factor secret and sessionID
type TwoFactorRemovalRequest struct {
	Secret        string `json:"secret"`
	SessionID     string `json:"sessionID"`
	TwoFactorType string `json:"twoFactorType"`
}

type ProfileData struct {
	// CanDisableEmailMFA is used to decide if client should show disable email MFA option
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
