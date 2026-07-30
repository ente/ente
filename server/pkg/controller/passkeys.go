package controller

import (
	"fmt"
	"net/http"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/repo/passkey"
	"github.com/go-webauthn/webauthn/protocol"
	"github.com/go-webauthn/webauthn/webauthn"
	"github.com/google/uuid"
)

const (
	_passKeyNameMaxLength = 256
)

type PasskeyController struct {
	Repo     *passkey.Repository
	UserRepo *repo.UserRepository
}

func (c *PasskeyController) GetPasskeys(userID int64) (passkeys []ente.Passkey, err error) {
	user, err := c.UserRepo.Get(userID)
	if err != nil {
		return
	}

	return c.Repo.GetUserPasskeys(user.ID)
}

func (c *PasskeyController) GetPasskeysAndAccountsURL(userID int64) (passkeys []ente.Passkey, accountsURL string, err error) {
	user, err := c.UserRepo.Get(userID)
	if err != nil {
		return
	}

	passkeys, err = c.Repo.GetUserPasskeys(user.ID)
	if err != nil {
		return
	}
	accountsURL, err = c.Repo.AccountsURLForUser(user.ID)
	return
}

func (c *PasskeyController) DeletePasskey(userID int64, passkeyID uuid.UUID) (err error) {
	user, err := c.UserRepo.Get(userID)
	if err != nil {
		return
	}

	return c.Repo.DeletePasskey(&user, passkeyID)
}

// RemovePasskey2FA removes all the user's passkeys to disable passkey 2FA and fall back to TOTP based 2FA if enabled.
func (c *PasskeyController) RemovePasskey2FA(userID int64) (err error) {
	passkeys, err := c.GetPasskeys(userID)
	if err != nil {
		return
	}

	for _, passkey := range passkeys {
		err = c.DeletePasskey(userID, passkey.ID)
		if err != nil {
			return
		}
	}

	return
}

func (c *PasskeyController) RenamePasskey(userID int64, passkeyID uuid.UUID, newName string) (err error) {
	if len(newName) < 1 || len(newName) > _passKeyNameMaxLength {
		err = ente.NewBadRequestWithMessage(fmt.Sprintf("friendlyName must be between 1 and %d characters", _passKeyNameMaxLength))
		return
	}

	user, err := c.UserRepo.Get(userID)
	if err != nil {
		return
	}

	return c.Repo.RenamePasskey(&user, passkeyID, newName)
}

func (c *PasskeyController) BeginRegistration(userID int64) (options *protocol.CredentialCreation, session *webauthn.SessionData, sessionID uuid.UUID, err error) {
	user, err := c.UserRepo.Get(userID)
	if err != nil {
		return
	}

	return c.Repo.CreateBeginRegistrationData(&user)
}

func (c *PasskeyController) FinishRegistration(userID int64, friendlyName string, req *http.Request, sessionID uuid.UUID) (err error) {
	if len(friendlyName) < 1 || len(friendlyName) > _passKeyNameMaxLength {
		err = ente.NewBadRequestWithMessage(fmt.Sprintf("friendlyName must be between 1 and %d characters", _passKeyNameMaxLength))
		return
	}
	user, err := c.UserRepo.Get(userID)
	if err != nil {
		return
	}
	return c.Repo.FinishRegistration(&user, friendlyName, req, sessionID)
}
