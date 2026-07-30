package passkey

import (
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	emailUtil "github.com/ente/museum/pkg/utils/email"
	ente_time "github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
	"github.com/go-webauthn/webauthn/protocol"
	"github.com/google/uuid"
	"github.com/sirupsen/logrus"
	"github.com/spf13/viper"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/byteMarshaller"
	"github.com/go-webauthn/webauthn/webauthn"
)

const (
	// MaxSessionTokenFetchLimit specifies the maximum number of requests a client can make to retrieve token data for a given session ID.
	MaxSessionTokenFetchLimit = 2
	// TokenFetchAllowedDurationInMin is the duration in minutes for which the token fetch is allowed after the session is verified.
	TokenFetchAllowedDurationInMin = 2
)

type Repository struct {
	DB                     *sql.DB
	RPID                   string
	webAuthnInstance       *webauthn.WebAuthn
	accountsURL            string
	legacyRPID             string
	legacyWebAuthnInstance *webauthn.WebAuthn
	legacyAccountsURL      string
}

type PasskeyUser struct {
	*ente.User
	repo *Repository
	rpID string
}

func (u *PasskeyUser) WebAuthnID() []byte {
	b, _ := byteMarshaller.ConvertInt64ToByte(u.ID)
	return b
}

func (u *PasskeyUser) WebAuthnName() string {
	return u.Email
}

func (u *PasskeyUser) WebAuthnDisplayName() string {
	// Safari requires a display name to be set, otherwise it does not recognize
	// security keys.
	return u.Email
}

func (u *PasskeyUser) WebAuthnCredentials() []webauthn.Credential {
	creds, err := u.repo.GetUserPasskeyCredentials(u.ID, u.rpID)
	if err != nil {
		return []webauthn.Credential{}
	}

	return creds
}

func (u *PasskeyUser) WebAuthnIcon() string {
	// this specification is deprecated but the interface requires it
	return ""
}

func NewRepository(
	db *sql.DB,
) (repo *Repository, err error) {
	rpID := viper.GetString("webauthn.rpid")
	webAuthnInstance, err := newWebAuthnInstance(rpID, viper.GetStringSlice("webauthn.rporigins"))
	if err != nil {
		return
	}

	legacyRPID := viper.GetString("webauthn.legacy-rpid")
	var legacyWebAuthnInstance *webauthn.WebAuthn
	if legacyRPID != "" && legacyRPID != rpID {
		legacyOrigins := viper.GetStringSlice("webauthn.legacy-rporigins")
		if len(legacyOrigins) == 0 {
			err = fmt.Errorf("webauthn.legacy-rporigins is required when webauthn.legacy-rpid is set")
			return
		}
		legacyWebAuthnInstance, err = newWebAuthnInstance(legacyRPID, legacyOrigins)
		if err != nil {
			return
		}
	} else {
		legacyRPID = ""
	}

	repo = &Repository{
		DB:                     db,
		webAuthnInstance:       webAuthnInstance,
		RPID:                   rpID,
		accountsURL:            viper.GetString("apps.accounts"),
		legacyRPID:             legacyRPID,
		legacyWebAuthnInstance: legacyWebAuthnInstance,
		legacyAccountsURL:      viper.GetString("apps.accounts-legacy"),
	}

	return
}

func newWebAuthnInstance(rpID string, rpOrigins []string) (*webauthn.WebAuthn, error) {
	wconfig := &webauthn.Config{
		RPDisplayName: "Ente",
		RPID:          rpID,
		RPOrigins:     rpOrigins,
		Timeouts: webauthn.TimeoutsConfig{
			Login: webauthn.TimeoutConfig{
				Enforce: true,
				Timeout: time.Duration(2) * time.Minute,
			},
			Registration: webauthn.TimeoutConfig{
				Enforce: true,
				Timeout: time.Duration(5) * time.Minute,
			},
		},
	}

	return webauthn.New(wconfig)
}

func (r *Repository) webAuthnInstanceForRPID(rpID string) (*webauthn.WebAuthn, error) {
	if rpID == r.RPID {
		return r.webAuthnInstance, nil
	}
	if rpID == r.legacyRPID {
		return r.legacyWebAuthnInstance, nil
	}
	return nil, fmt.Errorf("missing webauthn config for rp_id %q", rpID)
}

func (r *Repository) selectRPIDForUser(userID int64) (string, error) {
	legacyRPID, err := r.legacyRPIDForUser(userID)
	if err != nil {
		return "", err
	}
	if legacyRPID != "" {
		return legacyRPID, nil
	}

	return r.RPID, nil
}

func (r *Repository) rpIDForSession(session *ente.WebAuthnSession) string {
	if session.RPID != "" {
		return session.RPID
	}
	if r.legacyRPID != "" {
		return r.legacyRPID
	}
	return r.RPID
}

func (r *Repository) AccountsURLForUser(userID int64) (string, error) {
	rpID, err := r.selectRPIDForUser(userID)
	if err != nil {
		return "", err
	}
	if rpID == r.legacyRPID {
		return r.legacyAccountsURL, nil
	}
	return r.accountsURL, nil
}

func (r *Repository) GetPasskeyCount(userID int64) (count int64, err error) {
	err = r.DB.QueryRow(`SELECT COUNT(*) FROM passkeys WHERE user_id = $1 AND deleted_at IS NULL`, userID).Scan(&count)
	return
}

func (r *Repository) GetUserPasskeys(userID int64) (passkeys []ente.Passkey, err error) {
	rows, err := r.DB.Query(`
		SELECT id, user_id, friendly_name, created_at
		FROM passkeys
		WHERE user_id = $1 AND deleted_at IS NULL
	`, userID)
	if err != nil {
		err = stacktrace.Propagate(err, "")
		return
	}
	defer rows.Close()

	for rows.Next() {
		var passkey ente.Passkey
		if err = rows.Scan(
			&passkey.ID,
			&passkey.UserID,
			&passkey.FriendlyName,
			&passkey.CreatedAt,
		); err != nil {
			err = stacktrace.Propagate(err, "")
			return
		}

		passkeys = append(passkeys, passkey)
	}

	return
}

func (r *Repository) CreateBeginRegistrationData(user *ente.User) (options *protocol.CredentialCreation, session *webauthn.SessionData, id uuid.UUID, err error) {
	rpID, err := r.selectRPIDForUser(user.ID)
	if err != nil {
		err = stacktrace.Propagate(err, "")
		return
	}
	webAuthnInstance, err := r.webAuthnInstanceForRPID(rpID)
	if err != nil {
		err = stacktrace.Propagate(err, "")
		return
	}
	passkeyUser := &PasskeyUser{
		User: user,
		repo: r,
		rpID: rpID,
	}

	passkeys, err := r.GetUserPasskeys(user.ID)
	if err != nil {
		err = stacktrace.Propagate(err, "")
		return
	}
	if len(passkeys) >= ente.MaxPasskeys {
		err = stacktrace.Propagate(&ente.ErrMaxPasskeysReached, "")
		return
	}

	// Set residentKey to "required" to ensure passkeys are created as discoverable credentials.
	// This is necessary for Android to show third-party password managers (1Password, Bitwarden, etc.)
	// in the Credential Manager UI during passkey registration. Without this, Android falls back to
	// the legacy FIDO2 API which only offers Google Password Manager.
	// This feature is currently enabled only for internal users (@ente.io email addresses).
	if strings.HasSuffix(emailUtil.NormalizeEmail(user.Email), "@ente.io") {
		authSelection := protocol.AuthenticatorSelection{
			ResidentKey:        protocol.ResidentKeyRequirementRequired,
			RequireResidentKey: protocol.ResidentKeyRequired(),
			UserVerification:   protocol.VerificationPreferred,
		}
		options, session, err = webAuthnInstance.BeginRegistration(passkeyUser, webauthn.WithAuthenticatorSelection(authSelection))
	} else {
		options, session, err = webAuthnInstance.BeginRegistration(passkeyUser)
	}
	if err != nil {
		err = stacktrace.Propagate(err, "")
		return
	}

	// save session data
	marshalledSessionData, err := r.marshalSessionDataToWebAuthnSession(session, rpID)
	if err != nil {
		err = stacktrace.Propagate(err, "")
		return
	}

	id = uuid.New()

	err = r.saveSessionData(id, marshalledSessionData)
	if err != nil {
		err = stacktrace.Propagate(err, "")
		return
	}

	return
}

func (r *Repository) AddPasskeyTwoFactorSession(userID int64, sessionID string, expirationTime int64) error {
	_, err := r.DB.Exec(`INSERT INTO passkey_login_sessions(user_id, session_id, creation_time, expiration_time) VALUES($1, $2, $3, $4)`,
		userID, sessionID, ente_time.Microseconds(), expirationTime)
	return stacktrace.Propagate(err, "")
}

func (r *Repository) GetUserIDWithPasskeyTwoFactorSession(sessionID string) (userID int64, err error) {
	err = r.DB.QueryRow(`SELECT user_id FROM passkey_login_sessions WHERE session_id = $1`, sessionID).Scan(&userID)
	return
}

// IsSessionAlreadyClaimed checks if the both token_data and verified_at are not null for a given session ID
func (r *Repository) IsSessionAlreadyClaimed(sessionID string) (bool, error) {
	var verifiedAt sql.NullInt64
	err := r.DB.QueryRow(`SELECT verified_at FROM passkey_login_sessions WHERE session_id = $1`, sessionID).Scan(&verifiedAt)
	if err != nil {
		if err == sql.ErrNoRows {
			return false, nil
		}
		return false, stacktrace.Propagate(err, "")
	}
	return verifiedAt.Valid, nil
}

// StoreTokenData takes a sessionID, and tokenData, and updates the tokenData in the database
func (r *Repository) StoreTokenData(sessionID string, tokenData ente.TwoFactorAuthorizationResponse) error {
	tokenDataJson, err := json.Marshal(tokenData)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	_, err = r.DB.Exec(`UPDATE passkey_login_sessions SET token_data = $1, verified_at = now_utc_micro_seconds() WHERE session_id = $2`, tokenDataJson, sessionID)
	return stacktrace.Propagate(err, "")
}

// GetTokenData retrieves the token data associated with a given session ID.
// The function will return the token data if the following conditions are met:
// - The token data is not null.
// - The session was verified less than 5 minutes ago.
// - The token fetch count is less than 2.
// If these conditions are met, the function will also increment the token fetch count by 1.
//
// Parameters:
// - sessionID: The ID of the session for which to retrieve the token data.
//
// Returns:
// - A pointer to a TwoFactorAuthorizationResponse object containing the token data, if the conditions are met.
// - An error, if an error occurred while retrieving the token data or if the conditions are not met.
func (r *Repository) GetTokenData(sessionID string) (*ente.TwoFactorAuthorizationResponse, error) {
	var tokenDataJson []byte
	var verifiedAt sql.NullInt64
	var fetchCount int
	err := r.DB.QueryRow(`SELECT token_data, verified_at, token_fetch_cnt FROM passkey_login_sessions WHERE session_id = $1`, sessionID).Scan(&tokenDataJson, &verifiedAt, &fetchCount)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, ente.ErrNotFound
		}
		return nil, stacktrace.Propagate(err, "")
	}
	if !verifiedAt.Valid {
		return nil, &ente.ApiError{
			Code:           "SESSION_NOT_VERIFIED",
			Message:        "Session is not verified yet",
			HttpStatusCode: http.StatusBadRequest,
		}
	}
	if verifiedAt.Int64 < ente_time.MicrosecondsBeforeMinutes(TokenFetchAllowedDurationInMin) {
		return nil, &ente.ApiError{
			Code:           "INVALID_SESSION",
			Message:        "Session verified but expired now",
			HttpStatusCode: http.StatusGone,
		}
	}
	if fetchCount >= MaxSessionTokenFetchLimit {
		return nil, &ente.ApiError{
			Code:           "INVALID_SESSION",
			Message:        "Token fetch limit reached",
			HttpStatusCode: http.StatusGone,
		}
	}
	var tokenData ente.TwoFactorAuthorizationResponse
	err = json.Unmarshal(tokenDataJson, &tokenData)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	// update the token_fetch_count
	_, err = r.DB.Exec(`UPDATE passkey_login_sessions SET token_fetch_cnt = token_fetch_cnt + 1 WHERE session_id = $1`, sessionID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &tokenData, nil
}

func (r *Repository) CreateBeginAuthenticationData(user *ente.User) (options *protocol.CredentialAssertion, session *webauthn.SessionData, id uuid.UUID, err error) {
	rpID, err := r.selectRPIDForUser(user.ID)
	if err != nil {
		err = stacktrace.Propagate(err, "")
		return
	}
	webAuthnInstance, err := r.webAuthnInstanceForRPID(rpID)
	if err != nil {
		err = stacktrace.Propagate(err, "")
		return
	}
	passkeyUser := &PasskeyUser{
		User: user,
		repo: r,
		rpID: rpID,
	}

	options, session, err = webAuthnInstance.BeginLogin(passkeyUser)
	if err != nil {
		if _, ok := err.(*protocol.Error); ok {
			protocolErr := err.(*protocol.Error)
			if protocolErr.Type == "invalid_request" && protocolErr.Details == "Found no credentials for user" {
				err = stacktrace.Propagate(ente.NewBadRequestWithMessage("No passkey found for user"), "")
				return
			} else {
				err = stacktrace.Propagate(err, "error while beginning login: type %s, msg %s", protocolErr.Type, protocolErr.Details)
				return
			}
		}
		err = stacktrace.Propagate(err, "")
		return
	}

	// save session data
	marshalledSessionData, err := r.marshalSessionDataToWebAuthnSession(session, rpID)
	if err != nil {
		err = stacktrace.Propagate(err, "")
		return
	}

	id = uuid.New()

	err = r.saveSessionData(id, marshalledSessionData)
	if err != nil {
		err = stacktrace.Propagate(err, "")
		return
	}

	return
}

func (r *Repository) FinishRegistration(user *ente.User, friendlyName string, req *http.Request, sessionID uuid.UUID) (err error) {
	session, err := r.getWebAuthnSessionByID(sessionID)
	if err != nil {
		err = stacktrace.Propagate(err, "")
		return
	}

	if session.UserID != user.ID {
		err = stacktrace.NewError("session does not belong to user")
		return
	}

	rpID := r.rpIDForSession(session)
	webAuthnInstance, err := r.webAuthnInstanceForRPID(rpID)
	if err != nil {
		err = stacktrace.Propagate(err, "")
		return
	}
	passkeyUser := &PasskeyUser{
		User: user,
		repo: r,
		rpID: rpID,
	}

	sessionData, err := session.SessionData()
	if err != nil {
		err = stacktrace.Propagate(err, "")
		return
	}

	if time.Now().After(sessionData.Expires) {
		err = stacktrace.NewError("session expired")
		return
	}

	credential, err := webAuthnInstance.FinishRegistration(passkeyUser, *sessionData, req)
	if err != nil {
		if strings.Contains(err.Error(), "Error parsing attestation response") {
			err = stacktrace.Propagate(ente.NewBadRequestWithMessage(err.Error()), "")
			return
		}
		err = stacktrace.Propagate(err, "")
		return
	}

	newPasskey, err := r.createPasskey(user.ID, friendlyName)
	if err != nil {
		err = stacktrace.Propagate(err, "")
		return
	}

	passkeyCredential, err := r.marshalCredentialToPasskeyCredential(credential, newPasskey.ID, rpID)
	if err != nil {
		err = stacktrace.Propagate(err, "")
		return
	}

	err = r.createPasskeyCredential(passkeyCredential)
	if err != nil {
		err = stacktrace.Propagate(err, "")
		return
	}

	return
}

func (r *Repository) FinishAuthentication(user *ente.User, req *http.Request, sessionID uuid.UUID) (err error) {
	session, err := r.getWebAuthnSessionByID(sessionID)
	if err != nil {
		err = stacktrace.Propagate(err, "")
		return
	}

	if session.UserID != user.ID {
		err = stacktrace.NewError("session does not belong to user")
		return
	}

	rpID := r.rpIDForSession(session)
	webAuthnInstance, err := r.webAuthnInstanceForRPID(rpID)
	if err != nil {
		err = stacktrace.Propagate(err, "")
		return
	}
	passkeyUser := &PasskeyUser{
		User: user,
		repo: r,
		rpID: rpID,
	}

	sessionData, err := session.SessionData()
	if err != nil {
		err = stacktrace.Propagate(err, "")
		return
	}

	if time.Now().After(sessionData.Expires) {
		err = &ente.ApiError{Code: ente.SessionExpired, Message: "Session expired", HttpStatusCode: http.StatusGone}
		return
	}

	_, err = webAuthnInstance.FinishLogin(passkeyUser, *sessionData, req)
	if err != nil {
		logrus.Warnf("Could not finish passkey authentication: %s", err)
		err = &ente.ApiError{Code: ente.BadRequest, Message: "Invalid signature", HttpStatusCode: http.StatusUnauthorized}
		return
	}

	return
}

func (r *Repository) DeletePasskey(user *ente.User, passkeyID uuid.UUID) (err error) {
	_, err = r.DB.Exec(`
		UPDATE passkeys
		SET friendly_name = $1,
			deleted_at = $2
		WHERE id = $3 AND user_id = $4 AND deleted_at IS NULL
	`, passkeyID, ente_time.Microseconds(), passkeyID, user.ID)
	if err != nil {
		err = stacktrace.Propagate(err, "")
		return
	}

	return
}

func (r *Repository) RenamePasskey(user *ente.User, passkeyID uuid.UUID, newName string) (err error) {
	_, err = r.DB.Exec(`
		UPDATE passkeys
		SET friendly_name = $1
		WHERE id = $2 AND user_id = $3 AND deleted_at IS NULL
	`, newName, passkeyID, user.ID)
	if err != nil {
		err = stacktrace.Propagate(err, "")
		return
	}

	return
}

func (r *Repository) saveSessionData(id uuid.UUID, session *ente.WebAuthnSession) (err error) {
	_, err = r.DB.Exec(`
		INSERT INTO webauthn_sessions (
			id,
			challenge,
			user_id,
			rp_id,
			allowed_credential_ids,
			expires_at,
			user_verification_requirement,
			extensions,
			created_at
		) VALUES (
			$1,
			$2,
			$3,
			$4,
			$5,
			$6,
			$7,
			$8,
			$9
		)
		`,
		id,
		session.Challenge,
		session.UserID,
		session.RPID,
		session.AllowedCredentialIDs,
		session.ExpiresAt,
		session.UserVerificationRequirement,
		session.Extensions,
		session.CreatedAt,
	)
	return
}

func (r *Repository) marshalCredentialToPasskeyCredential(cred *webauthn.Credential, passkeyID uuid.UUID, rpID string) (*ente.PasskeyCredential, error) {
	// Convert the PublicKey to base64
	publicKeyB64 := base64.StdEncoding.EncodeToString(cred.PublicKey)

	// Convert the Transports slice to a comma-separated string
	var transports []string
	for _, t := range cred.Transport {
		transports = append(transports, string(t))
	}
	authenticatorTransports := strings.Join(transports, ",")

	// Marshal the Flags to JSON
	credentialFlags, err := json.Marshal(cred.Flags)
	if err != nil {
		return nil, err
	}

	// Marshal the Authenticator to JSON and encode AAGUID to base64
	authenticatorMap := map[string]interface{}{
		"AAGUID":       base64.StdEncoding.EncodeToString(cred.Authenticator.AAGUID),
		"SignCount":    cred.Authenticator.SignCount,
		"CloneWarning": cred.Authenticator.CloneWarning,
		"Attachment":   cred.Authenticator.Attachment,
	}
	authenticatorJSON, err := json.Marshal(authenticatorMap)
	if err != nil {
		return nil, err
	}

	// convert cred.ID into base64
	credID := base64.StdEncoding.EncodeToString(cred.ID)

	// Create the PasskeyCredential
	passkeyCred := &ente.PasskeyCredential{
		CredentialID:            credID,
		PasskeyID:               passkeyID,
		RPID:                    rpID,
		PublicKey:               publicKeyB64,
		AttestationType:         cred.AttestationType,
		AuthenticatorTransports: authenticatorTransports,
		CredentialFlags:         string(credentialFlags),
		Authenticator:           string(authenticatorJSON),
		CreatedAt:               time.Now().UnixMicro(),
	}

	return passkeyCred, nil
}

func (r *Repository) marshalSessionDataToWebAuthnSession(session *webauthn.SessionData, rpID string) (webAuthnSession *ente.WebAuthnSession, err error) {

	userID, err := byteMarshaller.ConvertBytesToInt64(session.UserID)
	if err != nil {
		return
	}

	extensionsJson, err := json.Marshal(session.Extensions)
	if err != nil {
		return
	}

	newWebAuthnSession := &ente.WebAuthnSession{
		Challenge:                   session.Challenge,
		UserID:                      userID,
		RPID:                        rpID,
		AllowedCredentialIDs:        byteMarshaller.EncodeSlices(session.AllowedCredentialIDs),
		ExpiresAt:                   session.Expires.UnixMicro(),
		UserVerificationRequirement: string(session.UserVerification),
		Extensions:                  string(extensionsJson),
		CreatedAt:                   time.Now().UnixMicro(),
	}

	return newWebAuthnSession, nil
}

func (r *Repository) GetUserPasskeyCredentials(userID int64, rpID string) (credentials []webauthn.Credential, err error) {
	if rpID == r.legacyRPID {
		return r.getLegacyPasskeyCredentials(userID, rpID)
	}
	return r.getPasskeyCredentialsForRPID(userID, rpID)
}

func (r *Repository) getPasskeyCredentialsForRPID(userID int64, rpID string) (credentials []webauthn.Credential, err error) {
	rows, err := r.DB.Query(`
		SELECT
			pc.passkey_id,
			pc.credential_id,
			$2 AS rp_id,
			pc.public_key,
			pc.attestation_type,
			pc.authenticator_transports,
			pc.credential_flags,
			pc.authenticator,
			pc.created_at
		FROM passkey_credentials pc
		JOIN passkeys p ON pc.passkey_id = p.id
		WHERE p.user_id = $1
			AND p.deleted_at IS NULL
			AND (pc.rp_id = $2 OR ($3 AND pc.rp_id IS NULL))
	`, userID, rpID, r.legacyRPID == "")
	if err != nil {
		err = stacktrace.Propagate(err, "")
		return
	}
	return webAuthnCredentialsFromRows(rows)
}

func (r *Repository) getLegacyPasskeyCredentials(userID int64, rpID string) (credentials []webauthn.Credential, err error) {
	rows, err := r.DB.Query(`
		SELECT
			pc.passkey_id,
			pc.credential_id,
			$2 AS rp_id,
			pc.public_key,
			pc.attestation_type,
			pc.authenticator_transports,
			pc.credential_flags,
			pc.authenticator,
			pc.created_at
		FROM passkey_credentials pc
		JOIN passkeys p ON pc.passkey_id = p.id
		WHERE p.user_id = $1
			AND p.deleted_at IS NULL
			AND (pc.rp_id = $2 OR pc.rp_id IS NULL)
	`, userID, rpID)
	if err != nil {
		err = stacktrace.Propagate(err, "")
		return
	}
	return webAuthnCredentialsFromRows(rows)
}

func webAuthnCredentialsFromRows(rows *sql.Rows) (credentials []webauthn.Credential, err error) {
	defer rows.Close()
	for rows.Next() {
		var pc ente.PasskeyCredential
		if err = rows.Scan(
			&pc.PasskeyID,
			&pc.CredentialID,
			&pc.RPID,
			&pc.PublicKey,
			&pc.AttestationType,
			&pc.AuthenticatorTransports,
			&pc.CredentialFlags,
			&pc.Authenticator,
			&pc.CreatedAt,
		); err != nil {
			err = stacktrace.Propagate(err, "")
			return
		}

		var cred *webauthn.Credential
		cred, err = pc.WebAuthnCredential()
		if err != nil {
			err = stacktrace.Propagate(err, "")
			return
		}

		credentials = append(credentials, *cred)
	}

	return
}

func (r *Repository) legacyRPIDForUser(userID int64) (string, error) {
	var rpID sql.NullString
	err := r.DB.QueryRow(`
		SELECT pc.rp_id
		FROM passkey_credentials pc
		JOIN passkeys p ON pc.passkey_id = p.id
		WHERE p.user_id = $1
			AND p.deleted_at IS NULL
			AND (pc.rp_id != $2 OR ($3 AND pc.rp_id IS NULL))
		LIMIT 1
	`, userID, r.RPID, r.legacyRPID != "").Scan(&rpID)
	if err == sql.ErrNoRows {
		return "", nil
	}
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}

	if r.legacyRPID == "" {
		return "", fmt.Errorf("webauthn.legacy-rpid is required for existing passkey rp_id %q", rpID.String)
	}
	if rpID.Valid && rpID.String != r.legacyRPID {
		return "", fmt.Errorf("existing passkey rp_id %q does not match configured webauthn.legacy-rpid %q", rpID.String, r.legacyRPID)
	}
	return r.legacyRPID, nil
}

func (repo *Repository) RemoveExpiredPasskeySessions() error {
	_, err := repo.DB.Exec(`DELETE FROM webauthn_sessions WHERE expires_at <= $1`,
		ente_time.Microseconds())
	if err != nil {
		return stacktrace.Propagate(err, "")
	}

	_, err = repo.DB.Exec(`DELETE FROM passkey_login_sessions WHERE expiration_time <= $1`,
		ente_time.Microseconds())

	return stacktrace.Propagate(err, "")
}
