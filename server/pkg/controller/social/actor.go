package social

import "github.com/ente/museum/ente"

// Actor represents a user identity (authenticated or anonymous) performing an action.
type Actor struct {
	UserID     *int64
	AnonUserID *string
}

// IsAnonymous reports whether the actor is using an anonymous persona.
func (a Actor) IsAnonymous() bool {
	return a.UserID == nil
}

// ValidateAnon ensures anonymous actors always supply an anonUserID.
func (a Actor) ValidateAnon() error {
	if !a.IsAnonymous() {
		return nil
	}
	if a.AnonUserID == nil || *a.AnonUserID == "" {
		return ente.ErrBadRequest
	}
	return nil
}

// UserIDValue returns the concrete userID if present.
func (a Actor) UserIDValue() (int64, bool) {
	if a.UserID == nil {
		return 0, false
	}
	return *a.UserID, true
}
