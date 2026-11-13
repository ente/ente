package social

import "github.com/ente/museum/ente"

type Actor struct {
	UserID     *int64
	AnonUserID *string
}

func (a Actor) IsAnonymous() bool {
	return a.UserID == nil
}

func (a Actor) ValidateAnon() error {
	if !a.IsAnonymous() {
		return nil
	}
	if a.AnonUserID == nil || *a.AnonUserID == "" {
		return ente.ErrBadRequest
	}
	return nil
}

func (a Actor) UserIDValue() (int64, bool) {
	if a.UserID == nil {
		return 0, false
	}
	return *a.UserID, true
}
