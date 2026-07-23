package controller

import (
	baserepo "github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/space/repo"
	"github.com/gin-gonic/gin"
)

type Module struct {
	Spaces     *SpacesController
	Posts      *PostsController
	Friends    *FriendsController
	Messages   *MessagesController
	Assets     *AssetsController
	Read       *ReadMarkersController
	Sessions   *SessionsController
	Cleanup    *CleanupController
	UserTokens UserTokenTerminator
	auth       authDeps
}

type UserTokenTerminator interface {
	TerminateSession(userID int64, token string) error
}

func NewModule(repos *repo.Module, userAuthRepo *baserepo.UserAuthRepository, emailNotifiers ...SpaceEmailNotifier) *Module {
	var emailNotifier SpaceEmailNotifier
	if len(emailNotifiers) > 0 {
		emailNotifier = emailNotifiers[0]
	}
	authDeps := authDeps{
		UserAuthRepo: userAuthRepo,
		SpacesRepo:   repos.Spaces,
		FriendsRepo:  repos.Friends,
		SessionsRepo: repos.Sessions,
	}
	return &Module{
		Spaces:   &SpacesController{SpacesRepo: repos.Spaces, AssetsRepo: repos.Assets, auth: authDeps},
		Posts:    &PostsController{PostsRepo: repos.Posts, SpacesRepo: repos.Spaces, FriendsRepo: repos.Friends, AssetsRepo: repos.Assets, EmailNotifier: emailNotifier, auth: authDeps},
		Friends:  &FriendsController{FriendsRepo: repos.Friends, SpacesRepo: repos.Spaces, EmailNotifier: emailNotifier},
		Messages: &MessagesController{MessagesRepo: repos.Messages, PostsRepo: repos.Posts, SpacesRepo: repos.Spaces, FriendsRepo: repos.Friends, ReadMarkersRepo: repos.Read, EmailNotifier: emailNotifier, auth: authDeps},
		Assets:   &AssetsController{AssetsRepo: repos.Assets, SpacesRepo: repos.Spaces, auth: authDeps},
		Read:     &ReadMarkersController{ReadMarkersRepo: repos.Read},
		Sessions: &SessionsController{SessionsRepo: repos.Sessions},
		Cleanup:  &CleanupController{AssetsRepo: repos.Assets},
		auth:     authDeps,
	}
}

func (m *Module) RequireSelectedSpace(c *gin.Context, rawSpaceID string) error {
	space, err := m.auth.requireSelectedSpace(c, rawSpaceID)
	if err != nil {
		return err
	}
	setSelectedSpace(c, space)
	return nil
}

func (m *Module) SelectedSpace(c *gin.Context) (*repo.SpaceRecord, error) {
	return selectedSpace(c)
}
